--!strict
--[[
	The server. It owns one thing: what a player has actually solved.

	Two rules shape the whole file.

	**Nothing a client says is believed.** A client sends the code it thinks
	solves a room; the server runs that code itself, with the same interpreter
	and the same room, and only writes a score down if the robot really reaches
	the goal (D-004). Running a stranger's program is safe because the
	interpreter hands it nothing but the robot's own actions, and it stops at a
	step cap.

	**A profile that failed to load is never saved over.** If the DataStore is
	unreachable when a player joins, they play the session with a blank profile —
	but that blank profile must not be written back, or a moment of DataStore
	trouble would erase everything they had done. Saving is only ever allowed
	for a profile we know we read.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Progress = require(Shared:WaitForChild("Progress"))
local Rooms = require(Shared:WaitForChild("Rooms"))
local Solution = require(Shared:WaitForChild("Solution"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RequestProgress = Remotes:WaitForChild("RequestProgress") :: RemoteFunction
local SubmitSolution = Remotes:WaitForChild("SubmitSolution") :: RemoteFunction

-- The version is in the name so that a change to the shape of a profile starts
-- a new store rather than meeting an old one it cannot read.
local STORE_NAME = "CodebotProgress_v1"
local AUTOSAVE_SECONDS = 90
-- One submission every so often. A solve takes a person seconds to type; this
-- only stops a modified client asking the server to run programs in a loop.
local SUBMIT_COOLDOWN = 0.4

local store: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	else
		-- Studio without "Enable Studio Access to API Services" lands here. The
		-- game has to keep working, so progress simply lives for the session.
		warn("[codebot] no DataStore available; progress will not be saved this session")
	end
end

type Session = {
	profile: Progress.Profile,
	loaded: boolean, -- false means: do not save over whatever is really stored
	dirty: boolean,
	lastSubmit: number,
}

local sessions: { [Player]: Session } = {}

local function keyFor(player: Player): string
	return "player_" .. player.UserId
end

local function load(player: Player)
	local session: Session = {
		profile = Progress.empty(),
		loaded = store == nil, -- with no store at all there is nothing to lose
		dirty = false,
		lastSubmit = 0,
	}

	if store then
		local ok, raw = pcall(function()
			return (store :: DataStore):GetAsync(keyFor(player))
		end)
		if ok then
			session.profile = Progress.sanitize(raw, Rooms.count())
			session.loaded = true
		else
			warn(
				"[codebot] could not read progress for "
					.. player.Name
					.. "; not saving this session"
			)
		end
	end

	sessions[player] = session
end

local function save(player: Player)
	local session = sessions[player]
	if not session or not session.dirty then
		return
	end
	if not store or not session.loaded then
		return
	end

	local ok = pcall(function()
		(store :: DataStore):SetAsync(keyFor(player), session.profile)
	end)
	if ok then
		session.dirty = false
	else
		warn("[codebot] could not save progress for " .. player.Name)
	end
end

local function summary(session: Session)
	return {
		best = session.profile.best,
		unlocked = Progress.unlocked(session.profile, Rooms.count()),
		saving = store ~= nil and session.loaded,
	}
end

RequestProgress.OnServerInvoke = function(player: Player)
	local session = sessions[player]
	if not session then
		load(player)
		session = sessions[player]
	end
	return summary(session)
end

SubmitSolution.OnServerInvoke = function(player: Player, roomId: any, code: any)
	local session = sessions[player]
	if not session then
		return { accepted = false, reason = "notReady" }
	end

	-- Everything arriving from a client is checked for being the shape it claims
	-- to be before it is used for anything.
	if type(roomId) ~= "number" or roomId ~= math.floor(roomId) or type(code) ~= "string" then
		return { accepted = false, reason = "malformed" }
	end

	local room = Rooms.get(roomId)
	if not room then
		return { accepted = false, reason = "noSuchRoom" }
	end

	if not Progress.isUnlocked(session.profile, roomId, Rooms.count()) then
		return { accepted = false, reason = "locked" }
	end

	local now = os.clock()
	if now - session.lastSubmit < SUBMIT_COOLDOWN then
		return { accepted = false, reason = "tooFast" }
	end
	session.lastSubmit = now

	-- The actual check: run it here, rather than believing what we were told.
	local report = Solution.run(room, code)
	if not report.ok or not report.solved then
		return { accepted = false, reason = "notSolved" }
	end

	local changed, why = Progress.record(session.profile, roomId, report.lines)
	if changed then
		session.dirty = true
	end

	return {
		accepted = true,
		why = why,
		lines = report.lines,
		best = Progress.bestFor(session.profile, roomId),
		unlocked = Progress.unlocked(session.profile, Rooms.count()),
		saving = store ~= nil and session.loaded,
	}
end

Players.PlayerAdded:Connect(load)

Players.PlayerRemoving:Connect(function(player)
	save(player)
	sessions[player] = nil
end)

-- A player who joined before this script ran.
for _, player in Players:GetPlayers() do
	if not sessions[player] then
		task.spawn(load, player)
	end
end

task.spawn(function()
	while true do
		task.wait(AUTOSAVE_SECONDS)
		for player in sessions do
			save(player)
		end
	end
end)

-- A server does not always get to finish. This is the last chance to write.
game:BindToClose(function()
	if RunService:IsStudio() then
		return
	end
	for player in sessions do
		save(player)
	end
end)

-- There is no avatar in this game. The player is the code they write, and a
-- character wandering through the room would only be in the way of the camera.
Players.CharacterAutoLoads = false
