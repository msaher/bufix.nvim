---@class Span
---@field start number
---@field finish number
---@field value string | number

--HACK: generics are not supported yet in lua-ls
--https://github.com/LuaLS/lua-language-server/issues/1861
--span value is string | number

---@class Capture
---@field filename Span
---@field line? Span
---@field line_end? Span
---@field col? Span
---@field col_end? Span
---@field type? Span

local lpeg = vim.lpeg
local P, R, S, V = lpeg.P, lpeg.R, lpeg.S, lpeg.V
local C, Cg, Ct, Cc, Cp = lpeg.C, lpeg.Cg, lpeg.Ct, lpeg.Cc, lpeg.Cp

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

-- from https://www.inf.puc-rio.br/~roberto/lpeg/
local function anywhere(p)
  return P{ p + 1 * lpeg.V(1) }
end

local function except(set)
    return 1-S(set)
end

local win_or_unix_filename = (C(R("AZ", "az") * P":" * filename, "filename") + C(filename, "filename"))

local function Cg_span(patt, name)
    return Cg(
        Ct(
            Cp() * -- start position
            Cg(patt, "value") *
            Cp() -- end
        ) / function(t)
            return { start = t[1], value = t.value, finish = t[2] }
        end,
        name
    )
end

local M = {}

M.absoft = Ct(
    ((S"eE" * P"rror on") + (S"wW"*P"arning on"))^-1 * blank *
        S"Ll" * P"ine" * blank *
        Cg_span(digits / tonumber, "line") * blank *
        P"of" * blank *
        dquote^-1 * Cg_span(filename, "filename") * dquote^-1
)

M.ada = Ct(
    (P"warning: " * Cg_span(Cc"warning", "type"))^-1 *
    (any-P" at ")^0 * P" at " * Cg_span(filename, "filename") *
    P(":") * Cg_span(digits / tonumber, "line") * -1
)

M.aix = Ct(
    anywhere(" in line ") *
    Cg_span(digits / tonumber, "line") *
    " of file " *
    Cg_span((any - S(" \n"))^1, "filename")
)

M.ant = Ct({
    [1] = V'bracket_part' * V'bracket_part'^-1 *
        -- windows or unix path
        (Cg_span(R("AZ", "az") * P":" * filename, "filename") + Cg_span(filename, "filename")) *
        -- line number
        P":" * Cg_span(digits / tonumber, "line") *
        -- optional column information
        (P":" * Cg_span(digits / tonumber, "col") *
        P":" * Cg_span(digits / tonumber, "line_end") *
        P":" * Cg_span(digits / tonumber, "col_end"))^-1 *
        -- optional " warning" keyword. If it exists,
        (":" * P" warning" * Cg_span(Cc("warning"), "type"))^-1,


    bracket_part = blank * P"[" * (any - S"] \n")^1 * P"]" * blank,
})

M.bash = Ct(
    Cg_span(filename, "filename") * P":" * P" line " * Cg_span(digits / tonumber, "line")
)

M.borland = Ct(
    -- check type
    (P"Error" + ("Warning" * Cg_span(Cc("warning"), "type"))) * " " *

    ((S"FEW"*digits) * blank)^-1 *

    -- windows or unix path
    (Cg_span(R("AZ", "az") * P":" * -S("^:( \t\n"), "filename") + Cg_span(except(":( \t\n")^1, "filename")) * blank *
    -- row
    Cg_span(digits / tonumber, "line")
)

M.python_tracebacks_and_caml = Ct(
    blank * P"File " * dquote^-1 * Cg_span(win_or_unix_filename, "filename") * dquote^-1 *
    -- find lines
    P", line" * P"s"^-1 * blank * Cg_span(digits/tonumber, "line") * ("-" * Cg_span(digits/tonumber, "line_end"))^-1 * P","^-1 *
    -- optionaly characters section
    (P" characters " * Cg_span(digits/tonumber, "col") * ("-" * Cg_span(digits/tonumber, "col_end"))^-1)^-1
)

M.cmake = Ct(
    P"CMake " * (P"Error" + P"Warning" * Cg_span(Cc"warning", "type")) *
    P" at " * Cg_span(filename, "filename") * P":" *
    Cg_span(digits/tonumber, "line")
)

M.cmake_info = Ct(
    Cg_span(Cc"info", "type") * -- type is always info
    P"  " * (P" *"^-1) *  -- match two spaces and optionally a space with an asterisk
    Cg_span((1 - S" :")^1, "filename") * P":" *
    Cg_span(digits/tonumber, "line")
)

