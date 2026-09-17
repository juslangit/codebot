--!strict
--[[
	Solution — does this code solve this room?

	One answer, used in two places that must not be allowed to disagree. The
	client runs it to decide what to say to the player; the server runs it again
	before writing anything down, because a client can be modified and a best
	line count is a number worth lying about (D-004).

	Both call the same function, so there is no second implementation of "solved"
	to drift out of step with the first.

	This is also the one file in `shared` that requires its neighbours, so it
	carries the dual-target require: Roblox resolves a module through the data
	model, Lune through the file system, and `script` exists only in Roblox.
]]

local isRoblox = script ~= nil

local Tokenizer = if isRoblox
	then require(script.Parent.Interpreter.Tokenizer)
	else require("./Interpreter/Tokenizer")
local Parser = if isRoblox
	then require(script.Parent.Interpreter.Parser)
	else require("./Interpreter/Parser")
local Interp = if isRoblox
	then require(script.Parent.Interpreter.Interp)
	else require("./Interpreter/Interp")
local RobotWorld = if isRoblox then require(script.Parent.RobotWorld) else require("./RobotWorld")

local Solution = {}

-- Longer than any room needs, short enough that a submitted program cannot be
-- used to make the server think for a noticeable length of time.
local MAX_CODE_LENGTH = 4000
local MAX_STEPS = 4000

export type Report = {
	ok: boolean, -- it parsed and ran without stopping on an error
	solved: boolean,
	lines: number, -- lines that have something on them
	steps: number,
	err: { message: string, line: number }?,
}

--[[
	Counts the lines that do something. Blank lines are free, so a player is
	never punished for laying their code out readably.
]]
function Solution.countLines(code: string): number
	local count = 0
	for line in string.gmatch(code .. "\n", "(.-)\n") do
		if string.match(line, "%S") then
			count += 1
		end
	end
	return count
end

function Solution.run(room: any, code: string): Report
	local lines = Solution.countLines(code)

	if #code > MAX_CODE_LENGTH then
		return {
			ok = false,
			solved = false,
			lines = lines,
			steps = 0,
			err = { message = "That program is too long for this game.", line = 1 },
		}
	end

	local tokens = Tokenizer.tokenize(code)
	if not tokens.ok then
		local err = tokens.err :: any
		return {
			ok = false,
			solved = false,
			lines = lines,
			steps = 0,
			err = { message = err.message, line = err.line },
		}
	end

	local parsed = Parser.parse(tokens.tokens :: any)
	if not parsed.ok then
		local err = parsed.err :: any
		return {
			ok = false,
			solved = false,
			lines = lines,
			steps = 0,
			err = { message = err.message, line = err.line },
		}
	end

	local world = RobotWorld.create(room)
	local machine = Interp.create(parsed.ast :: any, {
		builtins = world:builtins(),
		maxSteps = MAX_STEPS,
	})
	local result = machine:run()

	return {
		ok = result.ok,
		solved = world:isSolved(),
		lines = lines,
		steps = result.steps,
		err = result.err,
	}
end

return Solution
