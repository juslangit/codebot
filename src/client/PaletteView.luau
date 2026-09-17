--!strict
--[[
	PaletteView — the buttons the player taps to write code.

	Laid out by hand rather than with a UIGridLayout, because a grid would give
	"move()" and "," the same width and the palette would read as a wall of
	identical tiles. Each button is as wide as its own word, wrapped into rows,
	the way words sit on a page.

	Pieces that are new in this room are drawn in the accent colour. That is the
	entire tutorial for a room: the new button is the lesson.
]]

local TextService = game:GetService("TextService")

local Theme = require(script.Parent.Theme)
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Palette = require(Shared:WaitForChild("Palette"))

local PaletteView = {}

local GAP = 6

local View = {}
View.__index = View

export type View = typeof(setmetatable(
	{} :: {
		frame: ScrollingFrame,
		unit: number,
		onTap: (string) -> (),
	},
	View
))

function PaletteView.create(parent: Instance, onTap: (string) -> ()): View
	local frame = Instance.new("ScrollingFrame")
	frame.Name = "Palette"
	frame.BackgroundColor3 = Theme.panel
	frame.BorderSizePixel = 0
	frame.ScrollBarThickness = 5
	frame.ScrollBarImageColor3 = Theme.edge
	frame.CanvasSize = UDim2.fromOffset(0, 0)
	frame.Parent = parent
	Theme.round(frame)
	Theme.stroke(frame)

	local self: any = setmetatable({
		frame = frame,
		unit = 1,
		onTap = onTap,
	}, View)

	return self :: View
end

function View.setUnit(self: View, unit: number)
	self.unit = unit
end

--[[
	Rebuilds the palette for a room. Called rarely — once per room — so building
	from scratch is simpler and cheaper than working out what changed.
]]
function View.setRoom(self: View, roomId: number)
	for _, child in self.frame:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local isNew: { [string]: boolean } = {}
	for _, piece in Palette.newInRoom(roomId) do
		isNew[piece] = true
	end

	local unit = self.unit
	local textSize = math.floor(Theme.bodySize * unit)
	local buttonHeight = math.floor(38 * unit)
	local labelHeight = math.floor(20 * unit)
	local width = math.max(self.frame.AbsoluteSize.X - 16, 160)

	local y = 6

	for _, group in Palette.forRoom(roomId) do
		local heading = Theme.label("Group", self.frame)
		heading.Position = UDim2.fromOffset(8, y)
		heading.Size = UDim2.new(1, -16, 0, labelHeight)
		heading.Font = Theme.uiFontBold
		heading.TextSize = math.floor((Theme.bodySize - 4) * unit)
		heading.TextColor3 = Theme.textDim
		heading.Text = group.name
		y += labelHeight + 2

		local x = 8
		for _, piece in group.pieces do
			local measured =
				TextService:GetTextSize(piece, textSize, Theme.codeFont, Vector2.new(10000, 100))
			local buttonWidth = math.ceil(measured.X) + math.floor(22 * unit)

			-- Wrap when the next button would run off the edge.
			if x > 8 and x + buttonWidth > width then
				x = 8
				y += buttonHeight + GAP
			end

			local button = Theme.button("Piece", piece, self.frame)
			button.Position = UDim2.fromOffset(x, y)
			button.Size = UDim2.fromOffset(buttonWidth, buttonHeight)
			button.Font = Theme.codeFont
			button.TextSize = textSize
			button.BackgroundColor3 = if isNew[piece] then Theme.accentDim else Theme.panelLight
			button.TextColor3 = if isNew[piece] then Theme.text else Theme.text

			local captured = piece
			button.Activated:Connect(function()
				self.onTap(captured)
			end)

			x += buttonWidth + GAP
		end

		y += buttonHeight + GAP + 6
	end

	self.frame.CanvasSize = UDim2.fromOffset(0, y + 4)
end

return PaletteView
