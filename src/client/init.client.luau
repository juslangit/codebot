--!strict
--[[
	The client. Loads a room, draws it, and runs whatever the player wrote.

	The loop at the bottom of this file is the game:

		step the interpreter  ->  highlight the line it just ran
		                      ->  play whatever the robot did
		                      ->  pause, and do it again

	Everything above it exists to make that loop possible, and every piece of it
	was already tested from a terminal before Studio was opened.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local StarterGui = game:GetService("StarterGui")
local TextChatService = game:GetService("TextChatService")

local Interpreter = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Interpreter")
local Tokenizer = require(Interpreter:WaitForChild("Tokenizer"))
local Parser = require(Interpreter:WaitForChild("Parser"))
local Interp = require(Interpreter:WaitForChild("Interp"))
local Rooms = require(ReplicatedStorage.Shared:WaitForChild("Rooms"))
local RobotWorld = require(ReplicatedStorage.Shared:WaitForChild("RobotWorld"))

local Theme = require(script.Theme)
local RoomView = require(script.RoomView)
local CodePanel = require(script.CodePanel)

-- How long to hold on each line. Slow enough to read, fast enough not to drag.
local STEP_PAUSE = 0.12

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local panel = CodePanel.create(playerGui)

local roomIndex = 1
local world: any = nil
local view: any = nil
local running = false

local function countLines(text: string): number
	local count = 0
	for line in string.gmatch(text .. "\n", "(.-)\n") do
		if string.match(line, "%S") then
			count += 1
		end
	end
	return count
end

--[[
	Turns off Roblox's own chat, player list, backpack and health bar. None of
	them mean anything in this game, and the chat bar in particular sits exactly
	where the room's instructions are.

	SetCoreGuiEnabled fails if the core scripts have not finished loading, so it
	is retried rather than called once and hoped for.
]]
local function hideRobloxUi()
	for _ = 1, 60 do
		local ok = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
		end)
		if ok then
			break
		end
		task.wait(0.1)
	end

	-- The newer chat is a separate service and is not covered by the above.
	pcall(function()
		TextChatService.ChatWindowConfiguration.Enabled = false
		TextChatService.ChatInputBarConfiguration.Enabled = false
	end)
end

--[[
	The room is indoors, so it is lit by the fittings on its own soffit rather
	than by a sun. The sun is turned down almost to nothing and the ambient kept
	low, which is what lets the cyan robot and the amber goal be the brightest
	things on screen.
]]
local function setScene()
	Lighting.Ambient = Color3.fromRGB(30, 36, 50)
	Lighting.OutdoorAmbient = Color3.fromRGB(24, 29, 42)
	Lighting.Brightness = 0.6
	Lighting.EnvironmentDiffuseScale = 0.2
	Lighting.EnvironmentSpecularScale = 0.35
	Lighting.ClockTime = 3
	Lighting.GlobalShadows = true
	Lighting.FogColor = Theme.background
	Lighting.FogStart = 90
	Lighting.FogEnd = 600
end

local function loadRoom(index: number)
	if view then
		view:destroy()
	end

	local room = Rooms.all()[index]
	world = RobotWorld.create(room)
	view = RoomView.create(room, world, workspace)
	view:focusCamera()

	panel:setRoom(room, Rooms.count())
	panel:message(room.brief, "info")
end

local function resetRoom()
	if running then
		return
	end
	world:reset()
	view:reset()
	panel:highlight(nil)
	panel:setVariables({})
	panel:message("Back to the start.", "info")
end

local function run()
	if running then
		return
	end

	local code = panel:code()
	if not string.match(code, "%S") then
		panel:message("There is nothing to run yet. Write a line first.", "bad")
		return
	end

	local tokens = Tokenizer.tokenize(code)
	if not tokens.ok then
		local err = tokens.err
		panel:highlight(err.line)
		panel:message(string.format("Line %d: %s", err.line, err.message), "bad")
		return
	end

	local parsed = Parser.parse(tokens.tokens)
	if not parsed.ok then
		local err = parsed.err
		panel:highlight(err.line)
		panel:message(string.format("Line %d: %s", err.line, err.message), "bad")
		return
	end

	running = true
	panel:setRunning(true)
	panel:message("", "info")

	world:reset()
	view:reset()

	local machine = Interp.create(parsed.ast, { builtins = world:builtins() })
	local failure: any = nil

	while true do
		local step = machine:step()

		if step.line then
			panel:highlight(step.line)
		end
		panel:setVariables(machine:variables())

		-- The robot's actions are played out here, between steps, rather than
		-- inside the builtins. A builtin that waited would be mistaken by the
		-- interpreter for a step boundary.
		for _, event in world:takeEvents() do
			view:play(event)
		end

		if step.err then
			failure = step.err
			break
		end
		if step.done then
			break
		end

		task.wait(STEP_PAUSE)
	end

	running = false
	panel:setRunning(false)

	if failure then
		panel:highlight(failure.line)
		panel:message(string.format("Line %d: %s", failure.line, failure.message), "bad")
	elseif world:isSolved() then
		local used = countLines(code)
		local room = Rooms.all()[roomIndex]
		local praise = if used <= room.par
			then "Solved in " .. used .. " lines. That is par."
			else "Solved in " .. used .. " lines. It can be done in " .. room.par .. "."
		panel:highlight(nil)
		panel:message(praise, "good")
	else
		panel:highlight(nil)
		panel:message("The robot stopped before reaching the goal. Try again.", "info")
	end
end

panel.onRun = function()
	task.spawn(run)
end

panel.onReset = resetRoom

panel.onNext = function()
	if running then
		return
	end
	roomIndex = if roomIndex >= Rooms.count() then 1 else roomIndex + 1
	loadRoom(roomIndex)
end

panel.onPrev = function()
	if running then
		return
	end
	roomIndex = if roomIndex <= 1 then Rooms.count() else roomIndex - 1
	loadRoom(roomIndex)
end

-- Spawned rather than called, so a slow retry cannot hold up the room appearing.
task.spawn(hideRobloxUi)
setScene()
loadRoom(roomIndex)
