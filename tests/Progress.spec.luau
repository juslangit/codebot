--!strict
local t = require("./testkit")
local Progress = require("../src/shared/Progress")
local Solution = require("../src/shared/Solution")
local Rooms = require("../src/shared/Rooms")

local COUNT = Rooms.count()

t.group("recording a solve")

do
	local p = Progress.empty()
	t.equal("a new player has solved nothing", Progress.solvedCount(p), 0)
	t.equal("and has no best for room 1", Progress.bestFor(p, 1), nil)

	local changed, why = Progress.record(p, 1, 3)
	t.equal("the first solve counts", changed, true)
	t.equal("and says so", why, "first")
	t.equal("the best is kept", Progress.bestFor(p, 1), 3)

	changed, why = Progress.record(p, 1, 5)
	t.equal("a worse attempt changes nothing", changed, false)
	t.equal("and says so", why, "matched")
	t.equal("the best is still the best", Progress.bestFor(p, 1), 3)

	changed, why = Progress.record(p, 1, 1)
	t.equal("a better attempt replaces it", changed, true)
	t.equal("and says so", why, "improved")
	t.equal("the new best", Progress.bestFor(p, 1), 1)

	t.equal("a solve of zero lines is not a solve", Progress.record(p, 2, 0), false)
	t.equal("and nothing was written", Progress.isSolved(p, 2), false)
end

t.group("what a player is allowed to open")

do
	local p = Progress.empty()
	t.equal("room 1 is open to everyone", Progress.unlocked(p, COUNT), 1)
	t.equal("room 2 is not", Progress.isUnlocked(p, 2, COUNT), false)

	Progress.record(p, 1, 1)
	t.equal("solving room 1 opens room 2", Progress.unlocked(p, COUNT), 2)
	t.equal("and room 2 is enterable", Progress.isUnlocked(p, 2, COUNT), true)
	t.equal("room 1 stays enterable", Progress.isUnlocked(p, 1, COUNT), true)
	t.equal("room 3 does not", Progress.isUnlocked(p, 3, COUNT), false)
end

do
	local p = Progress.empty()
	-- Cannot happen through the game, but a profile could say it.
	Progress.record(p, 1, 1)
	Progress.record(p, 3, 1)
	t.equal("a gap in the run unlocks nothing extra", Progress.unlocked(p, COUNT), 2)
end

do
	local p = Progress.empty()
	for id = 1, COUNT do
		Progress.record(p, id, 1)
	end
	t.equal("solving everything stops at the last room", Progress.unlocked(p, COUNT), COUNT)
	t.equal("there is no room after the last", Progress.isUnlocked(p, COUNT + 1, COUNT), false)
	t.equal("and none before the first", Progress.isUnlocked(p, 0, COUNT), false)
end

t.group("what comes back from the DataStore is not trusted")

t.equal("nothing at all", Progress.solvedCount(Progress.sanitize(nil, COUNT)), 0)
t.equal("a number", Progress.solvedCount(Progress.sanitize(7, COUNT)), 0)
t.equal("a table with no best", Progress.solvedCount(Progress.sanitize({}, COUNT)), 0)
t.equal("a best that is not a table", Progress.solvedCount(Progress.sanitize({ best = 3 }, COUNT)), 0)

do
	-- A DataStore stores JSON, so a table written with number keys comes back
	-- with string ones. Both have to survive.
	local fromStrings = Progress.sanitize({ best = { ["1"] = 2, ["2"] = 4 } }, COUNT)
	t.equal("string keys, as a DataStore returns them", Progress.bestFor(fromStrings, 1), 2)
	t.equal("and the second", Progress.bestFor(fromStrings, 2), 4)

	local fromNumbers = Progress.sanitize({ best = { [1] = 2, [3] = 9 } }, COUNT)
	t.equal("number keys, as an older version may have written them", Progress.bestFor(fromNumbers, 1), 2)
	t.equal("and they land on the right rooms", Progress.bestFor(fromNumbers, 3), 9)
end

do
	local junk = Progress.sanitize({
		best = {
			["1"] = 3,
			["hello"] = 2,
			["99"] = 1,
			["0"] = 1,
			["2"] = -4,
			["3"] = 2.5,
			["4"] = "many",
			["5"] = 999999,
		},
	}, COUNT)
	t.equal("only the one good entry survives", Progress.solvedCount(junk), 1)
	t.equal("and it is the right one", Progress.bestFor(junk, 1), 3)
	t.equal("a room that does not exist is dropped", Progress.bestFor(junk, 99), nil)
	t.equal("a negative line count is dropped", Progress.bestFor(junk, 2), nil)
	t.equal("a fractional line count is dropped", Progress.bestFor(junk, 3), nil)
	t.equal("text is dropped", Progress.bestFor(junk, 4), nil)
	t.equal("an absurd line count is dropped", Progress.bestFor(junk, 5), nil)
end

t.group("checking a solution, the same way on both sides")

do
	local report = Solution.run(Rooms.get(4), "for i = 1, 10 do\n\tmove()\nend")
	t.equal("it solves room 4", report.solved, true)
	t.equal("without an error", report.ok, true)
	t.equal("in three lines", report.lines, 3)
end

t.equal(
	"blank lines are free",
	Solution.countLines("move()\n\n\nmove()\n   \nmove()"),
	3
)

do
	local report = Solution.run(Rooms.get(1), "move()\nmove()\nmove()")
	t.equal("overshooting still counts as solved if it ends on the goal", report.solved, true)
end

do
	local report = Solution.run(Rooms.get(2), "move()")
	t.equal("stopping short is not solved", report.solved, false)
	t.equal("but it is not an error either", report.ok, true)
end

do
	local report = Solution.run(Rooms.get(1), "for i = 1 do move() end")
	t.equal("a program that will not parse is not ok", report.ok, false)
	t.equal("and it is not solved", report.solved, false)
	t.check("and it says what is wrong", (report.err :: any).message ~= nil)
end

do
	local report = Solution.run(Rooms.get(1), "jump()")
	t.equal("a program that fails while running is not ok", report.ok, false)
	t.equal(
		"and it says what is wrong",
		(report.err :: any).message,
		'There is no action called "jump". Check the spelling.'
	)
end

do
	local report = Solution.run(Rooms.get(1), "while true do\n\tturnLeft()\nend")
	t.equal("a program that never finishes is stopped", report.ok, false)
	t.check("at the step cap", report.steps > 1000)
end

do
	local long = string.rep("move()\n", 800)
	local report = Solution.run(Rooms.get(1), long)
	t.equal("a program too long to be honest is refused before it runs", report.ok, false)
	t.equal("without being run", report.steps, 0)
	t.equal(
		"and says why",
		(report.err :: any).message,
		"That program is too long for this game."
	)
end

t.group("every room's target solves it, through the same path the server uses")

for _, room in Rooms.all() do
	local report = Solution.run(room, room.target)
	t.check(
		string.format("room %d, %s", room.id, room.name),
		report.solved and report.ok and report.lines == room.par,
		string.format("solved=%s ok=%s lines=%d par=%d", tostring(report.solved), tostring(report.ok), report.lines, room.par)
	)
end

return t.report()
