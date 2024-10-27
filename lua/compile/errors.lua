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

    ada = Ct(
        (P"warning: " * Cg(Cc"warning", "type"))^-1 *
        (any-P" at ")^0 * P" at " * Cg(filename, "filename") *
        P(":") * Cg(digits / tonumber, "row_start")
    ),

    aix = Ct({
        anywhere(" in line ") *
        Cg(digits / tonumber, "row_start") *
        " of file " *
        Cg((any - S(" \n"))^1, "filename")
    }),

    ant = Ct({
        -- optional one or two bracketed sections with content inside
        (blank * P"[" * (any - S"] \n")^1 * P"]" * blank)^-2 *
            -- windows or unix path
            (Cg(R("AZ", "az") * P":" * filename, "filename") + Cg(filename, "filename")) *
            -- line number
            P":" * Cg(digits / tonumber, "row_start") *
            -- optional column information
            (P":" * Cg(digits / tonumber, "col_start") *
            P":" * Cg(digits / tonumber, "row_end") *
            P":" * Cg(digits / tonumber, "col_end"))^-1 *
            -- optional " warning" keyword. If it exists,
            (":" * P" warning" * Cg(Cc("warning"), "type"))^-1
    }),

    bash = Ct({
        Cg(filename, "filename") * P":" * P" line " * Cg(digits / tonumber, "row_start")
    }),

    borland = Ct({
        -- optionally check if warning or error
        (P"Error" + ("Warning" * Cg(Cc("warning"), "type")))^-1 * blank *
        -- optionally match error/warning code
        (S"FEW"*digits)^-1 * blank *
        -- windows or unix path
        (Cg(R("AZ", "az") * P":" * -S("^:( \t\n"), "filename") + Cg(except(":( \t\n")^1, "filename")) * blank *
        -- row
        Cg(digits / tonumber, "row_start")
    }),

    python_tracebacks_and_caml = Ct({
        blank * P"File " * dquote^-1 * Cg(win_or_unix_filename, "filename") * dquote^-1 *
        -- find lines
        P", line" * P"s"^-1 * blank * Cg(digits/tonumber, "row_start") * ("-" * Cg(digits/tonumber, "row_end"))^-1 * P","^-1 *
        -- optionaly characters section
        (P" characters " * Cg(digits/tonumber, "col_start") * ("-" * Cg(digits/tonumber, "col_end"))^-1)^-1
    }),

    cmake = Ct({
        P"CMake " * (P"Error" + P"Warning" * Cg(Cc"warning", "type")) *
        P" at " * Cg(filename, "filename") * P":" *
        Cg(digits/tonumber, "row_start")
    }),

}

return M
