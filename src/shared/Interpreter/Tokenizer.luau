--!strict
--[[
	Tokenizer — step 1 of 3 in the interpreter.

	Turns the player's code, which is just one long string of characters, into a
	flat list of tokens: the smallest pieces that still mean something.

		"for i = 1, 3 do"  ->  for | i | = | 1 | , | 3 | do

	It does not care whether the code makes sense. "end end end end" tokenizes
	perfectly happily. Deciding whether a sequence of tokens is a real program is
	the Parser's job, and actually running it is the Interpreter's.

	Every token carries the line and column it came from, because the player is a
	beginner and every error we show them has to point at a place in their code.
]]

local Tokenizer = {}

export type TokenKind = "name" | "number" | "string" | "keyword" | "op" | "eof"

export type Token = {
	kind: TokenKind,
	-- For a number token this is the text, not the value: "3" not 3. The parser
	-- converts it. Keeping the original text means an error can quote it back.
	value: string,
	line: number,
	col: number,
}

export type SyntaxError = {
	message: string,
	line: number,
	col: number,
}

export type Result = {
	ok: boolean,
	tokens: { Token }?,
	err: SyntaxError?,
}

-- The only words the player is allowed to use as language, rather than as names
-- of their own. Kept to the v1 subset deliberately: see 02-planning.md.
local KEYWORDS: { [string]: boolean } = {
	["and"] = true,
	["break"] = true,
	["do"] = true,
	["else"] = true,
	["elseif"] = true,
	["end"] = true,
	["false"] = true,
	["for"] = true,
	["function"] = true,
	["if"] = true,
	["local"] = true,
	["nil"] = true,
	["not"] = true,
	["or"] = true,
	["return"] = true,
	["then"] = true,
	["true"] = true,
	["while"] = true,
}

-- Longest first, so that "==" is matched before "=" and "..." never half-matches.
local OPERATORS: { string } = {
	"==",
	"~=",
	"<=",
	">=",
	"..",
	"+",
	"-",
	"*",
	"/",
	"%",
	"<",
	">",
	"=",
	"(",
	")",
	",",
	".",
}

-- Mistakes a beginner makes because they have seen another language, and the
-- sentence we say instead of "unexpected symbol".
local FRIENDLY_MISTAKES: { [string]: string } = {
	["!="] = 'Luau writes "is not equal to" as ~= , not != ',
	["&&"] = 'Luau writes "and" as the word and , not && ',
	["||"] = 'Luau writes "or" as the word or , not || ',
	["!"] = 'Luau writes "not" as the word not , not ! ',
	["{"] = "Curly brackets are not used to group code in Luau. Blocks end with the word end .",
	["}"] = "Curly brackets are not used to group code in Luau. Blocks end with the word end .",
	[";"] = "You do not need a semicolon at the end of a line in Luau.",
	["#"] = "The # symbol is not part of what you can use yet.",
}

local function isDigit(c: string): boolean
	return c >= "0" and c <= "9"
end

