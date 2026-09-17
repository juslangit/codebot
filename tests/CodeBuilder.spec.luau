--!strict
local t = require("./testkit")
local Tokenizer = require("../src/shared/Interpreter/Tokenizer")
local Parser = require("../src/shared/Interpreter/Parser")
local Interp = require("../src/shared/Interpreter/Interp")
local CodeBuilder = require("../src/shared/CodeBuilder")
local Palette = require("../src/shared/Palette")
local Rooms = require("../src/shared/Rooms")
local RobotWorld = require("../src/shared/RobotWorld")

-- Tap a sequence. "\n" means the new-line button.
local function tap(...: string): string
	local builder = CodeBuilder.new()
	for _, piece in { ... } do
		if piece == "\n" then
			builder:newline()
		else
			builder:append(piece)
		end
	end
	return builder:text()
end

t.group("spacing: what is tapped becomes what would have been typed")

t.equal("a call closes up", tap("move", "(", ")"), "move()")
t.equal("a whole call as one piece", tap("move()"), "move()")
t.equal("words get spaces", tap("local", "n", "=", "5"), "local n = 5")
t.equal("a comma hugs the left and breathes on the right", tap("for", "i", "=", "1", ",", "10", "do"), "for i = 1, 10 do")
t.equal("brackets with something inside", tap("print", "(", "1", ")"), "print(1)")
t.equal("two arguments", tap("add", "(", "1", ",", "2", ")"), "add(1, 2)")
t.equal("not takes a space", tap("while", "not", "atGoal()", "do"), "while not atGoal() do")

t.group("indenting: laid out correctly without being taught")

t.equal(
	"a loop body is pushed in",
	tap("for", "i", "=", "1", ",", "3", "do", "\n", "move()", "\n", "end"),
	"for i = 1, 3 do\n\tmove()\nend"
)
t.equal(
	"an if inside a loop goes in twice",
	tap("for", "i", "=", "1", ",", "3", "do", "\n", "if", "blocked()", "then", "\n", "turnRight()", "\n", "end", "\n", "move()", "\n", "end"),
	"for i = 1, 3 do\n\tif blocked() then\n\t\tturnRight()\n\tend\n\tmove()\nend"
)
t.equal(
	"else comes back out and in again",
	tap("if", "blocked()", "then", "\n", "turnRight()", "\n", "else", "\n", "move()", "\n", "end"),
	"if blocked() then\n\tturnRight()\nelse\n\tmove()\nend"
)
t.equal(
	"a function body is pushed in",
	tap("local function", "hop", "(", ")", "\n", "move()", "\n", "end"),
	"local function hop()\n\tmove()\nend"
)
t.equal("an empty line stays empty", tap("move()", "\n", "\n", "move()"), "move()\n\nmove()")
t.equal("a stray end does not indent past the left edge", tap("end", "\n", "end"), "end\nend")

t.group("tapping and untapping are symmetrical")

do
	local builder = CodeBuilder.new()
	builder:append("move()")
	builder:append("move()")
	t.equal("two taps", builder:text(), "move() move()")
	builder:backspace()
	t.equal("one backspace removes a whole piece, not a character", builder:text(), "move()")
	builder:backspace()
	t.equal("and again", builder:text(), "")
	builder:backspace()
	t.equal("backspacing an empty program is harmless", builder:text(), "")
	t.equal("and it knows it is empty", builder:isEmpty(), true)
end

do
	local builder = CodeBuilder.new()
	builder:append("move()")
	builder:newline()
	builder:append("move()")
	builder:backspace()
	t.equal("backspace after a new line removes the piece", builder:text(), "move()\n")
	builder:backspace()
	t.equal("and then the new line itself", builder:text(), "move()")
end

do
	local builder = CodeBuilder.new()
	builder:append("for")
	builder:append("i")
	t.equal("it remembers the last piece tapped", builder:last(), "i")
	builder:newline()
	t.equal("a new line is not a piece", builder:last(), "i")
	builder:clear()
	t.equal("clear empties it", builder:count(), 0)
	t.equal("and there is no last piece", builder:last(), nil)
