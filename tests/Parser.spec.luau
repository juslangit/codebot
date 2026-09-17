--!strict
local t = require("./testkit")
local Tokenizer = require("../src/shared/Interpreter/Tokenizer")
local Parser = require("../src/shared/Interpreter/Parser")

-- Render the tree as a one-line bracketed form, so an expectation reads as a
-- shape rather than as a wall of table literals.
local render: (any) -> string

local function renderList(nodes: any, separator: string): string
	local parts = {}
	for _, node in nodes do
		table.insert(parts, render(node))
	end
	return table.concat(parts, separator)
end

-- "{ a; b }", or "{ }" when the block is empty.
local function renderBlock(nodes: any): string
	if #nodes == 0 then
		return "{ }"
	end
	return "{ " .. renderList(nodes, "; ") .. " }"
end

function render(node: any): string
	local kind = node.kind

	if kind == "Number" then
		return tostring(node.value)
	elseif kind == "String" then
		return '"' .. node.value .. '"'
	elseif kind == "Boolean" then
		return tostring(node.value)
	elseif kind == "Nil" then
		return "nil"
	elseif kind == "Name" then
		return node.name
	elseif kind == "Binary" then
		return "(" .. node.op .. " " .. render(node.left) .. " " .. render(node.right) .. ")"
	elseif kind == "Unary" then
		return "(" .. node.op .. " " .. render(node.expr) .. ")"
	elseif kind == "Call" then
		if #node.args == 0 then
			return node.name .. "()"
		end
		return node.name .. "(" .. renderList(node.args, " ") .. ")"
	elseif kind == "Local" then
		return "local " .. node.name .. (if node.expr then " = " .. render(node.expr) else "")
	elseif kind == "Assign" then
		return "set " .. node.name .. " = " .. render(node.expr)
	elseif kind == "ExprStat" then
		return render(node.expr)
	elseif kind == "Break" then
		return "break"
	elseif kind == "Return" then
		return "return" .. (if node.expr then " " .. render(node.expr) else "")
	elseif kind == "While" then
		return "while " .. render(node.cond) .. " " .. renderBlock(node.body)
	elseif kind == "ForNumeric" then
		local header = "for " .. node.var .. " = " .. render(node.from) .. ", " .. render(node.to)
		if node.step then
			header ..= ", " .. render(node.step)
		end
		return header .. " " .. renderBlock(node.body)
	elseif kind == "Function" then
		return "function "
			.. node.name
			.. "("
			.. table.concat(node.params, " ")
			.. ") "
			.. renderBlock(node.body)
	elseif kind == "If" then
		local parts = {}
		for index, branch in node.branches do
			local word = if index == 1 then "if " else "elseif "
			table.insert(parts, word .. render(branch.cond) .. " " .. renderBlock(branch.body))
		end
		if node.elseBody then
			table.insert(parts, "else " .. renderBlock(node.elseBody))
		end
		return table.concat(parts, " ")
	end

	return "?" .. tostring(kind)
end

local function tree(source: string): string
	local tokens = Tokenizer.tokenize(source)
	if not tokens.ok then
		return "TOKENIZER ERROR: " .. (tokens.err :: any).message
	end
	local parsed = Parser.parse(tokens.tokens :: any)
	if not parsed.ok then
		return "ERROR: " .. (parsed.err :: any).message
	end
	return renderList(parsed.ast :: any, "; ")
end

local function errorOf(source: string): string
	local tokens = Tokenizer.tokenize(source)
	if not tokens.ok then
		return "TOKENIZER ERROR"
	end
	local parsed = Parser.parse(tokens.tokens :: any)
	if parsed.ok then
		return "NO ERROR"
	end
	return (parsed.err :: any).message
end

local function lineOf(source: string): number
	local tokens = Tokenizer.tokenize(source)
	local parsed = Parser.parse(tokens.tokens :: any)
	if parsed.ok then
		return -1
	end
	return (parsed.err :: any).line
end

t.group("the simplest programs")

