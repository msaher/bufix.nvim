local errors = require("compile.errors")
local busted = require("plenary.busted")


local function tbl_equal(a, b)
    if a == b then return true end

    if type(a) ~= "table" or type(b) ~= "table" then
        return false
    end

    for k, v in pairs(a) do
        if type(v) == "table" then
            if not tbl_equal(v, b[k]) then
                return false
            end
        else
            if v ~= b[k] then
                return false
            end
        end
    end

    -- make "a" has all keys "b" has
    for k in pairs(b) do
        if a[k] == nil then
            return false
        end
    end

    return true
end


busted.describe("error patterns", function()

    local cases = {
        { rule = "absoft", line = "Error on line 3 of t.f: Execution error unclassifiable statement", want = {row_start = 3, filename = "t.f" }},
        { rule = "absoft", line = "Line 45 of \"foo.c\": bloofle undefined", want = {row_start = 45, filename = "foo.c" }},
        { rule = "absoft", line = "error on line 19 of fplot.f: spelling error?", want = {row_start = 19, filename = "fplot.f" }},
        { rule = "absoft", line = "warning on line 17 of fplot.f: data type is undefined for variable d", want = {row_start = 17, filename = "fplot.f" }},

        { rule = "ada", line = "foo.adb:61:11:  [...] in call to size declared at foo.ads:11", want = {row_start = 11, filename = "foo.ads"}},
        { rule = "ada", line = "0x8008621 main+16 at error.c:17", want = { row_start = 17, filename = "error.c" }},
    }

    busted.it("captures error information", function()
        for i, v in ipairs(cases) do
            local got = errors.patterns[v.rule]:match(v.line)
            assert(
                tbl_equal(got, v.want),
                string.format("Test #%d failed for rule '%s' with line '%s'\n\tgot %s, want %s", i, v.rule, v.line, vim.inspect(got), vim.inspect(v.want))
            )
        end
    end)
end)

