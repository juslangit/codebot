--!strict
--[[
	Interp — step 3 of 3 in the interpreter. The part that actually runs.

	The parser handed us a tree. This walks it and makes things happen. The one
	thing that makes it different from an ordinary evaluator is that it can stop
	between statements and be resumed later:

		local machine = Interp.create(ast, { builtins = ... })
		machine:step()   -- runs one statement, says which line it was
		machine:step()   -- runs the next one

	That is the whole teaching mechanism. The game steps it about twice a second,
	highlights the line it reports, and animates the robot doing it. A program that
	ran all at once would show a beginner nothing.

	Stepping is done with a coroutine. The evaluator below is written as ordinary
	recursive code — a while loop really is a while loop — and simply yields at
	each statement. Hand-rolling a state machine to get the same effect would make
	every line of this file harder to read for no gain.

	Two things are deliberately not here:

	  * No globals. move() and blocked() are handed in by whoever creates the
	    machine. Player code can reach nothing we did not give it, which is what
	    makes running a stranger's code safe.
	  * No Roblox. This file can be run and tested from a terminal.
]]

local Interp = {}

export type Node = {
	kind: string,
	line: number,
	[any]: any,
}

export type RuntimeError = {
	message: string,
	line: number,
}

export type StepResult = {
	done: boolean,
	line: number?,
	err: RuntimeError?,
}

export type RunResult = {
	ok: boolean,
	steps: number,
	err: RuntimeError?,
}

export type Options = {
	-- The actions the player's code is allowed to take. Anything not in here
	-- does not exist as far as their program is concerned.
	builtins: { [string]: any }?,
	-- A program that never finishes must not take the client with it.
	maxSteps: number?,
	-- A function that calls itself forever must not blow the Lua stack.
	maxDepth: number?,
}

local DEFAULT_MAX_STEPS = 2000
local DEFAULT_MAX_DEPTH = 64

-- A user-defined function, as stored in a variable.
type FunctionValue = {
	__codebotFunction: boolean,
	name: string,
	params: { string },
	body: { Node },
}

local function isFunctionValue(value: any): boolean
	return type(value) == "table" and (value :: any).__codebotFunction == true
end

-- How a value should be described to someone who has never coded. Deliberately
-- avoids the words "nil", "boolean" and "table".
local function describeValue(value: any): string
	local valueType = type(value)
	if value == nil then
		return "nothing"
	elseif valueType == "number" then
		return tostring(value)
	elseif valueType == "string" then
		return '"' .. value .. '"'
	elseif valueType == "boolean" then
		return if value then "true" else "false"
	elseif isFunctionValue(value) or valueType == "function" then
		return "an action"
	end
	return tostring(value)
end

-- Lua's own rule, kept faithfully: only false and nothing are untrue. Zero and
-- empty text are true, which surprises people who know other languages, and
-- teaching it wrong here would teach it wrong in Studio too.
local function isTruthy(value: any): boolean
	return value ~= false and value ~= nil
end

local Machine = {}
Machine.__index = Machine

export type Machine = typeof(setmetatable(
	{} :: {
		_thread: thread,
		_scopes: { { [string]: any } },
		_steps: number,
		_maxSteps: number,
		_maxDepth: number,
		_depth: number,
		_builtins: { [string]: any },
		_finished: boolean,
		_error: RuntimeError?,
		_caught: any,
		_lastLine: number?,
	},
	Machine
))

function Interp.create(ast: { Node }, options: Options?): Machine
	local settings = options or {}
	local builtins = settings.builtins or {}

	local self = setmetatable({
		_scopes = { {} },
		_steps = 0,
		_maxSteps = settings.maxSteps or DEFAULT_MAX_STEPS,
		_maxDepth = settings.maxDepth or DEFAULT_MAX_DEPTH,
		_depth = 0,
		_builtins = builtins,
		_finished = false,
		_error = nil,
		_caught = nil,
		_lastLine = nil,
		_thread = nil :: any,
	}, Machine)

	-- The error is caught *inside* the coroutine rather than being allowed to
	-- escape it. Lune stringifies a table thrown across a coroutine boundary,
	-- which would have lost the message and line every time; Roblox does not.
	-- Catching it here means the error object survives on either runtime, and
	-- the difference between them stops mattering. Yielding from inside a pcall
	-- is fine in Luau, so stepping still works.
	self._thread = coroutine.create(function()
		local ok, caught = pcall(function()
			self:_execBlock(ast)
		end)
		if not ok then
			self._caught = caught
		end
	end)

	return (self :: any) :: Machine