t.equal("a call", tree("move()"), "move()")
t.equal("two calls in order", tree("move()\nturnRight()"), "move(); turnRight()")
t.equal("a call with an argument", tree('print("hi")'), 'print("hi")')
t.equal("a call with two arguments", tree("add(1, 2)"), "add(1 2)")
t.equal("an empty program", tree(""), "")

t.group("naming things")

t.equal("local with a value", tree("local steps = 3"), "local steps = 3")
t.equal("local with no value", tree("local steps"), "local steps")
t.equal("changing a name later", tree("steps = 4"), "set steps = 4")
t.equal("a name used in a call", tree("move(steps)"), "move(steps)")

t.group("the room ladder, as trees")

t.equal("room 4, the loop", tree("for i = 1, 8 do move() end"), "for i = 1, 8 { move() }")
t.equal(
	"room 5, a variable naming a number",
	tree("local steps = 8\nfor i = 1, steps do move() end"),
	"local steps = 8; for i = 1, steps { move() }"
)
t.equal(
	"room 6, asking about the world",
	tree("if blocked() then turnRight() end"),
	"if blocked() { turnRight() }"
)
t.equal(
	"room 7, repeating until something is true",
	tree("while not atGoal() do move() end"),
	"while (not atGoal()) { move() }"
)
t.equal(
	"room 8, a function of your own",
	tree("local function step2()\n\tmove()\n\tmove()\nend\nstep2()"),
	"function step2() { move(); move() }; step2()"
)

t.group("if, in all its shapes")

t.equal(
	"if with else",
	tree("if a then move() else turnLeft() end"),
	"if a { move() } else { turnLeft() }"
)
t.equal(
	"if with elseif",
	tree("if a then move() elseif b then turnLeft() end"),
	"if a { move() } elseif b { turnLeft() }"
)
t.equal(
	"if with elseif and else",
	tree("if a then move() elseif b then turnLeft() else turnRight() end"),
	"if a { move() } elseif b { turnLeft() } else { turnRight() }"
)
t.equal("an empty if body is allowed", tree("if a then end"), "if a { }")
t.equal("if inside if", tree("if a then if b then move() end end"), "if a { if b { move() } }")

t.group("operator precedence")

t.equal("times binds tighter than plus", tree("x = 1 + 2 * 3"), "set x = (+ 1 (* 2 3))")
t.equal("brackets override it", tree("x = (1 + 2) * 3"), "set x = (* (+ 1 2) 3)")
t.equal("plus is left to right", tree("x = 1 + 2 + 3"), "set x = (+ (+ 1 2) 3)")
t.equal("minus is left to right", tree("x = 5 - 2 - 1"), "set x = (- (- 5 2) 1)")
t.equal("compare binds looser than plus", tree("x = 1 + 2 == 3"), "set x = (== (+ 1 2) 3)")
t.equal(
	"and binds looser than compare",
	tree("x = a == 1 and b == 2"),
	"set x = (and (== a 1) (== b 2))"
)
t.equal("or binds loosest", tree("x = a and b or c"), "set x = (or (and a b) c)")
t.equal("not binds tightest", tree("x = not a and b"), "set x = (and (not a) b)")
t.equal("negation", tree("x = -3 + 1"), "set x = (+ (- 3) 1)")
t.equal(
	"joining text is right to left",
	tree('x = "a" .. "b" .. "c"'),
	'set x = (.. "a" (.. "b" "c"))'
)

t.group("values")

t.equal("true", tree("x = true"), "set x = true")
t.equal("false", tree("x = false"), "set x = false")
t.equal("nil", tree("x = nil"), "set x = nil")
t.equal("a decimal", tree("x = 1.5"), "set x = 1.5")

t.group("loops")

t.equal(
	"a for loop with a step",
	tree("for i = 1, 10, 2 do move() end"),
	"for i = 1, 10, 2 { move() }"
)
t.equal("break inside a loop", tree("while true do break end"), "while true { break }")
t.equal(
	"a loop inside a loop",
	tree("for i = 1, 2 do for j = 1, 3 do move() end end"),
	"for i = 1, 2 { for j = 1, 3 { move() } }"
)

