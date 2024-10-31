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
local function anywhere(p)
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

    cmake_info = Ct({
        Cg(Cc"info", "type") * -- type is always info
        P"  " * (P" *"^-1) *  -- match two spaces and optionally a space with an asterisk
        Cg((1 - P":")^1, "filename") * P":" *
        Cg(digits/tonumber, "row_start")
    }),

    comma = Ct({
        dquote * Cg(filename, "filename") * dquote *
        P", line " * Cg(digits/tonumber, "row_start") *
        ((S".(" + P" pos ") * Cg(digits/tonumber, "col_start") * P")"^-1)^-1 *
        S":.,; (-" * blank * Cg("warning", "type")^-1
    }),

     -- Must be before edg-1, so that MSVC's longer messages are
     -- considered before EDG.
     -- The message may be a "warning", "error", or "fatal error" with
     -- an error code, or "see declaration of" without an error code.
    msft = Ct({
        -- Optional number followed by ">"
        (digits * P(">"))^-1 *
        -- optional window drive followed by filename
        Cg((R("AZ", "az") * P":")^-1 * except" :(\t\n" * except":(\t\n"^1, "filename") *
        -- row
        P("(") * Cg(digits/tonumber, "row_start") *
        -- optional column
        (P(",") * Cg(digits/tonumber, "col_start"))^-1 * P(")") *
        -- colon
        blank * P(":") * blank *
        -- optional "see declaration"
        (P("see declaration") +
        P("warning") * Cg(Cc("warning"), "type"))^-1 -- optional warning
        -- + P("error") * -[[ Cg(Cc("error"), "type") --]])^-1 -- optional error
    }),

    edg_1 = Ct({
        Cg((except(" (\n"))^1, "filename") *
        "(" * Cg(digits / tonumber, "row_start") * ")" *
        ": " *
        ("error" + Cg("warning", "type") + "remark" * Cg(Cc"info", "type"))  -- error/warning/remark
    }),

    edg_2 = Ct({
        anywhere(P"at line ") * Cg(digits / tonumber, "row_start") * " of " *
        dquote * Cg(except(" \"\n")^1, "filename") * dquote
    }),

    epc = Ct({
        "Error " * digits * " at " *
        "(" * Cg(digits / tonumber, "row_start") * ":" * Cg(except(")\n")^1, "filename") * ")"
    }),

    ftnchek = Ct({
        ("Warning " * Cg(Cc"warning", "type") * (1-P"line")^1)^-1 * -- optional warning
        anywhere("line") * S" \n" * Cg(digits/tonumber, "row_start") * S" \n" *
        ("col " * Cg(digits/tonumber, "col_start") * S" \n")^-1 * -- optional column
        "file " * Cg(except(" :;\n")^1, "filename")
    }),

    gradle_kotlin = Ct({
        (P"w"*Cg(Cc"warning", "type"))^-1 * except(":")^-1 * ": " *
            P"file://" * Cg(except":"^1, "filename") *
            ":" * Cg(digits/tonumber, "row_start") *
            ":" * Cg(digits/tonumber, "col_start")
    }),


    iar = Ct({
        dquote * Cg((1 - dquote)^0, "filename") * dquote *
        "," * Cg(digits / tonumber, "row_start") * blank *
        (P("Warning") * Cg(Cc("warning"), "type"))^-1
    }),

    ibm = Ct({
        Cg(except" \n\t("^1, "filename") *
        "(" * Cg(digits / tonumber, "row_start") * -- row number
        ":" * Cg(digits / tonumber, "col_start") * -- column number
        ") :" *
        -- optional warning or ifnormation
        (Cg("warning", "type") + Cg("info", "type"))^-1
    }),

}

