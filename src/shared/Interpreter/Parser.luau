--!strict
--[[
	Parser — step 2 of 3 in the interpreter.

	The tokenizer gave us a flat list of pieces. The parser works out the shape
	those pieces make: what is inside what.

		for i = 1, 3 do move() end

		->  ForNumeric  (i, from 1, to 3)
		      body:
		        Call (move)

	A flat list cannot be run, because "inside the loop" is not a thing a list
	can say. A tree can. This is the step that turns an order of words into a
	structure with a body, and it is also where we find out that a program is
	nonsense before anyone tries to run it.

	Nothing here touches Roblox, and it does not require the Tokenizer either —
	it just reads a list of tables. That is what lets it be tested from a terminal.

	The node kinds it produces, and the fields each one carries:

		Number      value
		String      value
		Boolean     value
		Nil
		Name        name
		Binary      op, left, right
		Unary       op, expr
		Call        name, args

		Local       name, expr
		Assign      name, expr
		If          branches ({ cond, body }), elseBody
		While       cond, body
		ForNumeric  var, from, to, step, body
		Function    name, params, body
		Return      expr
		Break
		ExprStat    expr

	Every node also carries the line it started on, because the game highlights
	the line it is currently running.
]]

local Parser = {}

export type Token = {
	kind: string,
	value: string,
	line: number,
	col: number,
}

-- The AST is deliberately a plain tagged table rather than a Luau union type:
-- the interpreter reads these constantly, and narrowing a union on every access
-- would bury the part that matters. The kinds and their fields are listed above.
export type Node = {
	kind: string,
	line: number,
	[any]: any,
}

export type SyntaxError = {
	message: string,
	line: number,
	col: number,
}

export type Result = {
	ok: boolean,
	ast: { Node }?,
	err: SyntaxError?,
}

-- Binding power for each binary operator, lowest first. Matches Lua's own
-- precedence for the operators in the v1 subset.
local BINARY_PRECEDENCE: { [string]: number } = {
	["or"] = 1,
	["and"] = 2,
	["=="] = 3,
	["~="] = 3,
	["<"] = 3,
	["<="] = 3,
	[">"] = 3,
	[">="] = 3,
	[".."] = 4,
	["+"] = 5,
	["-"] = 5,
	["*"] = 6,
	["/"] = 6,
	["%"] = 6,
}

-- .. is the one right-associative operator here: "a" .. "b" .. "c" groups to
-- the right, which matters not at all for the result but keeps the tree honest.
local RIGHT_ASSOCIATIVE: { [string]: boolean } = {
	[".."] = true,
}

local UNARY_PRECEDENCE = 7

-- The word we use when telling the player which block was never closed.
local BLOCK_NAMES: { [string]: string } = {
	["if"] = "if",
	["while"] = "while loop",
	["for"] = "for loop",
	["function"] = "function",
}

