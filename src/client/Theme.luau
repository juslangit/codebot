--!strict
--[[
	Theme — every colour and size in one place.

	Sizes are deliberately generous. This is a game played on phones and read by
	people who are concentrating on unfamiliar words; small text is not a style
	choice here, it is a way of losing players.
]]

local Theme = {}

-- A workshop at night: dark metal, lit dials, a warm goal to walk towards.
Theme.background = Color3.fromRGB(14, 18, 28)
Theme.panel = Color3.fromRGB(22, 28, 42)
Theme.panelLight = Color3.fromRGB(32, 40, 58)
Theme.edge = Color3.fromRGB(52, 64, 88)

Theme.accent = Color3.fromRGB(64, 214, 224) -- cyan: the robot, the run button
Theme.accentDim = Color3.fromRGB(30, 96, 104)
Theme.warm = Color3.fromRGB(255, 176, 64) -- amber: the goal
Theme.good = Color3.fromRGB(104, 222, 138)
Theme.bad = Color3.fromRGB(255, 108, 108)

Theme.text = Color3.fromRGB(232, 240, 255)
Theme.textDim = Color3.fromRGB(150, 166, 194)

Theme.floor = Color3.fromRGB(46, 56, 78)
Theme.floorAlt = Color3.fromRGB(38, 47, 67)
Theme.wall = Color3.fromRGB(70, 84, 112)

-- Text sizes. Large on purpose.
Theme.titleSize = 34
Theme.headingSize = 24
Theme.bodySize = 20
Theme.codeSize = 22
Theme.buttonSize = 24

Theme.lineHeight = 1.3
Theme.corner = UDim.new(0, 10)

Theme.codeFont = Enum.Font.Code
Theme.uiFont = Enum.Font.GothamMedium
Theme.uiFontBold = Enum.Font.GothamBold

--[[
	Small helpers, so that every panel in the game is built the same way and a
	change to the look happens in one place rather than twenty.
]]

function Theme.round(instance: Instance, radius: UDim?): UICorner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius or Theme.corner
	corner.Parent = instance
	return corner
end

function Theme.stroke(instance: Instance, color: Color3?, thickness: number?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or Theme.edge
	stroke.Thickness = thickness or 2
	stroke.Parent = instance
	return stroke
end

function Theme.pad(instance: Instance, amount: number): UIPadding
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, amount)
	padding.PaddingBottom = UDim.new(0, amount)
	padding.PaddingLeft = UDim.new(0, amount)
	padding.PaddingRight = UDim.new(0, amount)
	padding.Parent = instance
	return padding
end

function Theme.panelFrame(name: string, parent: Instance): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundColor3 = Theme.panel
	frame.BorderSizePixel = 0
	frame.Parent = parent
	Theme.round(frame)
	Theme.stroke(frame)
	return frame
end

function Theme.label(name: string, parent: Instance): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Font = Theme.uiFont
	label.TextSize = Theme.bodySize
	label.TextColor3 = Theme.text
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.RichText = false
	label.Parent = parent
	return label
end

function Theme.button(name: string, text: string, parent: Instance): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Text = text
	button.Font = Theme.uiFontBold
	button.TextSize = Theme.buttonSize
	button.TextColor3 = Theme.text
	button.BackgroundColor3 = Theme.panelLight
	button.BorderSizePixel = 0
	button.AutoButtonColor = true
	button.Parent = parent
	Theme.round(button)
	Theme.stroke(button)
	return button
end

return Theme
