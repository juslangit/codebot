--!strict
--[[
	Progress — what a player has solved, and what they are allowed to open.

	A profile is deliberately small and dull:

		{ best = { ["1"] = 1, ["2"] = 3 } }

	room number as a *string*, best line count as a number. The keys are strings
	because a profile goes into a DataStore, which stores it as JSON: a table
	with number keys is written as an object and comes back with string keys, so
	a profile written as { [1] = 1 } would not be the profile that came back.
	Using strings on both sides means saving and loading cannot disagree.

	Nothing here is trusted. `sanitize` is what a profile goes through on the way
	out of the DataStore, because what comes back was written by some earlier
	version of this file and may be anything at all.

	No Roblox in here, so the rules a player's whole history depends on are
	tested from a terminal.
]]

local Progress = {}

export type Profile = {
	best: { [string]: number },
}

function Progress.empty(): Profile
	return { best = {} }
end

local function key(roomId: number): string
	return tostring(roomId)
end

function Progress.bestFor(profile: Profile, roomId: number): number?
	return profile.best[key(roomId)]
end

function Progress.isSolved(profile: Profile, roomId: number): boolean
	return profile.best[key(roomId)] ~= nil
end

function Progress.solvedCount(profile: Profile): number
	local count = 0
	for _ in profile.best do
		count += 1
	end
	return count
end

--[[
	The highest room the player may open: the first one they have not solved.
	Solving room 3 without having solved room 2 cannot happen through the game,
	but a profile saying so unlocks nothing extra — the run of solved rooms has
	to be unbroken from the first.
]]
function Progress.unlocked(profile: Profile, roomCount: number): number
	local highest = 1
	while highest < roomCount and Progress.isSolved(profile, highest) do
		highest += 1
	end
	return highest
end

function Progress.isUnlocked(profile: Profile, roomId: number, roomCount: number): boolean
	if roomId < 1 or roomId > roomCount then
		return false
	end
	return roomId <= Progress.unlocked(profile, roomCount)
end

--[[
	Records a solve. Returns whether anything changed, so the caller knows
	whether a save is worth making, and a word for what happened so the game can
	say something true rather than always congratulating.
]]
function Progress.record(profile: Profile, roomId: number, lines: number): (boolean, string)
	if lines < 1 then
		return false, "ignored"
	end

	local previous = Progress.bestFor(profile, roomId)
	if previous == nil then
		profile.best[key(roomId)] = lines
		return true, "first"
	end
	if lines < previous then
		profile.best[key(roomId)] = lines
		return true, "improved"
	end
	return false, "matched"
end

--[[
	Turns whatever came back from the DataStore into a profile we can rely on.

	It throws nothing away quietly that it can keep, and keeps nothing it cannot
	understand. A key that is not a room number, a value that is not a positive
	whole number, a `best` that is not a table, or no profile at all, all end up
	as an empty profile rather than as an error in front of a player.
]]
function Progress.sanitize(raw: any, roomCount: number): Profile
	local profile = Progress.empty()
	if type(raw) ~= "table" or type(raw.best) ~= "table" then
		return profile
	end

	for rawKey, rawValue in raw.best do
		local roomId = tonumber(rawKey)
		if
			type(rawValue) == "number"
			and roomId ~= nil
			and roomId == math.floor(roomId)
			and roomId >= 1
			and roomId <= roomCount
			and rawValue == math.floor(rawValue)
			and rawValue >= 1
			and rawValue < 10000
		then
			profile.best[key(roomId)] = rawValue
		end
	end

	return profile
end

return Progress
