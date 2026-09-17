--!strict
--[[
	Prints how the tokenizer reads a piece of code. Handy for seeing what the
	first step of the interpreter actually does, without opening Studio.

		lune run tools/show_tokens.luau 'for i = 1, 8 do move() end'
]]

local process = require("@lune/process")
local Tokenizer = require("../src/shared/Interpreter/Tokenizer")

local source = process.args[1]
if not source then
	print("usage: lune run tools/show_tokens.luau '<code>'")
	return
end

print("\ncode:  " .. (string.gsub(source, "\n", " / ")))

local result = Tokenizer.tokenize(source)
if not result.ok then
	local err = result.err :: any
	print(string.format("  error at line %d, column %d", err.line, err.col))
	print("  " .. err.message)
	return
end

local parts = {}
for _, token in result.tokens :: any do
	if token.kind ~= "eof" then
		table.insert(parts, token.kind .. "(" .. token.value .. ")")
	end
end
print("  " .. table.concat(parts, "  "))
