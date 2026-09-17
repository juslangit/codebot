--!strict
--[[
	The client. Loads a room, draws it, and runs whatever the player wrote.

	The loop in `run` is the game:

		step the interpreter  ->  highlight the line it just ran
		                      ->  play whatever the robot did
		                      ->  pause, and do it again

	Solving a room is decided twice. Here, so the player is told immediately; and
	again on the server, which runs the same code through the same interpreter
	before writing anything down. The client's answer is for the player's eyes,
	the server's answer is the one that counts.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local StarterGui = game:GetService("StarterGui")
local TextChatService = game:GetService("TextChatService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Interpreter = Shared:WaitForChild("Interpreter")
local Tokenizer = require(Interpreter:WaitForChild("Tokenizer"))
local Parser = require(Interpreter:WaitForChild("Parser"))
local Interp = require(Interpreter:WaitForChild("Interp"))
local Rooms = require(Shared:WaitForChild("Rooms"))
local RobotWorld = require(Shared:WaitForChild("RobotWorld"))
local Progress = require(Shared:WaitForChild("Progress"))
local Solution = require(Shared:WaitForChild("Solution"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RequestProgress = Remotes:WaitForChild("RequestProgress") :: RemoteFunction
local SubmitSolution = Remotes:WaitForChild("SubmitSolution") :: RemoteFunction

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

local profile = Progress.empty()
local unlocked = 1
local saving = false

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

-- What the server told us, put through the same cleaning the server puts a
-- stored profile through. The server is trusted, but the shape is checked
-- anyway, because a mistake here would be a mistake about the player's history.
local function applySummary(summary: any)
	if type(summary) ~= "table" then
		return
	end
	profile = Progress.sanitize({ best = summary.best }, Rooms.count())
	unlocked = if type(summary.unlocked) == "number" then summary.unlocked else 1
	saving = summary.saving == true
end

local function canGoNext(index: number): boolean
	if index >= Rooms.count() then
		return true -- the last room wraps back to the first
	end
	return (index + 1) <= unlocked
end

local function loadRoom(index: number)
	if view then
		view:destroy()
	end

	local room = Rooms.all()[index]
	world = RobotWorld.create(room)
	view = RoomView.create(room, world, workspace)
	view:focusCamera()

	panel:setRoom(room, Rooms.count(), Progress.bestFor(profile, room.id))
	panel:setNextLocked(not canGoNext(index))
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

--[[
	Tells the server what was written and waits for it to agree. Runs in its own
	thread: the player has already seen the robot reach the goal, and should not
	be left watching a frozen screen while a DataStore is written to.
]]
local function submit(index: number, code: string, used: number)
	local room = Rooms.all()[index]
	local ok, result = pcall(function()
		return SubmitSolution:InvokeServer(index, code)
	end)

	if not ok or type(result) ~= "table" or not result.accepted then
		-- The room was still solved on this screen; it just is not recorded.
		panel:message(
			string.format("Solved in %d lines. Par is %d. (Not saved.)", used, room.par),
			"good"
		)
		return
	end

	Progress.record(profile, index, result.lines)
	unlocked = if type(result.unlocked) == "number" then result.unlocked else unlocked
	saving = result.saving == true

	panel:setBest(result.best)
	panel:setNextLocked(not canGoNext(index))

	local text
	if result.why == "improved" then
		text = string.format("Solved in %d lines. Your best yet.", result.lines)
	elseif result.why == "first" and result.lines <= room.par then
		text = string.format("Solved in %d lines. That is par.", result.lines)
	elseif result.why == "first" then
		text = string.format("Solved in %d lines. It can be done in %d.", result.lines, room.par)
	else
		text = string.format("Solved in %d lines. Your best is %d.", result.lines, result.best)
	end

	if index < Rooms.count() and unlocked > index then
		text ..= "  Room " .. (index + 1) .. " is open."
	end
	if not saving then
		text ..= "  (Progress is not being saved.)"
	end

	panel:message(text, "good")
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
	panel:setNextLocked(not canGoNext(roomIndex))

	if failure then
		panel:highlight(failure.line)
		panel:message(string.format("Line %d: %s", failure.line, failure.message), "bad")
	elseif world:isSolved() then
		panel:highlight(nil)
		local used = Solution.countLines(code)
		panel:message(string.format("Solved in %d lines. Checking…", used), "good")
		local index = roomIndex
		task.spawn(submit, index, code, used)
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
	if not canGoNext(roomIndex) then
		panel:message("Solve this room first, and the next one opens.", "info")
		return
	end
	roomIndex = if roomIndex >= Rooms.count() then 1 else roomIndex + 1
	loadRoom(roomIndex)
end

panel.onPrev = function()
	if running then
		return
	end
	roomIndex = if roomIndex <= 1 then math.min(unlocked, Rooms.count()) else roomIndex - 1
	loadRoom(roomIndex)
end

task.spawn(hideRobloxUi)
setScene()

-- Ask the server what this player has already done, then start them on the
-- first room they have not solved rather than back at the beginning.
do
	local ok, summary = pcall(function()
		return RequestProgress:InvokeServer()
	end)
	if ok then
		applySummary(summary)
	end
end

roomIndex = math.clamp(unlocked, 1, Rooms.count())
loadRoom(roomIndex)
