--!strict
--[[
	RobotWorld — the rules of a room, with nothing drawn.

	This is what move() and blocked() actually do. It knows where the walls are,
	where the robot is and which way it faces, and it hands the interpreter the
	small set of actions a player is allowed to take.

	It draws nothing and touches no Roblox API, which is deliberate: the rules of
	the game can then be tested from a terminal, and the part that builds parts
	and plays tweens only has to make the result visible. When a room behaves
	wrongly, the test suite can say so without anyone pressing Play.

	Anything the player does that should be seen is pushed onto a list of events.
	The view takes that list after each step and animates it. Builtins never wait
	and never yield — a builtin that yielded would be mistaken by the interpreter
	for a step boundary.
]]

local RobotWorld = {}

export type Event = {
	kind: string,
	[any]: any,
}

-- North, East, South, West. Turning right moves one along, and wraps.
local DIRECTIONS = {
	{ name = "N", dx = 0, dy = -1 },
	{ name = "E", dx = 1, dy = 0 },
	{ name = "S", dx = 0, dy = 1 },
	{ name = "W", dx = -1, dy = 0 },
}

local FACING_TO_INDEX: { [string]: number } = { N = 1, E = 2, S = 3, W = 4 }

local World = {}
World.__index = World

export type World = typeof(setmetatable(
	{} :: {
		width: number,
		height: number,
		walls: { [string]: boolean },
		startX: number,
		startY: number,
		startDir: number,
		goalX: number,
		goalY: number,
		x: number,
		y: number,
		dir: number,
		events: { Event },
		printed: { string },
	},
	World
))

local function key(x: number, y: number): string
	return x .. "," .. y
end

--[[
	Reads a room's picture into walls, a start and a goal.
]]
function RobotWorld.create(room: any): World
	local walls: { [string]: boolean } = {}
	local startX, startY = 1, 1
	local goalX, goalY = 1, 1
	local width = 0

	for y, row in room.map do
		width = math.max(width, #row)
		for x = 1, #row do
			local character = string.sub(row, x, x)
			if character == "#" then
				walls[key(x, y)] = true
			elseif character == "R" then
				startX, startY = x, y
			elseif character == "G" then
				goalX, goalY = x, y
			end
		end
	end

	local self = setmetatable({
		width = width,
		height = #room.map,
		walls = walls,
		startX = startX,
		startY = startY,
		startDir = FACING_TO_INDEX[room.facing or "E"] or 2,
		goalX = goalX,
		goalY = goalY,
		x = startX,
		y = startY,
		dir = FACING_TO_INDEX[room.facing or "E"] or 2,
		events = {},
		printed = {},
	}, World)

	return (self :: any) :: World
end

function World.reset(self: World)
	self.x = self.startX
	self.y = self.startY
	self.dir = self.startDir
	self.events = {}
	self.printed = {}
end

function World.isWall(self: World, x: number, y: number): boolean
	if x < 1 or y < 1 or x > self.width or y > self.height then
		return true
	end
	return self.walls[key(x, y)] == true
end

function World.ahead(self: World): (number, number)
	local direction = DIRECTIONS[self.dir]
	return self.x + direction.dx, self.y + direction.dy
end

function World.isSolved(self: World): boolean
	return self.x == self.goalX and self.y == self.goalY
end

function World.facingName(self: World): string
	return DIRECTIONS[self.dir].name
end

function World.takeEvents(self: World): { Event }
	local events = self.events
	self.events = {}
	return events
end

--[[
	The entire surface the player's code can reach. Everything else — the room,
	the walls, the goal, Roblox itself — is invisible to their program.
]]
function World.builtins(self: World): { [string]: any }
	return {
		move = function()
			local nextX, nextY = self:ahead()
			if self:isWall(nextX, nextY) then
				-- Walking into a wall is not an error. The robot simply cannot
				-- go, and the player sees it try. Treating it as a crash would
				-- punish exactly the experiment room 6 is asking them to make.
				table.insert(self.events, { kind = "bump", x = nextX, y = nextY })
				return
			end
			local fromX, fromY = self.x, self.y
			self.x, self.y = nextX, nextY
			table.insert(self.events, {
				kind = "move",
				fromX = fromX,
				fromY = fromY,
				toX = nextX,
				toY = nextY,
			})
			if self:isSolved() then
				table.insert(self.events, { kind = "solved" })
			end
		end,

		turnRight = function()
			local from = self.dir
			self.dir = (self.dir % 4) + 1
			table.insert(self.events, { kind = "turn", from = from, to = self.dir })
		end,

		turnLeft = function()
			local from = self.dir
			self.dir = ((self.dir - 2) % 4) + 1
			table.insert(self.events, { kind = "turn", from = from, to = self.dir })
		end,

		blocked = function(): boolean
			local nextX, nextY = self:ahead()
			return self:isWall(nextX, nextY)
		end,

		atGoal = function(): boolean
			return self:isSolved()
		end,

		print = function(...)
			local parts = {}
			for _, value in { ... } do
				table.insert(parts, tostring(value))
			end
			local text = table.concat(parts, " ")
			table.insert(self.printed, text)
			table.insert(self.events, { kind = "say", text = text })
		end,
	}
end

return RobotWorld
