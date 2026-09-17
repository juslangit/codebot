--!strict
local t = require("./testkit")
local Tokenizer = require("../src/shared/Interpreter/Tokenizer")
local Parser = require("../src/shared/Interpreter/Parser")
local Interp = require("../src/shared/Interpreter/Interp")

--[[
	A pretend robot standing on a one-dimensional strip. Enough to prove the
	interpreter drives something; the real one arrives with the room.
]]
local function makeRobot()
	local robot = {
		position = 0,
		facing = 1,
		wallAt = nil :: number?,
		log = {} :: { string },
		printed = {} :: { string },
	}

	robot.builtins = {
		move = function()
			local ahead = robot.position + robot.facing
			if robot.wallAt ~= nil and ahead == robot.wallAt then
				table.insert(robot.log, "blocked")
				return
			end
			robot.position = ahead
			table.insert(robot.log, "move")
		end,
		turnLeft = function()
			robot.facing = -robot.facing
			table.insert(robot.log, "left")
		end,
		turnRight = function()
			robot.facing = -robot.facing
			table.insert(robot.log, "right")
		end,
		blocked = function(): boolean
			return robot.wallAt ~= nil and robot.position + robot.facing == robot.wallAt
		end,
		atGoal = function(): boolean
			return robot.position >= 3
		end,
		print = function(...)
			local parts = {}
			for _, value in { ... } do
				table.insert(parts, tostring(value))
			end
			table.insert(robot.printed, table.concat(parts, " "))
		end,
	}

	return robot
end

local function build(source: string, options: any?)
	local tokens = Tokenizer.tokenize(source)
	assert(tokens.ok, "tokenizer failed: " .. tostring(tokens.err and (tokens.err :: any).message))
	local parsed = Parser.parse(tokens.tokens :: any)
	assert(parsed.ok, "parser failed: " .. tostring(parsed.err and (parsed.err :: any).message))

	local robot = makeRobot()
	local settings: any = options or {}
	settings.builtins = robot.builtins
	return Interp.create(parsed.ast :: any, settings), robot
end

-- Run to completion and report what the robot did.
local function actions(source: string): string
	local machine, robot = build(source)
	local result = machine:run()
	if not result.ok then
		return "ERROR: " .. (result.err :: any).message
	end
	return table.concat(robot.log, " ")
end

local function errorOf(source: string, options: any?): string
	local machine = build(source, options)
	local result = machine:run()
	if result.ok then
		return "NO ERROR"
	end
	return (result.err :: any).message
end

-- The line reported by each step, in order.
local function lines(source: string): string
	local machine = build(source)
	local seen = {}
	while true do
		local step = machine:step()
		if step.done then
			break
		end
		table.insert(seen, tostring(step.line))
	end
	return table.concat(seen, " ")
end

t.group("the robot does what the code says")

t.equal("one move", actions("move()"), "move")
t.equal("three moves in order", actions("move()\nmove()\nmove()"), "move move move")
t.equal("turning", actions("move()\nturnRight()\nmove()"), "move right move")
t.equal("a loop", actions("for i = 1, 3 do move() end"), "move move move")
t.equal(
	"a loop with a variable",
	actions("local n = 4\nfor i = 1, n do move() end"),
	"move move move move"
)
t.equal("a loop counting down", actions("for i = 3, 1, -1 do move() end"), "move move move")
t.equal("a loop that never runs", actions("for i = 1, 0 do move() end"), "")
t.equal(
	"while with a condition about the world",
	actions("while not atGoal() do move() end"),
	"move move move"
)
t.equal(
	"break leaves the loop",
	actions("for i = 1, 10 do move() if i == 2 then break end end"),
	"move move"
)

t.group("asking about the world")

t.equal("if that is false does nothing", actions("if blocked() then turnRight() end"), "")
t.equal("else runs instead", actions("if blocked() then turnRight() else move() end"), "move")
t.equal(
	"elseif picks the middle branch",
	actions("local n = 2\nif n == 1 then move() elseif n == 2 then turnLeft() else turnRight() end"),
	"left"
)

t.group("functions of your own")

t.equal(
	"a function is run when it is called",
	actions("local function step2()\n\tmove()\n\tmove()\nend\nstep2()\nstep2()"),
	"move move move move"
)
t.equal(
	"a function with an input",
	actions("local function go(n)\n\tfor i = 1, n do move() end\nend\ngo(3)"),
	"move move move"
)

do
	local machine, robot = build("local function double(n) return n * 2 end\nprint(double(4))")
	machine:run()
	t.equal("a function can give an answer back", robot.printed[1], "8")
end

t.group("stepping, one statement at a time")

t.equal("two statements report their own lines", lines("move()\nmove()"), "1 2")
t.equal(
	"a loop reports the for line and the body line alternately",
	lines("for i = 1, 2 do\n\tmove()\nend"),
	"1 2 1 2 1"
)
t.equal("the if line is a step of its own", lines("if true then\n\tmove()\nend"), "1 2")

