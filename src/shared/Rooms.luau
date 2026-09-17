--!strict
--[[
	Rooms — the curriculum, as data.

	Each room is drawn as a little picture, which is the whole point: a room is
	readable in the file, in a diff, and in a code review, and editing one is
	moving a character rather than editing coordinates.

		#  wall
		.  floor
		R  where the robot starts
		G  the goal

	Rooms are ordered so that each one introduces exactly one new idea and the
	one before it is not enough. "target" is the tidiest solution, used for the
	par score, not to check the player's answer — any program that reaches the
	goal is correct.

	No Roblox in this file. The room is a shape long before it is a place.
]]

local Rooms = {}

export type Room = {
	id: number,
	name: string,
	teaches: string,
	brief: string,
	map: { string },
	facing: string,
	target: string,
	par: number,
}

local ROOMS: { Room } = {
	{
		id = 1,
		name = "First Step",
		teaches = "a line of code does one thing",
		brief = "Write one line that moves the robot forward. Then press Run.",
		map = {
			"####",
			"#RG#",
			"####",
		},
		facing = "E",
		target = "move()",
		par = 1,
	},
	{
		id = 2,
		name = "Three Tiles",
		teaches = "lines run from top to bottom, in order",
		brief = "The goal is three tiles away. Lines run one after another, from the top.",
		map = {
			"######",
			"#R..G#",
			"######",
		},
		facing = "E",
		target = "move()\nmove()\nmove()",
		par = 3,
	},
	{
		id = 3,
		name = "The Corner",
		teaches = "there is more than one thing the robot can do",
		brief = "The robot can turn as well as move. turnRight() turns it without moving it.",
		map = {
			"#####",
			"#R..#",
			"###.#",
			"###G#",
			"#####",
		},
		facing = "E",
		target = "move()\nmove()\nturnRight()\nmove()\nmove()",
		par = 5,
	},
	{
		id = 4,
		name = "The Long Hall",
		teaches = "repeating yourself is the problem a loop solves",
		brief = "Ten tiles. You could write move() ten times. A for loop writes it once.",
		map = {
			"#############",
			"#R.........G#",
			"#############",
		},
		facing = "E",
		target = "for i = 1, 10 do\n\tmove()\nend",
		par = 3,
	},
	{
		id = 5,
		name = "Two Halls",
		teaches = "a variable gives a number a name",
		brief = "Two halls of the same length. Name the length once and use it twice.",
		map = {
			"########",
			"#R.....#",
			"######.#",
			"######.#",
			"######.#",
			"######.#",
			"######G#",
			"########",
		},
		facing = "E",
		target = "local n = 5\nfor i = 1, n do\n\tmove()\nend\nturnRight()\nfor i = 1, n do\n\tmove()\nend",
		par = 8,
	},
	{
		id = 6,
		name = "The Wall",
		teaches = "asking the world a question",
		brief = "A wall is in the way. blocked() is true when something is directly ahead.",
		map = {
			"######",
			"#R..##",
			"###.##",
			"###.##",
			"###G##",
			"######",
		},
		facing = "E",
		target = "for i = 1, 5 do\n\tif blocked() then\n\t\tturnRight()\n\tend\n\tmove()\nend",
		par = 6,
	},
	{
		id = 7,
		name = "Unknown Distance",
		teaches = "repeating until something becomes true",
		brief = "You are not told how far it is. atGoal() is true once you arrive.",
		map = {
			"##################",
			"#R..............G#",
			"##################",
		},
		facing = "E",
		target = "while not atGoal() do\n\tmove()\nend",
		par = 3,
	},
	{
		id = 8,
		name = "Your Own Move",
		teaches = "naming your own block of code",
		brief = "This staircase repeats the same shape four times. Give that shape a name, then loop it.",
		map = {
			"########",
			"#R.#####",
			"##..####",
			"###..###",
			"####..##",
			"#####G##",
			"########",
		},
		facing = "E",
		target = "local function hop()\n\tmove()\n\tturnRight()\n\tmove()\n\tturnLeft()\nend\nfor i = 1, 4 do\n\thop()\nend",
		par = 9,
	},
}

function Rooms.all(): { Room }
	return ROOMS
end

function Rooms.count(): number
	return #ROOMS
end

function Rooms.get(id: number): Room?
	for _, room in ROOMS do
		if room.id == id then
			return room
		end
	end
	return nil
end

return Rooms
