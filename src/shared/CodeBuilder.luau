--!strict
--[[
	CodeBuilder — turns tapped pieces into real Luau text.

	The player on a phone never types. They tap "for", then "i", then "=", and
	this assembles what they tapped into the thing they would have typed:

		for  i  =  1  ,  10  do   ->   for i = 1, 10 do

	Two jobs, and they are both about the result being *real* Luau rather than a
	picture of it:

	  * spacing — "move" "(" ")" has to become move(), not move ( )
	  * indenting — a line after do or then is pushed in, and end comes back out,
	    so the player is shown correctly laid-out code without ever being taught
	    to indent. When they open Studio later, their code will already look right.

	It holds the taps rather than the finished string, so backspace removes a
	whole piece — tapping move() once and deleting it once are symmetrical, which
	is not true of deleting characters.

	No Roblox in here, so all of it is tested from the terminal.
]]

local CodeBuilder = {}

local INDENT = "\t"

-- Pieces that close a block, so the line they start comes back out one level.
local DEDENTS: { [string]: boolean } = {
	["end"] = true,
	["else"] = true,
	["elseif"] = true,
}

-- Pieces that open a block when a line ends with them.
local OPENS: { [string]: boolean } = {
	["do"] = true,
	["then"] = true,
	["else"] = true,
}

-- A piece that never takes a space before it.
local TIGHT_BEFORE: { [string]: boolean } = {
	["("] = true,
	[")"] = true,
	[","] = true,
	["."] = true,
}

-- A piece that never takes a space after it.
local TIGHT_AFTER: { [string]: boolean } = {
	["("] = true,
}

type Item = { kind: string, text: string }

local Builder = {}
Builder.__index = Builder

export type Builder = typeof(setmetatable({} :: { items: { Item } }, Builder))

function CodeBuilder.new(): Builder
	return (setmetatable({ items = {} }, Builder) :: any) :: Builder
end

function Builder.append(self: Builder, snippet: string)
	table.insert(self.items, { kind = "piece", text = snippet })
end

function Builder.newline(self: Builder)
	table.insert(self.items, { kind = "newline", text = "" })
end

function Builder.backspace(self: Builder)
	if #self.items > 0 then
		table.remove(self.items)
	end
end

function Builder.clear(self: Builder)
	self.items = {}
end

function Builder.isEmpty(self: Builder): boolean
	return #self.items == 0
end

function Builder.count(self: Builder): number
	return #self.items
end

-- The piece most recently tapped, so the palette can offer what follows it.
function Builder.last(self: Builder): string?
	for index = #self.items, 1, -1 do
		if self.items[index].kind == "piece" then
			return self.items[index].text
		end
	end
	return nil
end

local function joinLine(pieces: { string }): string
	local out = ""
	for index, piece in pieces do
		if index > 1 then
			local previous = pieces[index - 1]
			local space = not TIGHT_BEFORE[piece] and not TIGHT_AFTER[previous]
			if space then
				out ..= " "
			end
		end
		out ..= piece
	end
	return out
end

-- Split the taps into lines of pieces. Kept separate because both the text and
-- the line count are wanted, and doing it twice would be a way to disagree.
local function toLines(self: Builder): { { string } }
	local lines: { { string } } = { {} }
	for _, item in self.items do
		if item.kind == "newline" then
			table.insert(lines, {})
		else
			table.insert(lines[#lines], item.text)
		end
	end
	return lines
end

function Builder.text(self: Builder): string
	local lines = toLines(self)
	local out: { string } = {}
	local level = 0

	for _, pieces in lines do
		local first = pieces[1]
		local last = pieces[#pieces]

		if first ~= nil and DEDENTS[first] then
			level = math.max(level - 1, 0)
		end

		local body = joinLine(pieces)
		table.insert(out, if body == "" then "" else string.rep(INDENT, level) .. body)

		if first ~= nil then
			local opensBlock = (last ~= nil and OPENS[last])
				or first == "function"
				or first == "local function"
			if opensBlock then
				level += 1
			end
		end
	end

	return table.concat(out, "\n")
end

--[[
	Rebuilds the taps from typed text, so that someone who typed with a keyboard
	can switch back to tapping and still have backspace remove whole pieces.

	Deliberately crude: it splits on whitespace and keeps brackets and commas as
	their own pieces. It does not need to be clever, because the result is fed
	straight back through text() and compared by the player's own eyes.
]]
function CodeBuilder.fromText(text: string): Builder
	local builder = CodeBuilder.new()
	local firstLine = true

	for line in string.gmatch(text .. "\n", "(.-)\n") do
		if not firstLine then
			builder:newline()
		end
		firstLine = false

		-- Give the tight characters room to be seen as their own pieces.
		local spaced = string.gsub(line, "([%(%),])", " %1 ")
		for word in string.gmatch(spaced, "%S+") do
			builder:append(word)
		end
	end

	return builder
end

return CodeBuilder
