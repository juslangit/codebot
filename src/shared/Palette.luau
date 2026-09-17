--!strict
--[[
	Palette — which pieces a player can tap in each room.

	Pieces arrive room by room rather than all at once. Room 1 offers three
	buttons and nothing else, which is the entire lesson: there is a thing you
	can say, and saying it makes the robot move. Showing "while" in room 1 would
	be showing a beginner a wall of words they have no use for.

	A group becomes available from its room and stays available afterwards, so
	the palette only ever grows. Nothing a player learned is taken away.

	No Roblox in here. The important test — that every room's own solution can
	actually be *built* out of the pieces that room offers — runs in the terminal.
]]

local Palette = {}

export type Group = {
	name: string,
	from: number,
	pieces: { string },
}

local GROUPS: { Group } = {
	{
		name = "ACTIONS",
		from = 1,
		pieces = { "move()", "turnRight()", "turnLeft()" },
	},
	{
		name = "REPEAT",
		from = 4,
		pieces = { "for", "i", "=", ",", "do", "end" },
	},
	{
		name = "NUMBERS",
		from = 4,
		pieces = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "10" },
	},
	{
		name = "NAMES",
		from = 5,
		pieces = { "local", "n", "steps" },
	},
	{
		name = "ASKING",
		from = 6,
		pieces = { "if", "then", "else", "not", "blocked()" },
	},
	{
		name = "UNTIL",
		from = 7,
		pieces = { "while", "atGoal()" },
	},
	{
		name = "YOUR OWN",
		from = 8,
		pieces = { "local function", "hop", "(", ")" },
	},
}

function Palette.groups(): { Group }
	return GROUPS
end

--[[
	The groups a player has by the time they reach this room.
]]
function Palette.forRoom(roomId: number): { Group }
	local available: { Group } = {}
	for _, group in GROUPS do
		if group.from <= roomId then
			table.insert(available, group)
		end
	end
	return available
end

--[[
	Every piece available in a room, flattened. Used by the palette UI and by the
	test that checks a room's own solution is buildable.
]]
function Palette.piecesForRoom(roomId: number): { string }
	local pieces: { string } = {}
	for _, group in Palette.forRoom(roomId) do
		for _, piece in group.pieces do
			table.insert(pieces, piece)
		end
	end
	return pieces
end

--[[
	The room a piece first appears in, or nil if it is not a palette piece at all.
	The UI uses it to mark what is new in a room, which is the only signposting
	the curriculum needs: the new button is the lesson.
]]
function Palette.newInRoom(roomId: number): { string }
	local pieces: { string } = {}
	for _, group in GROUPS do
		if group.from == roomId then
			for _, piece in group.pieces do
				table.insert(pieces, piece)
			end
		end
	end
	return pieces
end

return Palette
