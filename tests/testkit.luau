--!strict
--[[
	A very small test kit, so the interpreter can be tested with Studio closed.

	There is no test framework here on purpose. The whole thing is about sixty
	lines, which means it never needs debugging and never becomes a dependency.
]]

local testkit = {}

local passed = 0
local failed = 0
local failures: { string } = {}
local currentGroup = ""

function testkit.group(name: string)
	currentGroup = name
	print("\n  " .. name)
end

function testkit.check(name: string, condition: boolean, detail: string?)
	if condition then
		passed += 1
		print("    ok   " .. name)
	else
		failed += 1
		local line = currentGroup .. " / " .. name
		if detail then
			line ..= "\n         " .. detail
		end
		table.insert(failures, line)
		print("    FAIL " .. name .. (if detail then "  (" .. detail .. ")" else ""))
	end
end

function testkit.equal(name: string, got: any, want: any)
	testkit.check(name, got == want, "got " .. tostring(got) .. ", wanted " .. tostring(want))
end

function testkit.report(): number
	print("\n" .. string.rep("-", 58))
	if failed == 0 then
		print(string.format("  all %d checks passed", passed))
		return 0
	end
	print(string.format("  %d passed, %d FAILED", passed, failed))
	for _, f in failures do
		print("    - " .. f)
	end
	return 1
end

return testkit