t.group("functions")

t.equal(
	"a function with inputs",
	tree("local function add(a, b) return a + b end"),
	"function add(a b) { return (+ a b) }"
)
t.equal("a bare return", tree("local function f() return end"), "function f() { return }")
t.equal(
	"function without local works the same",
	tree("function f() move() end"),
	"function f() { move() }"
)

t.group("a missing end names the line the block opened on")

t.equal(
	"an unclosed if",
	errorOf("if blocked() then\n\tturnRight()"),
	"This if starting on line 1 is never closed. It needs an end to say where it stops."
)
t.equal(
	"an unclosed while",
	errorOf("while true do\n\tmove()"),
	"This while loop starting on line 1 is never closed. It needs an end to say where it stops."
)
t.equal(
	"an unclosed for",
	errorOf("for i = 1, 3 do\n\tmove()"),
	"This for loop starting on line 1 is never closed. It needs an end to say where it stops."
)
t.equal(
	"an unclosed function",
	errorOf("local function go()\n\tmove()"),
	"This function starting on line 1 is never closed. It needs an end to say where it stops."
)
t.equal(
	"it points at the opener, not the bottom of a long program",
	lineOf("move()\nmove()\nif blocked() then\n\tmove()\n\tmove()\n\tmove()"),
	3
)

t.group("mistakes a beginner makes")

t.equal(
	"= where == was meant, in an if",
	errorOf("if a = b then end"),
	"To check whether two things are the same, use == with two equals signs. "
		.. "A single = is for giving something a value."
)
t.equal(
	"= where == was meant, in a while",
	errorOf("while a = b do end"),
	"To check whether two things are the same, use == with two equals signs. "
		.. "A single = is for giving something a value."
)
t.equal(
	"a line that does nothing",
	errorOf("steps + 1"),
	"This line does not do anything. A line on its own has to be an action, "
		.. "like move(), or give something a value, like steps = 3."
)
t.equal(
	"a stray end",
	errorOf("move()\nend"),
	"There is an end here with nothing open for it to close."
)
t.equal("an else with no if", errorOf("else move() end"), '"else" can only be used inside an if.')
t.equal(
	"a missing then",
	errorOf("if blocked() move() end"),
	'An if needs the word then after what it is checking. I found "move" instead.'
)
t.equal(
	"a missing do on a while",
	errorOf("while true move() end"),
	'A while loop needs the word do after what it is checking. I found "move" instead.'
)
t.equal(
	"a missing closing bracket on a call",
	errorOf("move("),
	"I expected a value here, but found the end of your code."
)
t.equal(
	"an unclosed bracket with an argument inside",
	errorOf("print(1"),
	"This call is missing its closing ) bracket. I found the end of your code instead."
)
t.equal(
	"a keyword used as a name",
	errorOf("local end = 3"),
	'"end" is a word Luau uses for something else, so it cannot be used as a name.'
)
t.equal(
	"the other kind of for loop is named, not just refused",
	errorOf("for k, v in pairs(t) do end"),
	"That kind of for loop is not available yet. Use a counting one, like for i = 1, 10 do."
)
t.equal(
	"reaching inside things with a dot",
	errorOf("x = game.Workspace"),
	"Reaching inside things with a dot is not part of what you can use yet."
)
t.equal(
	"only a name can be given a value",
	errorOf("move() = 3"),
	"Only a name can be given a value, like steps = 3."
)

t.group("the line each statement starts on")

do
	local tokens = Tokenizer.tokenize("move()\n\nlocal x = 1\nif x then\n\tmove()\nend")
	local parsed = Parser.parse(tokens.tokens :: any)
	local ast = parsed.ast :: any
	t.equal("first statement", ast[1].line, 1)
	t.equal("a blank line does not count", ast[2].line, 3)
	t.equal("the if", ast[3].line, 4)
	t.equal("a statement inside the if", ast[3].branches[1].body[1].line, 5)
end

return t.report()