local function isLetter(c: string): boolean
	return (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or c == "_"
end

local function isNameChar(c: string): boolean
	return isLetter(c) or isDigit(c)
end

--[[
	tokenize takes the player's whole program and returns either the list of
	tokens or a single error. It never raises, because the caller is a game that
	has to draw the problem on screen, not crash.
]]
function Tokenizer.tokenize(source: string): Result
	local tokens: { Token } = {}

	local pos = 1 -- where we are in the source string, 1-based
	local line = 1
	local col = 1
	local length = #source

	local function peek(offset: number?): string
		local at = pos + (offset or 0)
		if at > length then
			return ""
		end
		return string.sub(source, at, at)
	end

	-- Move forward n characters, keeping line and column honest as we go.
	local function advance(n: number?)
		for _ = 1, n or 1 do
			if peek() == "\n" then
				line += 1
				col = 1
			else
				col += 1
			end
			pos += 1
		end
	end

	local function fail(message: string, atLine: number, atCol: number): Result
		return { ok = false, tokens = nil, err = { message = message, line = atLine, col = atCol } }
	end

	local function push(kind: TokenKind, value: string, atLine: number, atCol: number)
		table.insert(tokens, { kind = kind, value = value, line = atLine, col = atCol })
	end

	while pos <= length do
		local c = peek()

		-- Whitespace, including newlines, carries no meaning. Skip it.
		if c == " " or c == "\t" or c == "\r" or c == "\n" then
			advance()

		-- A comment runs to the end of the line. Block comments are not in the
		-- v1 subset, so --[[ is read as a normal comment, which is harmless.
		elseif c == "-" and peek(1) == "-" then
			while pos <= length and peek() ~= "\n" do
				advance()
			end

		-- A name or a keyword. Both start with a letter or underscore.
		elseif isLetter(c) then
			local startLine, startCol = line, col
			local startPos = pos
			while pos <= length and isNameChar(peek()) do
				advance()
			end
			local word = string.sub(source, startPos, pos - 1)
			push(if KEYWORDS[word] then "keyword" else "name", word, startLine, startCol)

		-- A number: digits, with at most one dot inside them.
		elseif isDigit(c) or (c == "." and isDigit(peek(1))) then
			local startLine, startCol = line, col
			local startPos = pos
			local seenDot = false
			while pos <= length do
				local ch = peek()
				if isDigit(ch) then
					advance()
				elseif ch == "." and not seenDot then
					seenDot = true
					advance()
				elseif ch == "." and seenDot then
					return fail(
						"That number has two dots in it, so I cannot tell what it is meant to be.",
						line,
						col
					)
				else
					break
				end
			end
			push("number", string.sub(source, startPos, pos - 1), startLine, startCol)

		-- A string, in either kind of quote. It must close on the same line:
		-- a runaway quote is the error that confuses beginners most, so we
		-- catch it exactly where it started rather than at the end of the file.
		elseif c == '"' or c == "'" then
			local quote = c
			local startLine, startCol = line, col
			advance()
			local pieces: { string } = {}
			local closed = false
			while pos <= length do
				local ch = peek()
				if ch == "\n" then
					break
				elseif ch == "\\" then
					local escaped = peek(1)
					if escaped == "n" then
						table.insert(pieces, "\n")
					elseif escaped == "t" then
						table.insert(pieces, "\t")
					elseif escaped == "\\" then
						table.insert(pieces, "\\")
					elseif escaped == quote then
						table.insert(pieces, quote)
					else
						return fail(
							"I do not know what \\" .. escaped .. " means inside a piece of text.",
							line,
							col
						)
					end
					advance(2)
				elseif ch == quote then
					advance()
					closed = true
					break
				else
					table.insert(pieces, ch)
					advance()
				end
			end
			if not closed then
				return fail(
					"This piece of text is missing its closing " .. quote .. " mark.",
					startLine,
					startCol
				)
			end
			push("string", table.concat(pieces), startLine, startCol)
		else
			-- An operator, or something we can name helpfully, or something we cannot.
			local matched: string? = nil
			for _, op in OPERATORS do
				if string.sub(source, pos, pos + #op - 1) == op then
					matched = op
					break
				end
			end

			if matched then
				local startLine, startCol = line, col
				advance(#matched)
				push("op", matched, startLine, startCol)
			else
				local two = string.sub(source, pos, pos + 1)
				local hint = FRIENDLY_MISTAKES[two] or FRIENDLY_MISTAKES[c]
				return fail(
					hint or ('I do not understand the symbol "' .. c .. '" here.'),
					line,
					col
				)
			end
		end
	end

	-- A final token meaning "the code stops here", so the parser never has to
	-- check whether it has run off the end of the list.
	push("eof", "", line, col)

	return { ok = true, tokens = tokens, err = nil }
end

return Tokenizer