M.comma = Ct(
    dquote * Cg_span(filename, "filename") * dquote *
    P", line " * Cg_span(digits/tonumber, "line") *
    ((S".(" + P" pos ") * Cg_span(digits/tonumber, "col") * P")"^-1)^-1 *
    S":.,; (-" * blank * Cg_span("warning", "type")^-1
)

 -- Must be before edg-1, so that MSVC's longer messages are
 -- considered before EDG.
 -- The message may be a "warning", "error", or "fatal error" with
 -- an error code, or "see declaration of" without an error code.
M.msft = Ct(
    -- Optional number followed by ">"
    (digits * P(">"))^-1 *
    -- optional window drive followed by filename
    Cg_span((R("AZ", "az") * P":")^-1 * except" :(\t\n" * except":(\t\n"^1, "filename") *
    -- row
    P("(") * Cg_span(digits/tonumber, "line") *
    -- optional column
    (P(",") * Cg_span(digits/tonumber, "col"))^-1 * P(")") *
    -- colon
    blank * P(":") * blank *
    -- optional "see declaration"
    (P("see declaration") +
    P("warning") * Cg_span(Cc("warning"), "type"))^-1 -- optional warning
    -- + P("error") * -[[ Cg_span(Cc("error"), "type") --]])^-1 -- optional error
)

M.edg_1 = Ct(
    Cg_span((except(" (\n"))^1, "filename") *
    "(" * Cg_span(digits / tonumber, "line") * ")" *
    ": " *
    ("error" + Cg_span("warning", "type") + "remark" * Cg_span(Cc"info", "type"))  -- error/warning/remark
)

M.edg_2 = Ct(
    anywhere(P"at line ") * Cg_span(digits / tonumber, "line") * " of " *
    dquote * Cg_span(except(" \"\n")^1, "filename") * dquote
)

M.epc = Ct(
    "Error " * digits * " at " *
    "(" * Cg_span(digits / tonumber, "line") * ":" * Cg_span(except(")\n")^1, "filename") * ")"
)

M.ftnchek = Ct(
    ("Warning " * Cg_span(Cc"warning", "type") * (1-P"line")^1)^-1 * -- optional warning
    anywhere("line") * S" \n" * Cg_span(digits/tonumber, "line") * S" \n" *
    ("col " * Cg_span(digits/tonumber, "col") * S" \n")^-1 * -- optional column
    "file " * Cg_span(except(" :;\n")^1, "filename")
)

M.gradle_kotlin = Ct(
    (P"w"*Cg_span(Cc"warning", "type"))^-1 * except(":")^-1 * ": " *
        P"file://" * Cg_span(except":"^1, "filename") *
        ":" * Cg_span(digits/tonumber, "line") *
        ":" * Cg_span(digits/tonumber, "col")
)

M.iar = Ct(
    dquote * Cg_span((1 - dquote)^0, "filename") * dquote *
    "," * Cg_span(digits / tonumber, "line") * blank *
    (P("Warning") * Cg_span(Cc("warning"), "type"))^-1
)

M.ibm = Ct(
    Cg_span(except" \n\t("^1, "filename") *
    "(" * Cg_span(digits / tonumber, "line") * -- row number
    ":" * Cg_span(digits / tonumber, "col") * -- column number
    ") :" *
    -- optional warning or ifnormation
    (Cg_span("warning", "type") + Cg_span("info", "type"))^-1
)

-- NOTE: In htop the uptime part matches (same behaviour as emacs)
-- "                         Uptime: 05:00:38" <-- match
-- This can be fixed by disallowing digit only filenames
M.irix = Ct(
    -- prefix: alphanumeric characters, dashes, underscores, slashes, spaces, followed by ": "
    ((R("AZ", "az", "09") + S("-_/ ")) - ":")^1 * ": " *

    -- error type ("Info", "Warning", "Error", "Severe"), followed by optional error number
    (
        (
        S"Ss"*"evere"                              +
        S"Ee"*"rror"                               +
        S"Ww"*"arning" * Cg_span(Cc("warning"), "type") +
        S"Ii"*"nfo"    * Cg_span(Cc("info"), "type")
        ) *

        (" " * digit^1)^-1 * -- optional numeric code after error type
        ":"
    )^-1 * P(" ")^-1 *

    Cg_span(except",\": \n\t"^1, "filename") *

    (P", line " + P":") * P(" ")^-1 * Cg_span(digits / tonumber, "line")
)


M.java = Ct(
    ((S(" \t")^1 * "at ") + ("==" * digits * "==" * blank * ("at" + "by" * Cg_span(Cc"warning", "type"))))^1 * blank *
    -- search for (filename:line) anywhere
    anywhere("(" * Cg_span(except("):")^0, "filename") * ":" * Cg_span(digits/tonumber, "line") * ")" * -1)
)

