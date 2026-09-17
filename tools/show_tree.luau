--!strict
--[[
	Prints the shape the parser makes out of a piece of code, as an indented
	tree. Handy for seeing what "inside" means, without opening Studio.

		lune run tools/show_tree.luau 'for i = 1, 3 do move() end'
]]

local process = require("@lune/process")
local Tokenizer = require("../src/shared/Interpreter/Tokenizer")
local Parser = require("../src/shared/Interpreter/Parser")

local source = process.args[1]
if not source then
	print("usage: lune run tools/show_tree.luau '<code>'")
	return
end

local function describe(node: any): string
	local kind = node.kind
	if kind == "Number" or kind == "Boolean" then
		return tostring(node.value)
	elseif kind == "String" then
		return '"' .. node.value .. '"'
	elseif kind == "Nil" then
		return "nil"
	elseif kind == "Name" then
		return node.name
	elseif kind == "Binary" then
		return describe(node.left) .. " " .. node.op .. " " .. describe(node.right)
	elseif kind == "Unary" then
		return node.op .. " " .. describe(node.expr)
	elseif kind == "Call" then
		local args = {}
		for _, arg in node.args do
			table.insert(args, describe(arg))
		end
		return node.name .. "(" .. table.concat(args, ", ") .. ")"
	end
	return kind
end

local show: (any, number) -> ()
local function showBlock(nodes: any, depth: number)
	for _, node in nodes do
		show(node, depth)
	end
end

function show(node: any, depth: number)
	local pad = string.rep("   ", depth)
	local kind = node.kind
	local label = string.format("%s%s", pad, "line " .. node.line .. "  ")

	if kind == "ExprStat" then
		print(label .. describe(node.expr))
	elseif kind == "Local" then
		print(
			label
				.. "name "
				.. node.name
				.. " = "
				.. (if node.expr then describe(node.expr) else "nothing")
		)
	elseif kind == "Assign" then
		print(label .. "set " .. node.name .. " = " .. describe(node.expr))
	elseif kind == "Return" then
		print(label .. "return " .. (if node.expr then describe(node.expr) else ""))
	elseif kind == "Break" then
		print(label .. "break")
	elseif kind == "While" then
		print(label .. "repeat while " .. describe(node.cond))
		showBlock(node.body, depth + 1)
	elseif kind == "ForNumeric" then
		print(
			label
				.. "count "
				.. node.var
				.. " from "
				.. describe(node.from)
				.. " to "
				.. describe(node.to)
		)
		showBlock(node.body, depth + 1)
	elseif kind == "Function" then
		print(label .. "function " .. node.name .. "(" .. table.concat(node.params, ", ") .. ")")
		showBlock(node.body, depth + 1)
	elseif kind == "If" then
		for index, branch in node.branches do
			print(
				(if index == 1 then label else pad .. "        ")
					.. (if index == 1 then "if " else "otherwise if ")
					.. describe(branch.cond)
			)
			showBlock(branch.body, depth + 1)
		end
		if node.elseBody then
			print(pad .. "        otherwise")
			showBlock(node.elseBody, depth + 1)
		end
	else
		print(label .. kind)
	end
end

print("\ncode:  " .. (string.gsub(source, "\n", " / ")) .. "\n")

local tokens = Tokenizer.tokenize(source)
if not tokens.ok then
	local err = tokens.err :: any
	print(string.format("  cannot read it: line %d, column %d", err.line, err.col))
	print("  " .. err.message)
	return
end

local parsed = Parser.parse(tokens.tokens :: any)
if not parsed.ok then
	local err = parsed.err :: any
	print(string.format("  cannot make sense of it: line %d, column %d", err.line, err.col))
	print("  " .. err.message)
	return
end

showBlock(parsed.ast :: any, 1)
