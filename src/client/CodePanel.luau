--!strict
--[[
	CodePanel — where the player writes, and where the running line is shown.

	For now the code is typed into a text box, which is fine at a keyboard and
	poor on a phone. M5 replaces the typing with a palette of tappable tokens
	that writes into this same box, so the rest of the panel — the highlight, the
	messages, the variables — is built to work either way.

	The highlight is a coloured bar behind the text rather than anything clever
	with the text itself: the line height is known, so the bar is simply moved to
	(line - 1) * lineHeight. Nothing about the player's code has to be re-drawn
	while it runs.
]]

local Theme = require(script.Parent.Theme)

local CodePanel = {}

local LINE_HEIGHT = math.floor(Theme.codeSize * Theme.lineHeight)
local PANEL_WIDTH = 0.42

local Panel = {}
Panel.__index = Panel

export type Panel = typeof(setmetatable(
	{} :: {
		gui: ScreenGui,
		box: TextBox,
		highlightBar: Frame,
		roomLabel: TextLabel,
		teachesLabel: TextLabel,
		briefLabel: TextLabel,
		messageLabel: TextLabel,
		variablesLabel: TextLabel,
		parLabel: TextLabel,
		runButton: TextButton,
		resetButton: TextButton,
		prevButton: TextButton,
		nextButton: TextButton,
		onRun: (() -> ())?,
		onReset: (() -> ())?,
		onPrev: (() -> ())?,
		onNext: (() -> ())?,
	},
	Panel
))

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
	Theme.pad(inner, 22)

	local title = Theme.label("Title", inner)
	title.Size = UDim2.new(1, 0, 0, 40)
	title.Font = Theme.uiFontBold
	title.TextSize = Theme.titleSize
	title.TextColor3 = Theme.accent
	title.Text = "CODEBOT"

	local roomLabel = Theme.label("Room", inner)
	roomLabel.Position = UDim2.fromOffset(0, 46)
	roomLabel.Size = UDim2.new(1, 0, 0, 30)
	roomLabel.Font = Theme.uiFontBold
	roomLabel.TextSize = Theme.headingSize
	roomLabel.Text = ""

	local teachesLabel = Theme.label("Teaches", inner)
	teachesLabel.Position = UDim2.fromOffset(0, 78)
	teachesLabel.Size = UDim2.new(1, 0, 0, 24)
	teachesLabel.TextSize = Theme.bodySize - 2
	teachesLabel.TextColor3 = Theme.accent
	teachesLabel.Text = ""

	local briefLabel = Theme.label("Brief", inner)
	briefLabel.Position = UDim2.fromOffset(0, 106)
	briefLabel.Size = UDim2.new(1, 0, 0, 58)
	briefLabel.TextWrapped = true
	briefLabel.TextColor3 = Theme.textDim
	briefLabel.Text = ""

	local codeHeading = Theme.label("CodeHeading", inner)
	codeHeading.Position = UDim2.fromOffset(0, 170)
	codeHeading.Size = UDim2.new(0.6, 0, 0, 24)
	codeHeading.Font = Theme.uiFontBold
	codeHeading.TextSize = Theme.bodySize - 2
	codeHeading.TextColor3 = Theme.textDim
	codeHeading.Text = "YOUR CODE"

	local parLabel = Theme.label("Par", inner)
	parLabel.Position = UDim2.new(0.6, 0, 0, 170)
	parLabel.Size = UDim2.new(0.4, 0, 0, 24)
	parLabel.TextXAlignment = Enum.TextXAlignment.Right
	parLabel.TextSize = Theme.bodySize - 2
	parLabel.TextColor3 = Theme.textDim
	parLabel.Text = ""

	local codeFrame = Theme.panelFrame("Code", inner)
	codeFrame.Position = UDim2.fromOffset(0, 198)
	codeFrame.Size = UDim2.new(1, 0, 1, -198 - 190)
	codeFrame.BackgroundColor3 = Theme.panel
	codeFrame.ClipsDescendants = true

	local codeInner = Instance.new("Frame")
	codeInner.Name = "Inner"
	codeInner.Size = UDim2.fromScale(1, 1)
	codeInner.BackgroundTransparency = 1
	codeInner.Parent = codeFrame
	Theme.pad(codeInner, 12)

	local highlight = Instance.new("Frame")
	highlight.Name = "Highlight"
	highlight.Size = UDim2.new(1, 8, 0, LINE_HEIGHT)
	highlight.Position = UDim2.fromOffset(-4, 0)
	highlight.BackgroundColor3 = Theme.accentDim
	highlight.BorderSizePixel = 0
	highlight.Visible = false
	highlight.ZIndex = 1
	highlight.Parent = codeInner
	Theme.round(highlight, UDim.new(0, 4))

	local box = Instance.new("TextBox")
	box.Name = "Box"
	box.Size = UDim2.fromScale(1, 1)
	box.BackgroundTransparency = 1
	box.ClearTextOnFocus = false
	box.MultiLine = true
	box.TextEditable = true
	box.Font = Theme.codeFont
	box.TextSize = Theme.codeSize
	box.LineHeight = Theme.lineHeight
	box.TextColor3 = Theme.text
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.TextYAlignment = Enum.TextYAlignment.Top
	box.PlaceholderText = "write your code here"
	box.PlaceholderColor3 = Theme.textDim
	box.Text = ""
	box.ZIndex = 2
	box.Parent = codeInner

	local runButton = Theme.button("Run", "▶  RUN", inner)
	runButton.Position = UDim2.new(0, 0, 1, -178)
	runButton.Size = UDim2.new(0.58, -6, 0, 58)
	runButton.BackgroundColor3 = Theme.accentDim
	runButton.TextColor3 = Theme.text

	local resetButton = Theme.button("Reset", "RESET", inner)
	resetButton.Position = UDim2.new(0.58, 6, 1, -178)
	resetButton.Size = UDim2.new(0.42, -6, 0, 58)

	local messageLabel = Theme.label("Message", inner)
	messageLabel.Position = UDim2.new(0, 0, 1, -112)
	messageLabel.Size = UDim2.new(1, 0, 0, 54)
	messageLabel.TextWrapped = true
	messageLabel.TextSize = Theme.bodySize - 1
	messageLabel.Text = ""

	local variablesLabel = Theme.label("Variables", inner)
	variablesLabel.Position = UDim2.new(0, 0, 1, -52)
	variablesLabel.Size = UDim2.new(1, 0, 0, 48)
	variablesLabel.Font = Theme.codeFont
	variablesLabel.TextSize = Theme.bodySize - 2
	variablesLabel.TextColor3 = Theme.textDim
	variablesLabel.TextWrapped = true
	variablesLabel.Text = ""

	-- Room navigation sits over the room itself, out of the way of the writing.
	local nav = Instance.new("Frame")
	nav.Name = "Nav"
	nav.AnchorPoint = Vector2.new(1, 1)
	nav.Position = UDim2.new(1, -24, 1, -24)
	nav.Size = UDim2.fromOffset(260, 56)
	nav.BackgroundTransparency = 1
	nav.Parent = gui

	local prevButton = Theme.button("Prev", "◀", nav)
	prevButton.Size = UDim2.new(0, 56, 1, 0)
	prevButton.BackgroundColor3 = Theme.panel

	local nextButton = Theme.button("Next", "NEXT ROOM  ▶", nav)
	nextButton.Position = UDim2.fromOffset(66, 0)
	nextButton.Size = UDim2.new(1, -66, 1, 0)
	nextButton.BackgroundColor3 = Theme.panel

	local self: any = setmetatable({
		gui = gui,
		box = box,
		highlightBar = highlight,
		roomLabel = roomLabel,
		teachesLabel = teachesLabel,
		briefLabel = briefLabel,
		messageLabel = messageLabel,
		variablesLabel = variablesLabel,
		parLabel = parLabel,
		runButton = runButton,
		resetButton = resetButton,
		prevButton = prevButton,
		nextButton = nextButton,
		onRun = nil,
		onReset = nil,
		onPrev = nil,
		onNext = nil,
	}, Panel)

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

	return self :: Panel
end

function Panel.setRoom(self: Panel, room: any, total: number)
	self.roomLabel.Text =
		string.format("ROOM %d OF %d  —  %s", room.id, total, string.upper(room.name))
	self.teachesLabel.Text = room.teaches
	self.briefLabel.Text = room.brief
	self.parLabel.Text = string.format("par: %d lines", room.par)
	self.box.Text = ""
	self:message("", "info")
	self:setVariables({})
	self:highlight(nil)
end

function Panel.code(self: Panel): string
	return self.box.Text
end

function Panel.highlight(self: Panel, line: number?)
	if line == nil then
		self.highlightBar.Visible = false
		return
	end
	self.highlightBar.Visible = true
	self.highlightBar.Position = UDim2.fromOffset(-4, (line - 1) * LINE_HEIGHT)
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
	self.runButton.Text = if running then "RUNNING…" else "▶  RUN"
	self.runButton.AutoButtonColor = not running
	self.runButton.BackgroundColor3 = if running then Theme.panelLight else Theme.accentDim
	self.box.TextEditable = not running
	self.prevButton.Visible = not running
	self.nextButton.Visible = not running
end

return CodePanel