end

t.group("typed text can be turned back into taps")

do
	local builder = CodeBuilder.fromText("for i = 1, 3 do\n\tmove()\nend")
	t.equal(
		"it comes back out the same",
		builder:text(),
		"for i = 1, 3 do\n\tmove()\nend"
	)
	builder:backspace()
	t.equal("and backspace still works on whole pieces", builder:text(), "for i = 1, 3 do\n\tmove()\n")
end

-- It tidies what it can split safely and leaves the rest alone. "i=1" stays as
-- typed because splitting on = would have to tell == and ~= apart, and getting
-- that wrong would silently rewrite the player's meaning.
t.equal(
	"indentation and comma spacing are tidied",
	CodeBuilder.fromText("for i=1,3 do\nmove( )\nend"):text(),
	"for i=1, 3 do\n\tmove()\nend"
)
t.equal(
	"but a comparison is never rewritten",
	CodeBuilder.fromText("if a ~= b then\nmove()\nend"):text(),
	"if a ~= b then\n\tmove()\nend"
)

t.group("every room's own solution can be built from that room's buttons")

-- The palette equivalent of the room test. A room offering no way to write its
-- own answer is a room the player cannot leave, and it would not be visible by
-- reading either file on its own.
local function tokensOf(source: string): { string }
	local result = Tokenizer.tokenize(source)
	if not result.ok then
		return {}
	end
	local out = {}
	for _, token in result.tokens :: any do
		if token.kind ~= "eof" then
			table.insert(out, token.value)
		end
	end
	return out
end

for _, room in Rooms.all() do
	local available: { [string]: boolean } = {}
	for _, piece in Palette.piecesForRoom(room.id) do
		for _, token in tokensOf(piece) do
			available[token] = true
		end
	end

	local missing: { string } = {}
	for _, token in tokensOf(room.target) do
		if not available[token] then
			table.insert(missing, token)
		end
	end

	t.check(
		string.format("room %d, %s", room.id, room.name),
		#missing == 0,
		if #missing == 0 then nil else "no button for: " .. table.concat(missing, " ")
	)
end

t.group("the palette grows and never shrinks")

t.equal("room 1 offers one group", #Palette.forRoom(1), 1)
t.equal("room 3 still offers only that group", #Palette.forRoom(3), 1)
t.equal("room 8 offers all of them", #Palette.forRoom(8), #Palette.groups())

do
	local previous = 0
	local shrank = false
	for id = 1, Rooms.count() do
		local count = #Palette.piecesForRoom(id)
		if count < previous then
			shrank = true
		end
		previous = count
	end
	t.check("no room takes a button away", not shrank)
end

t.equal("room 4 introduces the loop", table.concat(Palette.newInRoom(4), " "):find("for") ~= nil, true)
t.equal("room 2 introduces nothing new", #Palette.newInRoom(2), 0)

t.group("a tapped solution actually solves its room")

-- Building the text is one thing; the text running is another. This taps out
-- room 4's answer piece by piece and drives the real robot with the result.
do
	local builder = CodeBuilder.new()
	for _, piece in { "for", "i", "=", "1", ",", "10", "do" } do
		builder:append(piece)
	end
	builder:newline()
	builder:append("move()")
	builder:newline()
	builder:append("end")

	local room = Rooms.get(4) :: any
	local tokens = Tokenizer.tokenize(builder:text())
	local parsed = Parser.parse(tokens.tokens :: any)
	local world = RobotWorld.create(room)
	local machine = Interp.create(parsed.ast :: any, { builtins = world:builtins() })
	machine:run()

	t.equal("the tapped text is what we expect", builder:text(), "for i = 1, 10 do\n\tmove()\nend")
	t.check("and it reaches the goal", world:isSolved())
end

return t.report()
