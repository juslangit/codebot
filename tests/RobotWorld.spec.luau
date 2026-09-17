--!strict
local t = require("./testkit")
local Tokenizer = require("../src/shared/Interpreter/Tokenizer")
local Parser = require("../src/shared/Interpreter/Parser")
local Interp = require("../src/shared/Interpreter/Interp")
local RobotWorld = require("../src/shared/RobotWorld")
local Rooms = require("../src/shared/Rooms")

local function worldFrom(map: { string }, facing: string?): any
	return RobotWorld.create({ map = map, facing = facing or "E" })
end

local SMALL = {
	"#####",
	"#R..#",
	"###.#",
	"###G#",
	"#####",
}

t.group("reading a room's picture")

do
	local world = worldFrom(SMALL)
	t.equal("width", world.width, 5)
	t.equal("height", world.height, 5)
	t.equal("the robot starts where R is", world.x .. "," .. world.y, "2,2")
	t.equal("facing the way the room says", world:facingName(), "E")
	t.equal("the goal is where G is", world.goalX .. "," .. world.goalY, "4,4")
	t.equal("a # is a wall", world:isWall(1, 1), true)
	t.equal("a . is not", world:isWall(3, 2), false)
	t.equal("the goal tile is not a wall", world:isWall(4, 4), false)
	t.equal("outside the room counts as wall", world:isWall(0, 2), true)
end

t.group("moving and turning")

do
	local world = worldFrom(SMALL)
	local robot = world:builtins()

	robot.move()
	t.equal("moving east increases x", world.x .. "," .. world.y, "3,2")
	robot.turnRight()
	t.equal("turning right from east faces south", world:facingName(), "S")
	robot.turnRight()
	t.equal("again faces west", world:facingName(), "W")
	robot.turnLeft()
	t.equal("turning left goes back to south", world:facingName(), "S")
	robot.turnLeft()
	robot.turnLeft()
	t.equal("left three times from east faces north", world:facingName(), "N")
end

do
	local world = worldFrom(SMALL)
	local robot = world:builtins()
	t.equal("nothing ahead at the start", robot.blocked(), false)
	robot.move()
	robot.move()
	t.equal("the wall ahead is seen", robot.blocked(), true)

	local before = world.x .. "," .. world.y
	robot.move()
	t.equal("walking into a wall does not move the robot", world.x .. "," .. world.y, before)

	local events = world:takeEvents()
	t.equal("and it is reported as a bump", events[#events].kind, "bump")
end

do
	local world = worldFrom(SMALL)
	local robot = world:builtins()
	t.equal("not at the goal yet", robot.atGoal(), false)
	robot.move()
	robot.move()
	robot.turnRight()
	robot.move()
	robot.move()
	t.equal("arriving is noticed", robot.atGoal(), true)
	t.equal("and the room counts as solved", world:isSolved(), true)
end

t.group("events, for the view to animate")

do
	local world = worldFrom(SMALL)
	local robot = world:builtins()
	robot.move()
	local events = world:takeEvents()
	t.equal("one move, one event", #events, 1)
	t.equal("it says where from", events[1].fromX .. "," .. events[1].fromY, "2,2")
	t.equal("and where to", events[1].toX .. "," .. events[1].toY, "3,2")
	t.equal("taking them empties the list", #world:takeEvents(), 0)
end

do
	local world = worldFrom(SMALL)
	local robot = world:builtins()
	robot.move()
	robot.move()
	robot.turnRight()
	robot.move()
	world:takeEvents()
	robot.move()
	local events = world:takeEvents()
	t.equal("arriving at the goal is its own event", events[#events].kind, "solved")
end

do
	local world = worldFrom(SMALL)
	local robot = world:builtins()
	robot.move()
	robot.turnRight()
	world:reset()
	t.equal("reset puts the robot back", world.x .. "," .. world.y, "2,2")
	t.equal("and faces it the right way again", world:facingName(), "E")
end

t.group("every room can actually be solved by its own target solution")

-- The important test in this file. A room whose intended answer does not work
-- is a room that will stop a player dead, and nobody would find out by reading.
local function solve(room: any): (boolean, string, number)
	local tokens = Tokenizer.tokenize(room.target)
	if not tokens.ok then
		return false, "does not tokenize: " .. (tokens.err :: any).message, 0
	end
	local parsed = Parser.parse(tokens.tokens :: any)
	if not parsed.ok then
		return false, "does not parse: " .. (parsed.err :: any).message, 0
	end

	local world = RobotWorld.create(room)
	local machine = Interp.create(parsed.ast :: any, { builtins = world:builtins() })
	local result = machine:run()

	if not result.ok then
		return false, "errors while running: " .. (result.err :: any).message, 0
	end
	if not world:isSolved() then
		return false,
			string.format(
				"ends at %d,%d but the goal is %d,%d",
				world.x,
				world.y,
				world.goalX,
				world.goalY
			),
			result.steps
	end
	return true, "solved", result.steps
end

for _, room in Rooms.all() do
	local ok, detail, steps = solve(room)
	t.check(
		string.format("room %d, %s", room.id, room.name),
		ok,
		if ok then string.format("%d steps", steps) else detail
	)
end

t.group("every room is described properly")

for _, room in Rooms.all() do
	local lineCount = 0
	for _ in string.gmatch(room.target .. "\n", "(.-)\n") do
		lineCount += 1
	end
	t.equal(string.format("room %d par matches its target's length", room.id), room.par, lineCount)
	t.check(string.format("room %d says what it teaches", room.id), #room.teaches > 0)
	t.check(string.format("room %d has a brief", room.id), #room.brief > 0)
end

do
	t.equal("there are eight rooms", Rooms.count(), 8)
	t.equal("they are numbered in order", Rooms.all()[8].id, 8)
	t.equal("a room can be looked up by number", (Rooms.get(4) :: any).name, "The Long Hall")
	t.equal("asking for one that is not there gives nothing", Rooms.get(99), nil)
end

do
	-- Every room must be rectangular, or the picture lies about where the walls are.
	for _, room in Rooms.all() do
		local widths: { [number]: boolean } = {}
		for _, row in room.map do
			widths[#row] = true
		end
		local count = 0
		for _ in widths do
			count += 1
		end
		t.equal(string.format("room %d's rows are all the same width", room.id), count, 1)
	end
end

do
	-- A room with no way in or out of the goal would be unsolvable and the
	-- target test would catch it, but this says so directly.
	for _, room in Rooms.all() do
		local world = RobotWorld.create(room)
		t.check(string.format("room %d does not start on the goal", room.id), not world:isSolved())
	end
end

return t.report()