end

--[[ ------------------------------------------------------------------------
	Errors
	--------------------------------------------------------------------- ]]

function Machine._fail(_self: Machine, message: string, line: number): any
	error({ __runtimeError = true, message = message, line = line }, 0)
end

--[[ ------------------------------------------------------------------------
	Variables

	A stack of scopes. The innermost is the end of the list, so looking a name
	up means walking backwards until it is found.
	--------------------------------------------------------------------- ]]

function Machine._pushScope(self: Machine)
	table.insert(self._scopes, {})
end

function Machine._popScope(self: Machine)
	table.remove(self._scopes)
end

function Machine._declare(self: Machine, name: string, value: any)
	self._scopes[#self._scopes][name] = value
end

function Machine._lookup(self: Machine, name: string): (any, boolean)
	for index = #self._scopes, 1, -1 do
		local scope = self._scopes[index]
		if scope[name] ~= nil then
			return scope[name], true
		end
	end
	if self._builtins[name] ~= nil then
		return self._builtins[name], true
	end
	return nil, false
end

function Machine._assign(self: Machine, name: string, value: any)
	for index = #self._scopes, 1, -1 do
		if self._scopes[index][name] ~= nil then
			self._scopes[index][name] = value
			return
		end
	end
	-- Not declared anywhere: make it in the outermost scope, the way Lua would.
	self._scopes[1][name] = value
end

--[[
	The variables the player can currently see, for the side panel. Functions and
	built-in actions are left out — the panel is for values, and listing move()
	in it would only be noise.
]]
function Machine.variables(self: Machine): { [string]: any }
	local visible: { [string]: any } = {}
	for _, scope in self._scopes do
		for name, value in scope do
			if not isFunctionValue(value) and type(value) ~= "function" then
				visible[name] = value
			end
		end
	end
	return visible
end

--[[ ------------------------------------------------------------------------
	Expressions
	--------------------------------------------------------------------- ]]

-- Arithmetic wants numbers. Saying which side was wrong, and naming the
-- variable if we can, is the difference between a usable error and a shrug.
function Machine._toNumber(self: Machine, value: any, node: Node, side: string, op: string): number
	if type(value) == "number" then
		return value
	end
	local who = if node.kind == "Name" then '"' .. node.name .. '"' else "the " .. side .. " side"
	self:_fail(
		"I cannot use " .. op .. " here, because " .. who .. " is " .. describeValue(value) .. ".",
		node.line
	)
	return 0
end

function Machine._evalBinary(self: Machine, node: Node): any
	local op = node.op

	-- and / or decide whether to look at the right side at all, so they cannot
	-- be handled by evaluating both first.
	if op == "and" then
		local left = self:_eval(node.left)
		if not isTruthy(left) then
			return left
		end
		return self:_eval(node.right)
	elseif op == "or" then
		local left = self:_eval(node.left)
		if isTruthy(left) then
			return left
		end
		return self:_eval(node.right)
	end

	local left = self:_eval(node.left)
	local right = self:_eval(node.right)

	if op == "==" then
		return left == right
	elseif op == "~=" then
		return left ~= right
	elseif op == ".." then
		local function piece(value: any, source: Node): string
			if type(value) == "string" then
				return value
			elseif type(value) == "number" then
				return tostring(value)
			end
			self:_fail(
				"I can only join text and numbers together, but one side is "
					.. describeValue(value)
					.. ".",
				source.line
			)
			return ""
		end
		return piece(left, node.left) .. piece(right, node.right)
	end

	if op == "<" or op == "<=" or op == ">" or op == ">=" then
		local bothNumbers = type(left) == "number" and type(right) == "number"
		local bothText = type(left) == "string" and type(right) == "string"
		if not bothNumbers and not bothText then
			self:_fail(
				"I cannot compare "
					.. describeValue(left)
					.. " with "
					.. describeValue(right)
					.. " using "
					.. op
					.. ".",
				node.line
			)
		end
		if op == "<" then
			return left < right
		elseif op == "<=" then
			return left <= right
		elseif op == ">" then
			return left > right
		end
		return left >= right
	end

	local a = self:_toNumber(left, node.left, "left", op)
	local b = self:_toNumber(right, node.right, "right", op)

	if op == "+" then
		return a + b
	elseif op == "-" then
		return a - b
	elseif op == "*" then
		return a * b
	elseif op == "/" then
		if b == 0 then
			self:_fail("I cannot divide by zero.", node.line)
		end
		return a / b
	elseif op == "%" then
		if b == 0 then
			self:_fail("I cannot divide by zero.", node.line)
		end
		return a % b
	end

	self:_fail('I do not know how to use "' .. op .. '".', node.line)
	return nil
end

function Machine._callFunction(
	self: Machine,
	value: FunctionValue,
	args: { any },
	line: number
): any
	self._depth += 1
	if self._depth > self._maxDepth then
		self._depth -= 1
		self:_fail(
			'"'
				.. value.name
				.. '" keeps calling itself and never stops. Something has to make it finish.',
			line
		)
	end

	self:_pushScope()
	for index, param in value.params do
		self:_declare(param, args[index])
	end

	local signal = self:_execBlock(value.body)

	self:_popScope()
	self._depth -= 1

	if signal ~= nil and signal.kind == "return" then
		return signal.value
	end
	return nil
end

function Machine._evalCall(self: Machine, node: Node): any
	local target, found = self:_lookup(node.name)

	if not found then
		self:_fail(
			'There is no action called "' .. node.name .. '". Check the spelling.',
			node.line
		)
	end

	local args: { any } = {}
	for index, argument in node.args do
		args[index] = self:_eval(argument)
	end

	if isFunctionValue(target) then
		return self:_callFunction(target :: FunctionValue, args, node.line)
	end

	if type(target) == "function" then
		return target(table.unpack(args))
	end

	self:_fail(
		'"' .. node.name .. '" is ' .. describeValue(target) .. ", not something that can be done.",
		node.line
	)
	return nil
end

function Machine._eval(self: Machine, node: Node): any
	local kind = node.kind

	if kind == "Number" or kind == "String" or kind == "Boolean" then
		return node.value
	elseif kind == "Nil" then
		return nil
	elseif kind == "Name" then
		local value = self:_lookup(node.name)
		return value
	elseif kind == "Binary" then
		return self:_evalBinary(node)
	elseif kind == "Unary" then
		local value = self:_eval(node.expr)
		if node.op == "not" then
			return not isTruthy(value)
		end
		return -self:_toNumber(value, node.expr, "", "-")
	elseif kind == "Call" then
		return self:_evalCall(node)
	end

	self:_fail("I do not know how to work out a " .. tostring(kind) .. ".", node.line)
	return nil
end

--[[ ------------------------------------------------------------------------
	Statements

	_execBlock returns nil, or a signal saying the block was cut short by break
	or return, which the enclosing loop or function then acts on.
	--------------------------------------------------------------------- ]]

type Signal = { kind: string, value: any }?

-- The pause point. Everything about stepping is this one function.
function Machine._tick(self: Machine, line: number)
	self._steps += 1
	if self._steps > self._maxSteps then
		self:_fail(
			"Your code is still going after "
				.. self._maxSteps
				.. " steps, so it is probably repeating forever. "
				.. "Something in the loop has to make it stop.",
			line
		)
	end
	coroutine.yield(line)
end

function Machine._execBlock(self: Machine, body: { Node }): Signal
	for _, statement in body do
		local signal = self:_execStatement(statement)
		if signal ~= nil then
			return signal
		end
	end
	return nil
end

function Machine._execStatement(self: Machine, node: Node): Signal
	local kind = node.kind

	if kind == "ExprStat" then
		self:_eval(node.expr)
		self:_tick(node.line)
		return nil
	elseif kind == "Local" then
		local value = if node.expr then self:_eval(node.expr) else nil
		self:_declare(node.name, value)
		self:_tick(node.line)
		return nil
	elseif kind == "Assign" then
		self:_assign(node.name, self:_eval(node.expr))
		self:_tick(node.line)
		return nil
	elseif kind == "Function" then
		self:_declare(node.name, {
			__codebotFunction = true,
			name = node.name,
			params = node.params,
			body = node.body,
		})
		self:_tick(node.line)
		return nil
	elseif kind == "Return" then
		local value = if node.expr then self:_eval(node.expr) else nil
		self:_tick(node.line)
		return { kind = "return", value = value }
	elseif kind == "Break" then
		self:_tick(node.line)
		return { kind = "break", value = nil }
	elseif kind == "If" then
		for _, branch in node.branches do
			local condition = self:_eval(branch.cond)
			-- The check itself is a step, so the player watches the if line
			-- light up and can see which way it went.
			self:_tick(node.line)
			if isTruthy(condition) then
				self:_pushScope()
				local signal = self:_execBlock(branch.body)
				self:_popScope()
				return signal
			end
		end
		if node.elseBody then
			self:_pushScope()
			local signal = self:_execBlock(node.elseBody)
			self:_popScope()
			return signal
		end
		return nil
	elseif kind == "While" then
		while true do
			local condition = self:_eval(node.cond)
			self:_tick(node.line)
			if not isTruthy(condition) then
				return nil
			end
			self:_pushScope()
			local signal = self:_execBlock(node.body)
			self:_popScope()
			if signal ~= nil then
				if signal.kind == "break" then
					return nil
				end
				return signal
			end
		end
	elseif kind == "ForNumeric" then
		local from = self:_toNumber(self:_eval(node.from), node.from, "starting", "for")
		local to = self:_toNumber(self:_eval(node.to), node.to, "ending", "for")
		local step = if node.step
			then self:_toNumber(self:_eval(node.step), node.step, "counting", "for")
			else 1

		if step == 0 then
			self:_fail("A for loop counting in steps of zero would never finish.", node.line)
		end

		local counter = from
		while true do
			-- The check is a step whether it passes or not, so the player sees
			-- the for line light up one last time and the loop stop. A while
			-- loop already behaved this way; the two now match.
			local keepGoing = (step > 0 and counter <= to) or (step < 0 and counter >= to)
			self:_tick(node.line)
			if not keepGoing then
				return nil
			end
			self:_pushScope()
			self:_declare(node.var, counter)
			local signal = self:_execBlock(node.body)
			self:_popScope()
			if signal ~= nil then
				if signal.kind == "break" then
					return nil
				end
				return signal
			end
			counter += step
		end
	end

	self:_fail("I do not know how to run a " .. tostring(kind) .. ".", node.line)
	return nil
end

--[[ ------------------------------------------------------------------------
	The outside world
	--------------------------------------------------------------------- ]]

--[[
	Runs one statement. Returns the line it just ran, or done = true when the
	program has finished, or an error the player can read.
]]
function Machine.step(self: Machine): StepResult
	if self._finished then
		return { done = true, line = self._lastLine, err = self._error }
	end

	local ok, result = coroutine.resume(self._thread)

	-- resume itself only fails if something went wrong outside the player's
	-- program, because the program's own errors are caught inside the thread.
	if not ok then
		self._finished = true
		error(result, 0)
	end

	if self._caught ~= nil then
		local caught = self._caught
		self._caught = nil
		self._finished = true

		if type(caught) == "table" and (caught :: any).__runtimeError then
			local err = caught :: any
			self._error = { message = err.message, line = err.line }
			return { done = true, line = err.line, err = self._error }
		end
		-- Not the player's fault: a bug in this file. Do not disguise it.
		error(caught, 0)
	end

	if coroutine.status(self._thread) == "dead" then
		self._finished = true
		return { done = true, line = self._lastLine, err = nil }
	end

	self._lastLine = result
	return { done = false, line = result, err = nil }
end

--[[
	Runs the whole program without pausing, for the server checking a submitted
	solution and for tests. The step cap still applies.
]]
function Machine.run(self: Machine): RunResult
	while true do
		local result = self:step()
		if result.done then
			return { ok = result.err == nil, steps = self._steps, err = result.err }
		end
	end
end

function Machine.isFinished(self: Machine): boolean
	return self._finished
end

function Machine.stepsTaken(self: Machine): number
	return self._steps
end

return Interp