function Parser.parse(tokens: { Token }): Result
	local pos = 1

	local function peek(offset: number?): Token
		return tokens[math.min(pos + (offset or 0), #tokens)]
	end

	-- Raising is the right shape for a recursive descent parser: any depth can
	-- bail out to the top. The marker field is how Parser.parse tells its own
	-- syntax errors apart from a genuine bug in this file, which must not be
	-- swallowed.
	local function fail(message: string, token: Token): any
		error({ __syntaxError = true, message = message, line = token.line, col = token.col }, 0)
	end

	local function at(kind: string, value: string?): boolean
		local token = peek()
		return token.kind == kind and (value == nil or token.value == value)
	end

	local function advance(): Token
		local token = peek()
		if token.kind ~= "eof" then
			pos += 1
		end
		return token
	end

	local function accept(kind: string, value: string?): Token?
		if at(kind, value) then
			return advance()
		end
		return nil
	end

	-- Describes the current token the way a person would say it, for error text.
	local function describe(token: Token): string
		if token.kind == "eof" then
			return "the end of your code"
		elseif token.kind == "string" then
			return "a piece of text"
		elseif token.kind == "number" then
			return "the number " .. token.value
		end
		return '"' .. token.value .. '"'
	end

	local function expect(kind: string, value: string, message: string): Token
		if at(kind, value) then
			return advance()
		end
		return fail(message .. " I found " .. describe(peek()) .. " instead.", peek())
	end

	-- The single most common beginner mistake there is, caught wherever a
	-- keyword was expected and an = turned up instead.
	local function checkEqualsConfusion()
		if at("op", "=") then
			fail(
				"To check whether two things are the same, use == with two equals signs. "
					.. "A single = is for giving something a value.",
				peek()
			)
		end
	end

	local parseExpression: (number?) -> Node
	local parseStatement: () -> Node
	local parseBlock: ({ string }) -> { Node }

	local function parseCallArguments(): { Node }
		local args: { Node } = {}
		if accept("op", ")") then
			return args
		end
		repeat
			table.insert(args, parseExpression())
		until not accept("op", ",")
		expect("op", ")", "This call is missing its closing ) bracket.")
		return args
	end

	local function parsePrimary(): Node
		local token = peek()

		if token.kind == "number" then
			advance()
			local value = tonumber(token.value)
			if value == nil then
				return fail('I cannot read "' .. token.value .. '" as a number.', token)
			end
			return { kind = "Number", value = value, line = token.line }
		elseif token.kind == "string" then
			advance()
			return { kind = "String", value = token.value, line = token.line }
		elseif at("keyword", "true") or at("keyword", "false") then
			advance()
			return { kind = "Boolean", value = token.value == "true", line = token.line }
		elseif at("keyword", "nil") then
			advance()
			return { kind = "Nil", line = token.line }
		elseif at("op", "(") then
			advance()
			local inner = parseExpression()
			expect("op", ")", "This bracket is never closed.")
			return inner
		elseif token.kind == "name" then
			advance()
			if at("op", ".") then
				return fail(
					"Reaching inside things with a dot is not part of what you can use yet.",
					peek()
				)
			end
			if accept("op", "(") then
				return {
					kind = "Call",
					name = token.value,
					args = parseCallArguments(),
					line = token.line,
				}
			end
			return { kind = "Name", name = token.value, line = token.line }
		end

		if token.kind == "keyword" then
			return fail(
				'"'
					.. token.value
					.. '" is a word Luau uses for something else, '
					.. "so it cannot go here.",
				token
			)
		end
		return fail("I expected a value here, but found " .. describe(token) .. ".", token)
	end

	local function parseUnary(): Node
		local token = peek()
		if at("keyword", "not") or at("op", "-") then
			advance()
			return {
				kind = "Unary",
				op = token.value,
				expr = parseExpression(UNARY_PRECEDENCE),
				line = token.line,
			}
		end
		return parsePrimary()
	end

	-- Precedence climbing: parse one value, then keep absorbing operators that
	-- bind at least as tightly as the level we were asked for.
	function parseExpression(minPrecedence: number?): Node
		local minimum = minPrecedence or 1
		local left = parseUnary()

		while true do
			local token = peek()
			local isOperator = token.kind == "op"
				or (token.kind == "keyword" and (token.value == "and" or token.value == "or"))
			if not isOperator then
				break
			end

			local precedence = BINARY_PRECEDENCE[token.value]
			if precedence == nil or precedence < minimum then
				break
			end

			advance()
			local nextMinimum = if RIGHT_ASSOCIATIVE[token.value]
				then precedence
				else precedence + 1
			left = {
				kind = "Binary",
				op = token.value,
				left = left,
				right = parseExpression(nextMinimum),
				line = token.line,
			}
		end

		return left
	end

	-- Closes a block, naming the line the block *opened* on. A beginner whose
	-- missing "end" is reported at the bottom of a 30-line program learns
	-- nothing; pointing at the "if" on line 4 tells them where to look.
	local function expectEnd(opener: Token)
		if at("keyword", "end") then
			advance()
			return
		end
		local name = BLOCK_NAMES[opener.value] or "block"
		-- Reported at the opener rather than at the point we gave up, so the
		-- editor highlights the "if" the player forgot to close and not the
		-- last line of their program, which is innocent.
		fail(
			"This "
				.. name
				.. " starting on line "
				.. opener.line
				.. " is never closed. "
				.. "It needs an end to say where it stops.",
			opener
		)
	end

	local function parseIf(): Node
		local opener = advance() -- "if"
		local branches: { { cond: Node, body: { Node } } } = {}

		local condition = parseExpression()
		checkEqualsConfusion()
		expect("keyword", "then", "An if needs the word then after what it is checking.")
		table.insert(branches, { cond = condition, body = parseBlock({ "elseif", "else", "end" }) })

		while at("keyword", "elseif") do
			advance()
			local elseifCondition = parseExpression()
			checkEqualsConfusion()
			expect("keyword", "then", "An elseif needs the word then after what it is checking.")
			table.insert(
				branches,
				{ cond = elseifCondition, body = parseBlock({ "elseif", "else", "end" }) }
			)
		end

		local elseBody: { Node }? = nil
		if accept("keyword", "else") then
			elseBody = parseBlock({ "end" })
		end

		expectEnd(opener)
		return { kind = "If", branches = branches, elseBody = elseBody, line = opener.line }
	end

	local function parseWhile(): Node
		local opener = advance() -- "while"
		local condition = parseExpression()
		checkEqualsConfusion()
		expect("keyword", "do", "A while loop needs the word do after what it is checking.")
		local body = parseBlock({ "end" })
		expectEnd(opener)
		return { kind = "While", cond = condition, body = body, line = opener.line }
	end

	local function parseFor(): Node
		local opener = advance() -- "for"
		local nameToken = peek()
		if nameToken.kind ~= "name" then
			return fail("A for loop needs a name to count with, like i.", nameToken)
		end
		advance()

		if at("op", ",") or at("name", "in") or at("keyword", "in") then
			return fail(
				"That kind of for loop is not available yet. Use a counting one, "
					.. "like for i = 1, 10 do.",
				peek()
			)
		end

		expect(
			"op",
			"=",
			"A counting for loop needs = and a number to start from, like for i = 1, 10 do."
		)
		local from = parseExpression()
		expect("op", ",", "A counting for loop needs a comma and a number to count up to.")
		local to = parseExpression()
		local step: Node? = nil
		if accept("op", ",") then
			step = parseExpression()
		end
		expect("keyword", "do", "A for loop needs the word do before the lines it repeats.")
		local body = parseBlock({ "end" })
		expectEnd(opener)

		return {
			kind = "ForNumeric",
			var = nameToken.value,
			from = from,
			to = to,
			step = step,
			body = body,
			line = opener.line,
		}
	end

	local function parseFunction(opener: Token): Node
		local nameToken = peek()
		if nameToken.kind ~= "name" then
			return fail("A function needs a name.", nameToken)
		end
		advance()
		expect("op", "(", "A function name is followed by ( and its list of inputs.")

		local params: { string } = {}
		if not accept("op", ")") then
			repeat
				local param = peek()
				if param.kind ~= "name" then
					return fail("A function's inputs have to be names.", param)
				end
				advance()
				table.insert(params, param.value)
			until not accept("op", ",")
			expect("op", ")", "This function's list of inputs is missing its closing ) bracket.")
		end

		local body = parseBlock({ "end" })
		expectEnd(opener)
		return {
			kind = "Function",
			name = nameToken.value,
			params = params,
			body = body,
			line = opener.line,
		}
	end

	local function parseLocal(): Node
		local opener = advance() -- "local"

		if at("keyword", "function") then
			local functionToken = advance()
			return parseFunction(functionToken)
		end

		local nameToken = peek()
		if nameToken.kind ~= "name" then
			if nameToken.kind == "keyword" then
				return fail(
					'"'
						.. nameToken.value
						.. '" is a word Luau uses for something else, '
						.. "so it cannot be used as a name.",
					nameToken
				)
			end
			return fail("local has to be followed by a name, like local steps = 3.", nameToken)
		end
		advance()

		if accept("op", "=") then
			return {
				kind = "Local",
				name = nameToken.value,
				expr = parseExpression(),
				line = opener.line,
			}
		end
		return { kind = "Local", name = nameToken.value, expr = nil, line = opener.line }
	end

	local function parseReturn(): Node
		local opener = advance() -- "return"
		local stopsHere = at("eof")
			or at("keyword", "end")
			or at("keyword", "else")
			or at("keyword", "elseif")
		if stopsHere then
			return { kind = "Return", expr = nil, line = opener.line }
		end
		return { kind = "Return", expr = parseExpression(), line = opener.line }
	end

	function parseStatement(): Node
		local token = peek()

		if token.kind == "keyword" then
			if token.value == "local" then
				return parseLocal()
			elseif token.value == "if" then
				return parseIf()
			elseif token.value == "while" then
				return parseWhile()
			elseif token.value == "for" then
				return parseFor()
			elseif token.value == "function" then
				advance()
				return parseFunction(token)
			elseif token.value == "return" then
				return parseReturn()
			elseif token.value == "break" then
				advance()
				return { kind = "Break", line = token.line }
			elseif token.value == "end" then
				return fail("There is an end here with nothing open for it to close.", token)
			elseif token.value == "else" or token.value == "elseif" then
				return fail('"' .. token.value .. '" can only be used inside an if.', token)
			elseif token.value == "then" or token.value == "do" then
				return fail('"' .. token.value .. '" cannot start a line.', token)
			end
		end

		-- Anything else is either a call, or giving a name a value.
		local expr = parseExpression()

		if at("op", "=") then
			advance()
			if expr.kind ~= "Name" then
				return fail("Only a name can be given a value, like steps = 3.", token)
			end
			return { kind = "Assign", name = expr.name, expr = parseExpression(), line = token.line }
		end

		if expr.kind ~= "Call" then
			return fail(
				"This line does not do anything. A line on its own has to be an action, "
					.. "like move(), or give something a value, like steps = 3.",
				token
			)
		end

		return { kind = "ExprStat", expr = expr, line = token.line }
	end

	function parseBlock(terminators: { string }): { Node }
		local statements: { Node } = {}
		while true do
			local token = peek()
			if token.kind == "eof" then
				break
			end
			if token.kind == "keyword" and table.find(terminators, token.value) then
				break
			end
			table.insert(statements, parseStatement())
		end
		return statements
	end

	local function parseProgram(): { Node }
		local statements = parseBlock({})
		if not at("eof") then
			fail("I did not expect " .. describe(peek()) .. " here.", peek())
		end
		return statements
	end

	local ok, result = pcall(parseProgram)

	if ok then
		return { ok = true, ast = result :: { Node }, err = nil }
	end

	-- A syntax error is something the player did. Anything else is something we
	-- did, and it must not be disguised as bad player code.
	if type(result) == "table" and (result :: any).__syntaxError then
		local err = result :: any
		return {
			ok = false,
			ast = nil,
			err = { message = err.message, line = err.line, col = err.col },
		}
	end
	error(result, 0)
end

return Parser