do
	local machine, robot = build("move()\nmove()\nmove()")
	machine:step()
	t.equal("one step means one action so far", #robot.log, 1)
	machine:step()
	t.equal("two steps, two actions", #robot.log, 2)
	t.equal("and it is not finished yet", machine:isFinished(), false)
	machine:step()
	machine:step()
	t.equal("after the last statement it is finished", machine:isFinished(), true)
end

t.group("the variables panel")

do
	local machine = build('local steps = 3\nlocal name = "bot"\nlocal ready = true')
	machine:run()
	local vars = machine:variables()
	t.equal("a number", vars.steps, 3)
	t.equal("a piece of text", vars.name, "bot")
	t.equal("something true or false", vars.ready, true)
end

do
	local machine = build("for i = 1, 3 do\n\tmove()\nend")
	machine:step() -- the for line, i is now 1
	machine:step() -- the move
	t.equal("the counter is visible while the loop runs", machine:variables().i, 1)
end

do
	local machine = build("local function go() move() end\ngo()")
	machine:run()
	t.equal("actions are not listed as variables", machine:variables().go, nil)
end

t.group("a runaway program is stopped, not allowed to freeze anything")

t.equal(
	"a while loop that never ends",
	errorOf("while true do move() end", { maxSteps = 50 }),
	"Your code is still going after 50 steps, so it is probably repeating forever. "
		.. "Something in the loop has to make it stop."
)
t.equal(
	"a function that calls itself forever",
	errorOf("local function go()\n\tgo()\nend\ngo()", { maxDepth = 10 }),
	'"go" keeps calling itself and never stops. Something has to make it finish.'
)
t.equal(
	"a for loop counting in steps of zero",
	errorOf("for i = 1, 10, 0 do move() end"),
	"A for loop counting in steps of zero would never finish."
)

do
	local machine = build("while true do move() end", { maxSteps = 30 })
	local result = machine:run()
	t.equal("it stops at the cap, it does not run away", result.steps, 31)
end

t.group("runtime mistakes, in sentences")

t.equal(
	"calling something that does not exist",
	errorOf("jump()"),
	'There is no action called "jump". Check the spelling.'
)
t.equal(
	"using a name that was never given a value",
	errorOf("local x = steps + 1"),
	'I cannot use + here, because "steps" is nothing.'
)
t.equal(
	"adding text to a number",
	errorOf('local x = 1 + "two"'),
	'I cannot use + here, because the right side is "two".'
)
t.equal(
	"comparing things that cannot be compared",
	errorOf('local x = 1 < "two"'),
	'I cannot compare 1 with "two" using <.'
)
t.equal("dividing by zero", errorOf("local x = 1 / 0"), "I cannot divide by zero.")
t.equal(
	"joining something that is not text",
	errorOf('local x = "a" .. true'),
	"I can only join text and numbers together, but one side is true.",
	nil
)
t.equal(
	"calling a variable that holds a number",
	errorOf("local go = 3\ngo()"),
	'"go" is 3, not something that can be done.'
)

do
	local machine = build("move()\nmove()\njump()")
	local result = machine:run()
	t.equal("a runtime error carries the line it happened on", (result.err :: any).line, 3)
end

t.group("Lua's own rules, kept faithfully")

t.equal("zero is true", actions("if 0 then move() end"), "move")
t.equal("empty text is true", actions('if "" then move() end'), "move")
t.equal("false is not", actions("if false then move() end"), "")
t.equal("nothing is not", actions("if nil then move() end"), "")
t.equal("and returns the second thing", actions("if 1 and 2 then move() end"), "move")
t.equal("or stops at the first true thing", actions("if false or true then move() end"), "move")

do
	local machine, robot = build('print(1 + 2)\nprint("a" .. "b")\nprint(10 / 4)')
	machine:run()
	t.equal("arithmetic", robot.printed[1], "3")
	t.equal("joining text", robot.printed[2], "ab")
	t.equal("division gives a decimal", robot.printed[3], "2.5")
end

t.group("scope")

do
	local machine = build("local x = 1\nif true then\n\tlocal x = 2\nend")
	machine:run()
	t.equal("a name inside a block does not leak out", machine:variables().x, 1)
end

t.equal(
	"a loop counter does not survive the loop",
	errorOf("for i = 1, 2 do move() end\nlocal after = i + 1"),
	'I cannot use + here, because "i" is nothing.'
)

t.group("player code cannot reach anything we did not give it")

t.equal(
	"no print unless we supply one",
	errorOf("warn(1)"),
	'There is no action called "warn". Check the spelling.'
)
t.equal("no game", errorOf("game()"), 'There is no action called "game". Check the spelling.')
t.equal(
	"no loadstring",
	errorOf("loadstring(1)"),
	'There is no action called "loadstring". Check the spelling.'
)
t.equal(
	"no getfenv",
	errorOf("getfenv()"),
	'There is no action called "getfenv". Check the spelling.'
)
t.equal(
	"no require",
	errorOf("require(1)"),
	'There is no action called "require". Check the spelling.'
)

return t.report()
