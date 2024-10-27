--- Diagnostics for any buffer

local lpeg = vim.lpeg
local P, R, S, V = lpeg.P, lpeg.R, lpeg.S, lpeg.V
local C, Cg, Ct, Cc = lpeg.C, lpeg.Cg, lpeg.Ct, lpeg.Cc

-- Helper patterns
local blank = S(" \t")^0
local digit = R("09")
local digits = digit^1
local any = P(1)
local eol = P("\n")
local rest_of_line = (1 - eol)^0
local file_char = 1 - S(",:\n\t()\"'")
local filename = file_char^1
local dquote = P'"'
local squote = P"'"

-- from https://www.inf.puc-rio.br/~roberto/lpeg/
local function anywhere (p)
  return P{ p + 1 * lpeg.V(1) }
end

local function except(set)
    return 1-S(set)
end

local win_or_unix_filename = (C(R("AZ", "az") * P":" * filename, "filename") + C(filename, "filename"))

local M = {}

M.patterns = {}

-- local I = P(function(_, i)
--     vim.print(i)
-- end)
-- local offset = 0
-- local blank = blank * lpeg.P(
--     function (_, p)
--         offset = math.max(offset, p)
--         return true
--     end)

M.patterns = {
    absoft = Ct({
        ((S"eE" * P"rror on") + (S"wW"*P"arning on"))^-1 * blank *
            S"Ll" * P"ine" * blank *
            Cg(digits / tonumber, "row_start") * blank *
            P"of" * blank *
            dquote^-1 * Cg(filename, "filename") * dquote^-1
    }),


}

return M