M.patterns.irix = Ct({
    -- prefix: alphanumeric characters, dashes, underscores, slashes, spaces, followed by ": "
    ((R("AZ", "az", "09") + S("-_/ ")) - ":")^1 * ": " *

    -- error type ("Info", "Warning", "Error", "Severe"), followed by optional error number
    (
        (
        S"Ss"*"evere"                              +
        S"Ee"*"rror"                               +
        S"Ww"*"arning" * Cg(Cc("warning"), "type") +
        S"Ii"*"nfo"    * Cg(Cc("info"), "type")
        ) *

        (blank * digit^1)^-1 * -- optional numeric code after error type
        ":"
    )^-1 * blank *

    Cg(except",\": \n\t"^1, "filename") *

    (P", line " + P":")* blank * Cg(digits / tonumber, "row_start")
})


M.patterns.java = Ct({
    ((S(" \t")^1 * "at ") + ("==" * digits * "==" * blank * ("at" + "by" * Cg(Cc"warning", "type"))))^1 * blank *
    -- search for (filename:row_start) anywhere
    anywhere("(" * Cg(except("):")^0, "filename") * ":" * Cg(digits/tonumber, "row_start") * ")" * -1)
})

M.patterns.jikes_file = Ct({
    (P"Found" + P"Issued") *
    (1-P"compiling")^1 * P"compiling " * dquote *
    Cg(except("\"\n")^1, "filename") * dquote * P":"
})

M.patterns.jikes_line = Ct({
    blank * Cg(digits/tonumber, "row_start") * P"." * blank * rest_of_line * eol *
    blank * P"<" * P"-"^0 * P">" * eol *
    P"*** " * (P"Error" + P"Warning" * Cg(Cc"warning", "type"))
})


M.patterns.maven = Ct({
    ("[ERROR]" + "[WARNING]"*Cg(Cc"warning", "type") + "INFO"*Cg(Cc"info", "type"))^-1 * blank *
    Cg(except(" \n[:")^1, "filename") * ":" *
    "[" * Cg(digits/tonumber, "row_start") * "," * Cg(digits/tonumber, "col_start") * "]"
})

M.patterns.clang_include = Ct({
    Cg(Cc"info", "type") * -- always info
    P"In file included from " * Cg(except(":\n")^1, "filename") * ":" * Cg(digits/tonumber, "row_start") * ":" * -1
})

M.patterns.gcc_include = Ct({
    (P"In file included " + blank) * "from " *
    digit^0 * -- idk why. just translating regex
    Cg(except(":")^1, "filename") * ":" *
    Cg(digits/tonumber, "row_start") *
    (":" * Cg(digits/tonumber, "col_start"))^-1 -- optional col

})

M.patterns["ruby_Test::Unit"] = Ct({
    blank * P"["^-1 *
    Cg(except(":")^1, "filename") * ":" *
    Cg(digits / tonumber, "row_start") * ":" *
    P"in"
})

M.patterns.gmake = Ct({
    Cg(Cc"info", "type") * -- always info
    except(":")^1 * ":" * " *** " *
    "[" *
    Cg(except(":")^1, "filename") * ":" *
    Cg(digits / tonumber, "row_start")
})

local regex = "^\\%([[:alpha:]][-[:alnum:].]\\+: \\?\\|[ \t]\\%(in \\| from\\)\\)\\?\\(\\%([0-9]*[^0-9\\n]\\)\\%([^\\n :]\\| [^-/\\n]\\|:[^ \\n]\\)\\{-}\\)\\%(: \\?\\)\\([0-9]\\+\\)\\%(-\\([0-9]\\+\\)\\%(\\.\\([0-9]\\+\\)\\)\\?\\|[.:]\\([0-9]\\+\\)\\%(-\\%(\\([0-9]\\+\\)\\.\\)\\([0-9]\\+\\)\\)\\?\\)\\?:\\%( *\\(\\%(FutureWarning\\|RuntimeWarning\\|W\\%(arning\\)\\|warning\\)\\)\\| *\\([Ii]nfo\\%(\\>\\|formationa\\?l\\?\\)\\|I:\\|\\[ skipping .\\+ ]\\|instantiated from\\|required from\\|[Nn]ote\\)\\| *\\%([Ee]rror\\)\\|\\%([0-9]\\?\\)\\%([^0-9\\n]\\|$\\)\\|[0-9][0-9][0-9]\\)"