M.jikes_file = Ct(
    (P"Found" + P"Issued") *
    (1-P"compiling")^1 * P"compiling " * dquote *
    Cg_span(except("\"\n")^1, "filename") * dquote * P":"
)

M.jikes_line = Ct(
    blank * Cg_span(digits/tonumber, "line") * P"." * blank * rest_of_line * eol *
    blank * P"<" * P"-"^0 * P">" * eol *
    P"*** " * (P"Error" + P"Warning" * Cg_span(Cc"warning", "type"))
)


M.maven = Ct(
    ("[ERROR]" + "[WARNING]"*Cg_span(Cc"warning", "type") + "INFO"*Cg_span(Cc"info", "type"))^-1 * blank *
    Cg_span(except(" \n[:")^1, "filename") * ":" *
    "[" * Cg_span(digits/tonumber, "line") * "," * Cg_span(digits/tonumber, "col") * "]"
)

M.clang_include = Ct(
    Cg_span(Cc"info", "type") * -- always info
    P"In file included from " * Cg_span(except(":\n")^1, "filename") * ":" * Cg_span(digits/tonumber, "line") * ":" * -1
)

M.gcc_include = Ct(
    (P"In file included " + blank) * "from " *
    digit^0 * -- idk why. just translating regex
    Cg_span(except(":")^1, "filename") * ":" *
    Cg_span(digits/tonumber, "line") *
    (":" * Cg_span(digits/tonumber, "col"))^-1 -- optional col

)

M["ruby_Test::Unit"] = Ct(
    blank * P"["^-1 *
    Cg_span(except(":{(")^1, "filename") * ":" *
    Cg_span(digits / tonumber, "line") * ":" *
    P"in"
)

M.gmake = Ct(
    Cg_span(Cc"info", "type") * -- always info
    except(":")^1 * ":" * " *** " *
    "[" *
    Cg_span(except(":")^1, "filename") * ":" *
    Cg_span(digits / tonumber, "line")
)

-- ;; The `gnu' message syntax is
-- ;;   [PROGRAM:]FILE:LINE[-ENDLINE]:[COL[-ENDCOL]:] MESSAGE
-- ;; or
-- ;;   [PROGRAM:]FILE:LINE[.COL][-ENDLINE[.ENDCOL]]: MESSAGE
M.gnu = Ct({
    [1] = V'with_program' + V'without_program',

    without_program = V'yapping'^-1  * V'data',
    with_program =  V'program' * ":" * V'data',
    data = V'filename' * ":" * V'location' * P":"^-1 * blank * V'type'^-1,

    yapping = blank * (P"in " + P"from" + "|"),
    program = (R("AZ", "az") * (R("AZ", "az") + S".-_")^1),


    -- filenames cannot start with a digit
    non_digit = (1-(R"09"+"\n")),

    -- if part of the filename contains a space, ensure the next character is NOT dash
    -- or slash or newline or a another space. This rejects rare cases.
    -- Further, ensure that what follows is NOT a timestamp.
    -- This reject lines that contains "HH:MM:SS" where "MM" is interpreted as a line number
    with_space = " " * -V'timestamp' * except(" -/\n"),

    -- If part of the filename contains a colon, then esure what follows is NOT
    -- a location nor a colon
    with_colon = ":" * -V'location' * except(":\n"),

    -- normal file content
    with_sanity = except(" :\n"),

    filename = Cg_span(V'non_digit' * (V'with_space' + V'with_colon' + V'with_sanity')^0, "filename"),

    -- save some typing
    nums = R("09")^1 / tonumber,
    line = Cg_span(V'nums', "line"),
    line_end = Cg_span(V'nums', "line_end"),
    col = Cg_span(V'nums', "col"),
    col_end = Cg_span(V'nums', "col_end"),

    location = (V'location_format1' + V'location_format2'),

    location_format1 = V'line' * (P"-" * V'line_end')^-1 * S":." * (V'col' * (P"-" * V'col_end')^-1 * P":")^-1,
    location_format2 = V'line' * (P"." * V'col')^-1 * (P"-" * V'line_end' * (P"." * V'col_end')^-1)^-1 * P":",

    digit = R"09",
    timestamp = V'digit'*V'digit' * ":" * V'digit'*V'digit', -- HH:MM
    -- not_timestamp = -(R"09" * R"09"),
    type = V'warning' + V'info' + V'error',

    warning = (P"FutureWarning" + P"RuntimeWarning" + P"W" + S("Ww")*P"arning") * Cg_span(Cc"warning", "type"),
    info = ((S"Ii"*"nfo" * (P"rmation" + P"l"^-1)^-1) + P"I:" + (P"[ skipping " * except("]")^1 * "]") + P"instantiated from" + P"required from" + S"Nn"*"ote") * Cg_span(Cc"info", "type"),
    error = S"Ee"*"rror",
})

M.cucumber = Ct(
    (
        P"cucumber" * (P" -p " * (1-P(" ")^1))^-1 +
        "      " +
        anywhere(" # ")
    ) *
    Cg_span(except(" (:")^1, "filename") * ":" *
    Cg_span(digits / tonumber, "line")

)

M.lcc = Ct(
    (P"E" + P"W" * Cg_span(Cc"warning", "type")) * ", " *
    Cg_span(except("^(\n")^1, "filename") * "(" *
    Cg_span(digits/tonumber, "line") * "," * blank *
    Cg_span(digits/tonumber, "col")
)

M.makepp = Ct({
    [1] = V'prefix' * blank * V'path',
    prefix = P"makepp" *
        (
            (P": warning" * Cg_span(Cc"warning", "type") * ":" * except("`")^0) +
            (P": Scanning") +
            (P": " * S"Rr"*"eloading") +
            (P": " * S"Ll"*"oading") +
            (P": Imported") +
            (P"log:" * except("`")^0) +
            (P": " * except("`")^0)
        ),

    path = "`" * Cg_span(except(":' \t")^1, "filename") *
           (":" * Cg_span(digits/tonumber, "line"))^-1 * -- optional line number
            "'", -- ends with a single quote

})

