--!strict
--[[
	CodePanel — where the player writes, and where the running line is shown.

	The code is built by tapping pieces from the palette, and the panel shows the
	result as ordinary Luau text. Nothing here is a block or a picture of code:
	what is on screen is what the player would have typed, which is the promise
	the whole game rests on.

	A TYPE button swaps the display for a text box, for anyone at a keyboard who
	would rather write it out. Switching back turns the typed text into pieces
	again, so DELETE still removes a whole word rather than a letter.

	Everything is sized from the height of the screen, because this is played on
	phones as well as desktops and a layout in fixed pixels only ever fits one of
	them.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local CodeBuilder = require(Shared:WaitForChild("CodeBuilder"))
local Theme = require(script.Parent.Theme)
local PaletteView = require(script.Parent.PaletteView)

local CodePanel = {}

local PANEL_WIDTH = 0.42

local Panel = {}
Panel.__index = Panel

export type Panel = typeof(setmetatable({} :: { [any]: any }, Panel))

local function scaleFor(height: number): number
	return math.clamp(height / 900, 0.62, 1.15)
end

function CodePanel.create(parent: Instance): Panel
	local gui = Instance.new("ScreenGui")
	gui.Name = "Codebot"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = parent

	local left = Instance.new("Frame")
	left.Name = "Left"
	left.Size = UDim2.fromScale(PANEL_WIDTH, 1)
	left.BackgroundColor3 = Theme.background
	left.BorderSizePixel = 0
	left.Parent = gui

	local edge = Instance.new("Frame")
	edge.Name = "Edge"
	edge.Size = UDim2.new(0, 3, 1, 0)
	edge.Position = UDim2.new(1, -3, 0, 0)
	edge.BackgroundColor3 = Theme.accentDim
	edge.BorderSizePixel = 0
	edge.Parent = left

	local inner = Instance.new("Frame")
	inner.Name = "Inner"
	inner.Size = UDim2.fromScale(1, 1)
	inner.BackgroundTransparency = 1
	inner.Parent = left
	local innerPad = Theme.pad(inner, 18)

	local title = Theme.label("Title", inner)
	title.Font = Theme.uiFontBold
	title.TextColor3 = Theme.accent
	title.Text = "CODEBOT"

	local roomLabel = Theme.label("Room", inner)
	roomLabel.Font = Theme.uiFontBold
	roomLabel.Text = ""

	local teachesLabel = Theme.label("Teaches", inner)
	teachesLabel.TextColor3 = Theme.accent
	teachesLabel.Text = ""

	local briefLabel = Theme.label("Brief", inner)
	briefLabel.TextWrapped = true
	briefLabel.TextColor3 = Theme.textDim
	briefLabel.Text = ""

	local codeHeading = Theme.label("CodeHeading", inner)
	codeHeading.Font = Theme.uiFontBold
	codeHeading.TextColor3 = Theme.textDim
	codeHeading.Text = "YOUR CODE"

	local typeToggle = Theme.button("TypeToggle", "TYPE", inner)
	typeToggle.BackgroundColor3 = Theme.panel

	local codeFrame = Theme.panelFrame("Code", inner)
	codeFrame.ClipsDescendants = true

	local codeInner = Instance.new("Frame")
	codeInner.Name = "Inner"
	codeInner.Size = UDim2.fromScale(1, 1)
	codeInner.BackgroundTransparency = 1
	codeInner.Parent = codeFrame
	local codePad = Theme.pad(codeInner, 12)

	local highlightBar = Instance.new("Frame")
	highlightBar.Name = "Highlight"
	highlightBar.BackgroundColor3 = Theme.accentDim
	highlightBar.BorderSizePixel = 0
	highlightBar.Visible = false
	highlightBar.ZIndex = 1
	highlightBar.Parent = codeInner
	Theme.round(highlightBar, UDim.new(0, 4))

	local display = Theme.label("Display", codeInner)
	display.Size = UDim2.fromScale(1, 1)
	display.Font = Theme.codeFont
	display.LineHeight = Theme.lineHeight
	display.ZIndex = 2
	display.Text = ""

	local hint = Theme.label("Hint", codeInner)
	hint.Size = UDim2.fromScale(1, 1)
	hint.Font = Theme.codeFont
	hint.TextColor3 = Theme.textDim
	hint.ZIndex = 2
	hint.Text = "tap a button below to write your first line"

	local box = Instance.new("TextBox")
	box.Name = "Box"
	box.Size = UDim2.fromScale(1, 1)
	box.BackgroundTransparency = 1
	box.ClearTextOnFocus = false
	box.MultiLine = true
	box.Font = Theme.codeFont
	box.LineHeight = Theme.lineHeight
	box.TextColor3 = Theme.text
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.TextYAlignment = Enum.TextYAlignment.Top
	box.PlaceholderText = "write your code here"
	box.PlaceholderColor3 = Theme.textDim
	box.Text = ""
	box.Visible = false
	box.ZIndex = 2
	box.Parent = codeInner

	local editRow = Instance.new("Frame")
	editRow.Name = "EditRow"
	editRow.BackgroundTransparency = 1
	editRow.Parent = inner

	local newLineButton = Theme.button("NewLine", "NEW LINE", editRow)
	newLineButton.Size = UDim2.new(0.44, -4, 1, 0)

	local deleteButton = Theme.button("Delete", "DELETE", editRow)
	deleteButton.Position = UDim2.new(0.44, 4, 0, 0)
	deleteButton.Size = UDim2.new(0.34, -4, 1, 0)

	local clearButton = Theme.button("Clear", "CLEAR", editRow)
	clearButton.Position = UDim2.new(0.78, 4, 0, 0)
	clearButton.Size = UDim2.new(0.22, -4, 1, 0)

	local runRow = Instance.new("Frame")
	runRow.Name = "RunRow"
	runRow.BackgroundTransparency = 1
	runRow.Parent = inner

	local runButton = Theme.button("Run", "RUN", runRow)
	runButton.Size = UDim2.new(0.62, -5, 1, 0)
	runButton.BackgroundColor3 = Theme.accentDim

	local resetButton = Theme.button("Reset", "RESET", runRow)
	resetButton.Position = UDim2.new(0.62, 5, 0, 0)
	resetButton.Size = UDim2.new(0.38, -5, 1, 0)

	local messageLabel = Theme.label("Message", inner)
	messageLabel.TextWrapped = true
	messageLabel.Text = ""

	local variablesLabel = Theme.label("Variables", inner)
	variablesLabel.Font = Theme.codeFont
	variablesLabel.TextColor3 = Theme.textDim
	variablesLabel.TextWrapped = true
	variablesLabel.Text = ""

	local nav = Instance.new("Frame")
	nav.Name = "Nav"
	nav.AnchorPoint = Vector2.new(1, 1)
	nav.Position = UDim2.new(1, -24, 1, -24)
	nav.BackgroundTransparency = 1
	nav.Parent = gui

	local prevButton = Theme.button("Prev", "BACK", nav)
	prevButton.BackgroundColor3 = Theme.panel

	local nextButton = Theme.button("Next", "NEXT ROOM", nav)
	nextButton.BackgroundColor3 = Theme.panel

	local self: any = setmetatable({
		gui = gui,
		inner = inner,
		innerPad = innerPad,
		codePad = codePad,
		builder = CodeBuilder.new(),
		typing = false,
		unit = 1,
		lineHeight = 28,

		title = title,
		roomLabel = roomLabel,
		teachesLabel = teachesLabel,
		briefLabel = briefLabel,
		codeHeading = codeHeading,
		typeToggle = typeToggle,
		codeFrame = codeFrame,
		highlightBar = highlightBar,
		display = display,
		hint = hint,
		box = box,
		editRow = editRow,
		runRow = runRow,
		runButton = runButton,
		resetButton = resetButton,
		messageLabel = messageLabel,
		variablesLabel = variablesLabel,
		nav = nav,
		prevButton = prevButton,
		nextButton = nextButton,

		onRun = nil,
		onReset = nil,
		onPrev = nil,
		onNext = nil,
	}, Panel)

	self.palette = PaletteView.create(inner, function(piece: string)
		self.builder:append(piece)
		self:refresh()
	end)

	newLineButton.Activated:Connect(function()
		self.builder:newline()
		self:refresh()
	end)
	deleteButton.Activated:Connect(function()
		self.builder:backspace()
		self:refresh()
	end)
	clearButton.Activated:Connect(function()
		self.builder:clear()
		self:refresh()
	end)
	typeToggle.Activated:Connect(function()
		self:setTyping(not self.typing)
	end)

	runButton.Activated:Connect(function()
		if self.onRun then
			self.onRun()
		end
	end)
	resetButton.Activated:Connect(function()
		if self.onReset then
			self.onReset()
		end
	end)
	prevButton.Activated:Connect(function()
		if self.onPrev then
			self.onPrev()
		end
	end)
	nextButton.Activated:Connect(function()
		if self.onNext then
			self.onNext()
		end
	end)

	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:layout()
	end)
	self:layout()
	self:refresh()

	return self :: Panel
end

--[[
	Places everything, scaled to the height of the screen. Called again whenever
	that height changes, which on a phone includes turning it sideways.
]]
function Panel.layout(self: Panel)
	local height = self.gui.AbsoluteSize.Y
	if height <= 0 then
		height = 900
	end
	local u = scaleFor(height)
	self.unit = u

	local function px(value: number): number
		return math.floor(value * u)
	end

	local function setPadding(padding: UIPadding, amount: number)
		padding.PaddingTop = UDim.new(0, amount)
		padding.PaddingBottom = UDim.new(0, amount)
		padding.PaddingLeft = UDim.new(0, amount)
		padding.PaddingRight = UDim.new(0, amount)
	end
	setPadding(self.innerPad, px(18))
	setPadding(self.codePad, px(12))

	local codeSize = px(Theme.codeSize)
	self.lineHeight = math.floor(codeSize * Theme.lineHeight)

	-- Top stack, measured downwards from the top edge.
	local y = 0
	local function place(element: GuiObject, tall: number, gap: number)
		element.AnchorPoint = Vector2.new(0, 0)
		element.Position = UDim2.fromOffset(0, y)
		element.Size = UDim2.new(1, 0, 0, tall)
		y += tall + gap
	end

	self.title.TextSize = px(Theme.titleSize)
	place(self.title, px(40), px(4))

	self.roomLabel.TextSize = px(Theme.headingSize)
	place(self.roomLabel, px(28), px(2))

	self.teachesLabel.TextSize = px(Theme.bodySize - 2)
	place(self.teachesLabel, px(22), px(6))

	self.briefLabel.TextSize = px(Theme.bodySize - 1)
	place(self.briefLabel, px(52), px(10))

	local headerTop = y
	self.codeHeading.TextSize = px(Theme.bodySize - 4)
	self.codeHeading.Position = UDim2.fromOffset(0, headerTop)
	self.codeHeading.Size = UDim2.new(0.5, 0, 0, px(24))

	self.typeToggle.TextSize = px(Theme.bodySize - 4)
	self.typeToggle.AnchorPoint = Vector2.new(1, 0)
	self.typeToggle.Position = UDim2.new(1, 0, 0, headerTop)
	self.typeToggle.Size = UDim2.fromOffset(px(96), px(26))

	local codeTop = headerTop + px(24) + px(6)

	-- Bottom stack, measured upwards from the bottom edge.
	local used = 0
	local function placeFromBottom(element: GuiObject, tall: number, gap: number)
		used += tall
		element.AnchorPoint = Vector2.new(0, 1)
		element.Position = UDim2.new(0, 0, 1, -(used - tall))
		element.Size = UDim2.new(1, 0, 0, tall)
		used += gap
	end

	self.variablesLabel.TextSize = px(Theme.bodySize - 3)
	placeFromBottom(self.variablesLabel, px(30), px(4))

	self.messageLabel.TextSize = px(Theme.bodySize - 1)
	placeFromBottom(self.messageLabel, px(46), px(8))

	self.runButton.TextSize = px(Theme.buttonSize)
	self.resetButton.TextSize = px(Theme.buttonSize)
	placeFromBottom(self.runRow, px(56), px(8))

	self.editRow.Visible = not self.typing
	self.palette.frame.Visible = not self.typing

	if not self.typing then
		for _, child in self.editRow:GetChildren() do
			if child:IsA("TextButton") then
				child.TextSize = px(Theme.bodySize - 3)
			end
		end
		placeFromBottom(self.editRow, px(46), px(8))
		placeFromBottom(self.palette.frame, px(150), px(8))
	end

	self.codeFrame.AnchorPoint = Vector2.new(0, 0)
	self.codeFrame.Position = UDim2.fromOffset(0, codeTop)
	self.codeFrame.Size = UDim2.new(1, 0, 1, -(codeTop + used))

	self.display.TextSize = codeSize
	self.hint.TextSize = codeSize
	self.box.TextSize = codeSize
	self.highlightBar.Size = UDim2.new(1, px(8), 0, self.lineHeight)

	self.nav.Size = UDim2.fromOffset(px(280), px(56))
	self.prevButton.Size = UDim2.new(0, px(80), 1, 0)
	self.prevButton.TextSize = px(Theme.bodySize)
	self.nextButton.Position = UDim2.fromOffset(px(90), 0)
	self.nextButton.Size = UDim2.new(1, -px(90), 1, 0)
	self.nextButton.TextSize = px(Theme.bodySize)

	self.palette:setUnit(u)
end

function Panel.refresh(self: Panel)
	self.display.Text = self.builder:text()
	self.hint.Visible = not self.typing and self.builder:isEmpty()
	self.display.Visible = not self.typing
	self.box.Visible = self.typing
end

function Panel.setTyping(self: Panel, typing: boolean)
	if typing == self.typing then
		return
	end

	if typing then
		self.box.Text = self.builder:text()
	else
		-- Turn what was typed back into pieces, so DELETE keeps removing whole
		-- words rather than letters.
		self.builder = CodeBuilder.fromText(self.box.Text)
	end

	self.typing = typing
	self.typeToggle.Text = if typing then "TAP" else "TYPE"
	self:layout()
	self:refresh()
end

function Panel.setRoom(self: Panel, room: any, total: number)
	self.roomLabel.Text =
		string.format("ROOM %d OF %d  -  %s", room.id, total, string.upper(room.name))
	self.teachesLabel.Text = room.teaches .. "    par " .. room.par .. " lines"
	self.briefLabel.Text = room.brief
	self.builder:clear()
	self.box.Text = ""
	self.palette:setRoom(room.id)
	self:message("", "info")
	self:setVariables({})
	self:highlight(nil)
	self:refresh()
end

function Panel.code(self: Panel): string
	return if self.typing then self.box.Text else self.builder:text()
end

function Panel.highlight(self: Panel, line: number?)
	if line == nil then
		self.highlightBar.Visible = false
		return
	end
	self.highlightBar.Visible = true
	self.highlightBar.Position =
		UDim2.fromOffset(-math.floor(4 * self.unit), (line - 1) * self.lineHeight)
end

function Panel.message(self: Panel, text: string, kind: string?)
	self.messageLabel.Text = text
	if kind == "bad" then
		self.messageLabel.TextColor3 = Theme.bad
	elseif kind == "good" then
		self.messageLabel.TextColor3 = Theme.good
	else
		self.messageLabel.TextColor3 = Theme.textDim
	end
end

function Panel.setVariables(self: Panel, variables: { [string]: any })
	local names = {}
	for name, value in variables do
		table.insert(names, name .. " = " .. tostring(value))
	end
	table.sort(names)
	self.variablesLabel.Text = if #names == 0 then "" else table.concat(names, "    ")
end

function Panel.setRunning(self: Panel, running: boolean)
	self.runButton.Text = if running then "RUNNING" else "RUN"
	self.runButton.AutoButtonColor = not running
	self.runButton.BackgroundColor3 = if running then Theme.panelLight else Theme.accentDim
	self.box.TextEditable = not running
	self.editRow.Visible = not running and not self.typing
	self.palette.frame.Visible = not running and not self.typing
	self.typeToggle.Visible = not running
	self.nav.Visible = not running
end

return CodePanel