-- ;; The `gnu' message syntax is
-- ;;   [PROGRAM:]FILE:LINE[-ENDLINE]:[COL[-ENDCOL]:] MESSAGE
-- ;; or
-- ;;   [PROGRAM:]FILE:LINE[.COL][-ENDLINE[.ENDCOL]]: MESSAGE
M.patterns.gnu = Ct({
    [1] = V'without_program' + V'with_program',

    without_program = V'yapping'^-1  * V'data',
    with_program =  V'program' * ":" * V'data',
    data = V'filename' * ":" * V'location' * P":"^-1 * blank * V'type'^-1,

    yapping = blank * (P"in " + P"from" + "|"),
    program = (R("AZ", "az") * (R("AZ", "az", "09") + S".-_")^1),

    -- captures filename.
    -- Avoids entirely numerical filenames
    -- type of files:
    -- has space
    -- has colon
    -- has no space nor colon
    filename = Cg(R"09"^0 * (1-(R"09"+"\n")) *
                    -- three possible cases to match the rest of the filename
                  (except"\n :"^1 + (P" " * (except"-/\n")^1) + (P":" * except":\n"^1))
            , "filename"),

    -- save some typing
    nums = R("09")^1 / tonumber,
    row_start = Cg(V'nums', "row_start"),
    row_end = Cg(V'nums', "row_end"),
    col_start = Cg(V'nums', "col_start"),
    col_end = Cg(V'nums', "col_end"),

    location = V'location_format1' + V'location_format2',

    location_format1 = V'row_start' * (P"-" * V'row_end')^-1 * S":." * (V'col_start' * (P"-" * V'col_end' * P":")^-1)^-1,
    location_format2 = V'row_start' * (P"." * V'col_start')^-1 * (P"-" * V'row_end' * (P"." * V'col_end')^-1)^-1 * P":",

    type = V'warning' + V'info' + V'error',

    warning = (P"FutureWarning" + P"RuntimeWarning" + P"W" + S("Ww")*P"arning") * Cg(Cc"warning", "type"),
    info = ((S"Ii"*"nfo" * (P"rmation" + P"l"^-1)^-1) + P"I:" + (P"[ skipping " * except("]")^1 * "]") + P"instantiated from" + P"required from" + S"Nn"*"ote") * Cg(Cc"info", "type"),
    error = S"Ee"*"rror",
})

M.patterns.cucumber = Ct(
    anywhere(
        (P"cucumber" * (P" -p " * (1-blank)^1)^-1) +
        "     " +
        "#"
    ) * blank *
    Cg(except("(:")^1, "filename") * ":" *
    Cg(digits / tonumber, "row_start")
)

M.patterns.lcc = Ct(
    (P"E" + P"W" * Cg(Cc"warning", "type")) * ", " *
    Cg(except("^(\n")^1, "filename") * "(" *
    Cg(digits/tonumber, "row_start") * "," * blank *
    Cg(digits/tonumber, "col_start")
)

M.patterns.makepp = Ct({
    [1] = V'prefix' * blank * V'path',
    prefix = P"makepp" *
        (
            (P": warning" * Cg(Cc"warning", "type") * ":" * except("`")^0) +
            (P": Scanning") +
            (P": " * S"Rr"*"eloading") +
            (P": " * S"Ll"*"oading") +
            (P": Imported") +
            (P"log:" * except("`")^0) +
            (P": " * except("`")^0)
        ),

    path = "`" * Cg(except(":' \t")^1, "filename") *
           (":" * Cg(digits/tonumber, "row_start"))^-1 * -- optional line number
            "'", -- ends with a single quote

})

M.patterns.mips_1 = Ct(
    anywhere(
        "(" * Cg(digits/tonumber, "row_start") * ")" * " in " *
        Cg(except" \n"^1, "filename")
    )
)

M.patterns.mips_2 = Ct(
    anywhere(
        " in " *
        Cg(except"(\n"^1, "filename") *
        "(" * Cg(digits/tonumber, "row_start") * ")"
    )
)

M.patterns.omake = Ct(
    "*** omake: file" *
    Cg((1-P("changed")^-1), "filename") * P("changed")
)

return M
