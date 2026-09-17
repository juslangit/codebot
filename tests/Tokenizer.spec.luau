--!strict
local t = require("./testkit")
local Tokenizer = require("../src/shared/Interpreter/Tokenizer")

-- Render a token list as "kind:value kind:value ..." so a whole expectation
-- fits on one line and a failure is readable at a glance.
local function shape(source: string): string
	local result = Tokenizer.tokenize(source)
	if not result.ok then
		return "ERROR: " .. (result.err :: any).message
	end
	local parts = {}
	for _, token in result.tokens :: any do
		if token.kind == "eof" then
			table.insert(parts, "eof")
		else
			table.insert(parts, token.kind .. ":" .. token.value)
		end
	end
	return table.concat(parts, " ")
end

local function errorOf(source: string): string
	local result = Tokenizer.tokenize(source)
	if result.ok then
		return "NO ERROR"
	end
	return (result.err :: any).message
end

local function errorAt(source: string): string
	local result = Tokenizer.tokenize(source)
	if result.ok then
		return "NO ERROR"
	end
	local err = result.err :: any
	return err.line .. ":" .. err.col
end

t.group("the pieces of a program")

t.equal("a single call", shape("move()"), "name:move op:( op:) eof")
t.equal("a keyword is not a name", shape("local x"), "keyword:local name:x eof")
t.equal("a number", shape("42"), "number:42 eof")
t.equal("a decimal number", shape("1.5"), "number:1.5 eof")
t.equal("a leading-dot number", shape(".5"), "number:.5 eof")
t.equal("a piece of text", shape('"hello"'), "string:hello eof")
t.equal("single quotes work too", shape("'hello'"), "string:hello eof")
t.equal("an empty program is just the end marker", shape(""), "eof")

t.group("the loop from room 4")

t.equal(
	"for i = 1, 8 do move() end",
	shape("for i = 1, 8 do move() end"),
	"keyword:for name:i op:= number:1 op:, number:8 keyword:do name:move op:( op:) keyword:end eof"
)

t.group("operators that share a first character")

t.equal("== is one token, not two", shape("a == b"), "name:a op:== name:b eof")
t.equal("~= is one token", shape("a ~= b"), "name:a op:~= name:b eof")
t.equal(">= is one token", shape("a >= b"), "name:a op:>= name:b eof")
t.equal("a bare = stays a bare =", shape("a = b"), "name:a op:= name:b eof")
t.equal(".. joins text", shape('a .. "x"'), "name:a op:.. string:x eof")
t.equal("minus is not a comment", shape("1 - 2"), "number:1 op:- number:2 eof")

t.group("things that carry no meaning")

t.equal("a comment is skipped", shape("move() -- go forward"), "name:move op:( op:) eof")
t.equal("a comment on its own line", shape("-- nothing here\nmove()"), "name:move op:( op:) eof")
t.equal(
	"newlines and tabs are skipped",
	shape("move()\n\tmove()"),
	"name:move op:( op:) name:move op:( op:) eof"
)

t.group("where a token came from")

do
	local result = Tokenizer.tokenize("move()\nturnRight()")
	local tokens = result.tokens :: any
	t.equal("first token is on line 1", tokens[1].line, 1)
	t.equal("first token is at column 1", tokens[1].col, 1)
	t.equal("the second call is on line 2", tokens[4].line, 2)
	t.equal("the second call starts at column 1", tokens[4].col, 1)
end

do
	local result = Tokenizer.tokenize("  move()")
	local tokens = result.tokens :: any
	t.equal("indentation counts towards the column", tokens[1].col, 3)
end

t.group("errors a beginner will actually hit")

t.equal(
	"an unclosed quote is reported where it opened",
	errorOf('print("hello)'),
	'This piece of text is missing its closing " mark.'
)
t.equal("and it points at the opening quote, not the end", errorAt('print("hello)'), "1:7")
t.equal(
	"a runaway quote does not swallow the next line",
	errorOf('print("hello\nmove()'),
	'This piece of text is missing its closing " mark.'
)
t.equal(
	"!= is explained, not rejected",
	errorOf("if a != b then end"),
	'Luau writes "is not equal to" as ~= , not != '
)
t.equal(
	"&& is explained",
	errorOf("if a && b then end"),
	'Luau writes "and" as the word and , not && '
)
t.equal(
	"|| is explained",
	errorOf("if a || b then end"),
	'Luau writes "or" as the word or , not || '
)
t.equal(
	"curly brackets are explained",
	errorOf("if a then { }"),
	"Curly brackets are not used to group code in Luau. Blocks end with the word end ."
)
t.equal(
	"a semicolon is forgiven with an explanation",
	errorOf("move();"),
	"You do not need a semicolon at the end of a line in Luau."
)
t.equal(
	"a number with two dots is caught",
	errorOf("1.2.3"),
	"That number has two dots in it, so I cannot tell what it is meant to be."
)
t.equal(
	"an unknown symbol is named",
	errorOf("move() @"),
	'I do not understand the symbol "@" here.'
)

t.group("escapes inside text")

t.equal("a newline escape", shape('"a\\nb"'), "string:a\nb eof")
t.equal("an escaped quote does not close the text", shape('"say \\"hi\\""'), 'string:say "hi" eof')
t.equal(
	"an unknown escape is explained",
	errorOf('"a\\qb"'),
	"I do not know what \\q means inside a piece of text."
)

return t.report()