M.mips_1 = Ct(
    anywhere(
        "(" * Cg_span(digits/tonumber, "line") * ")" * " in " *
        Cg_span(except" \n"^1, "filename")
    )
)

M.mips_2 = Ct(
    anywhere(
        " in " *
        Cg_span(except"(\n"^1, "filename") *
        "(" * Cg_span(digits/tonumber, "line") * ")"
    )
)

M.omake = Ct(
    "*** omake: file" *
    Cg_span((1-P("changed")^-1), "filename") * P("changed")
)

M.oracle = Ct(
    (
        P"Semantic error" +
        P"Error" +
        P"PCC-" * digits * ":"
    ) *

    (1-P("line"))^0 * "line " *
    Cg_span(digits/tonumber, "line") *

    -- optional column
    ((P"," + P" at")^-1 * P" column " *
    Cg_span(digits/tonumber, "col")
    )^-1 *

    (P"," + P" in" + P" of" )^-1 * " file " *
    Cg_span(except(":")^1, "filename")
)

M.perl = Ct(
    anywhere(P" at " *
        Cg_span(except(" \n")^1, "filename") *
        " line " *
        Cg_span(digits/tonumber, "line") *
        (
            S",." +
            -1 +
            P" during global destruction." * -1
        )
    )
)

M.php = Ct(
    anywhere(
        (P"Parse" + P"Fatal") *
        " error: " *
        (1-P(" in "))^1 * " in " *

        Cg_span((1-P(" on line "))^1, "filename") * " on line " *
        Cg_span(digits/tonumber, "line")
    )
)

M.rxp = Ct(
    "in" *
    (1-P"at ")^1 * "at " *
    "line " * Cg_span(digits/tonumber, "line") * " " *
    "char " * Cg_span(digits/tonumber, "col")  * " " *
    "of file://" * Cg_span(P(1)^1, "filename")
)

M.shellcheck = Ct(
    "In " * Cg_span((1-P(" line "))^1, "filename") * " line " *
    Cg_span(digits/tonumber, "line") * ":"
)

M.sun = Ct(
    anywhere(": ") *
    (
        "ERROR" +
        "WARNING" * Cg_span(Cc"warning", "type") +
        "REMARK" * Cg_span(Cc"info", "type")
    ) *
    (1-P("File = "))^0 * -- optional yapping
    "File = " * Cg_span((1-P",")^1, "filename") * ", " *
    "Line = " * Cg_span(digits/tonumber, "line") *
    (P", " * "Column = " * Cg_span(digits/tonumber, "col"))^-1

)

M.sun_ada = Ct(
    Cg_span(except(",\n\t")^1, "filename") *
    ", line " * Cg_span(digits/tonumber, "line") *
    ", char " * Cg_span(digits/tonumber, "col") *
    S":., (-"
)

M.watcom = Ct(
    blank *
    Cg_span(except("(")^1, "filename") *
    "(" * Cg_span(digits/tonumber, "line") * ")" *
    ": " *
    (
        P"Error! E" * digits +
        P"Warning! W" * digits * Cg_span(Cc"warning", "type")
    )
    * ":"

)

return M
