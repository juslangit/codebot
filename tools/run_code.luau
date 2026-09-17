--!strict
--[[
	Runs a piece of code the way the game will: one step at a time, printing the
	line it is on, what the robot did, and the variables as they change.

		lune run tools/run_code.luau 'for i = 1, 3 do move() end'

	The robot here lives on a numbered strip rather than in a room. It is only
	standing in for the real one until the room exists.
]]

local process = require("@lune/process")
local Tokenizer = require("../src/shared/Interpreter/Tokenizer")
local Parser = require("../src/shared/Interpreter/Parser")
local Interp = require("../src/shared/Interpreter/Interp")

local source = process.args[1]
if not source then
	print("usage: lune run tools/run_code.luau '<code>'")
	return
end

local sourceLines = {}
for line in string.gmatch(source .. "\n", "(.-)\n") do
	table.insert(sourceLines, line)
end

local robot = { position = 0, facing = 1, did = nil :: string? }

local builtins = {
	move = function()
		robot.position += robot.facing
		robot.did = "moved to " .. robot.position
	end,
	turnLeft = function()
		robot.facing = -robot.facing
		robot.did = "turned"
	end,
	turnRight = function()
		robot.facing = -robot.facing
		robot.did = "turned"
	end,
	blocked = function(): boolean
		return robot.position + robot.facing > 5
	end,
	atGoal = function(): boolean
		return robot.position >= 3
	end,
	print = function(...)
		local parts = {}
		for _, value in { ... } do
			table.insert(parts, tostring(value))
		end
		robot.did = "said " .. table.concat(parts, " ")
	end,
}

local tokens = Tokenizer.tokenize(source)
if not tokens.ok then
	local err = tokens.err :: any
	print(string.format("\ncannot read line %d: %s", err.line, err.message))
	return
end

local parsed = Parser.parse(tokens.tokens :: any)
if not parsed.ok then
	local err = parsed.err :: any
	print(string.format("\ncannot make sense of line %d: %s", err.line, err.message))
	return
end

local machine = Interp.create(parsed.ast :: any, { builtins = builtins })

print("")
local steps = 0
while true do
	robot.did = nil
	local step = machine:step()

	if step.err then
		print(string.format("  line %d   STOPPED: %s", step.err.line, step.err.message))
		break
	end
	if step.done then
		print(string.format("\n  finished after %d steps, robot at %d", steps, robot.position))
		break
	end

	steps += 1
	local text = sourceLines[step.line :: number] or ""
	text = string.gsub(text, "^%s+", "")

	local names = {}
	for name, value in machine:variables() do
		table.insert(names, name .. "=" .. tostring(value))
	end
	table.sort(names)

	print(
		string.format(
			"  line %-3d %-30s %-18s %s",
			step.line :: number,
			text,
			robot.did or "",
			table.concat(names, " ")
		)
	)
end
