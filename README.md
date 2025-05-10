# Introduction

> This plugin is currently in the testing phase. Breaking changes might occur

Jump through `:terminal`'s errors (or any other buffer).

`bufix.nvim` is a navigation plugin similar to the quickfix list, but works on arbitrary buffers like `:terminal` buffers.

Some differences compared to the quickfix list

1. bufix buffers work on "live" buffers like terminals. This makes them useful when running servers or logging commands like `tail -f`.
2. It parses using `:h vim.lpeg`. This means that you do not have to mess with `:h errorformat`.
3. The cursor gets highlighted when jumping through errors (configurable).

Limitations:

1. Currently, multi-line errors are not supported

This plugin is inspired by emacs' M-x compile.

https://github.com/user-attachments/assets/5ca33b68-bec3-44cc-b36b-ab0726b24a3d

## Installation

This plugin requires nvim >= 0.10

With lazy

```lua
{
    "msaher/bufix.nvim"
    -- calling setup is optional :)
}
```

## Quickstart

Run `:Bufix register` to register the current buffer as a bufix buffer (try doing it on a terminal buffer that has some output like `:term grep -rn <string>`). You'll be able to jump through them using `:Bufix next` and `:Bufix prev`. You can also press `<CR>` on a path to
jump directly to it

Handy keymaps:

```lua
vim.keymap.set("n", "]e",        "<cmd>Bufix next<CR>", { desc = "Go to next error"})
vim.keymap.set("n", "[e",        "<cmd>Bufix prev<CR>", { desc = "Go to prev error"})

--- or if you prefer to use the API
vim.keymap.set("n", "]e",        function() require("bufix.api").goto_next()       end , { desc = "Go to next error"}))
vim.keymap.set("n", "[e",        function() require("bufix.api").goto_prev()       end , { desc = "Go to prev error"}))
```

To always mark `:terminal` as bufix buffers

```lua
local group = vim.api.nvim_create_augroup("BufixTerm", { clear = true })
vim.api.nvim_create_autocmd("TermOpen", {
    group = group,
    callback = function(opts)
        require("bufix.api").register_buf(opts.buf) -- make it work with goto_next() and friends
    end,
})
```

# Commands

`:Bufix`
: Prompts for a sub command

`:Bufix next`
: Go to the next error in the nav buffer

`:Bufix prev`
: Go to the previous error in the nav buffer

`:Bufix next-file`
: Go to the next file in the nav buffer

`:Bufix prev-file`
: Go to the previous file in the nav buffer

# Configuration

Configuration is done through calling `require("bufix").setup()`. It justs sets
`cfg` to the `require("bufix").config` table. The default configuration is:

```lua

-- DONT COPY PASTE THIS ITS JUST THE DEFAULT CONFIG
-- Read the next section to learn more about the options
require("bufix").setup({
    --- Buffer local keymaps in bufix buffers. Such as <CR> to jump or <C-q> to
    --- send to qflist
    ---@type boolean
    want_buffer_keymaps = true,

    --- How long to highlight the cursor after jumping. Set it to 0 to disable
    --- it.
    ---@type number in milliseconds
    locus_highlight_duration = 500,

    ---Add any aditional parsing rules
    ---See `:h bufix-rules` to learn more
    ---@type table
    rules = {}

})
```

If `want_buffer_keymaps` is true, then these buffer local mappings are set for
nav buffers (like task buffers):

```lua
    vim.keymap.set("n", "<CR>" , require("bufix.api").goto_error_under_cursor,    { buffer = buf,  desc = "Go to error under cursor"})
    vim.keymap.set("n", "g<CR>", require("bufix.api").display_error_under_cursor, { buffer = buf,  desc = "Dispaly error under cursor"})
    vim.keymap.set("n", "gj"   , require("bufix.api").move_to_next,               { buffer = buf,  desc = "Move cursor to next error"})
    vim.keymap.set("n", "gk"   , require("bufix.api").move_to_prev,               { buffer = buf,  desc = "Move cursor to prev error"})
    vim.keymap.set("n", "]]"   , require("bufix.api").move_to_next_file,          { buffer = buf,  desc = "Move cursor to next file"})
    vim.keymap.set("n", "[["   , require("bufix.api").move_to_prev_file,          { buffer = buf,  desc = "Move cursor to prev file"})

    vim.keymap.set("n", "<C-q>", function()
        require("bufix.api").send_to_qflist()
        vim.cmd.copen()
    end,
    { buffer = buf, desc = "Send errors to qflist"})
```

Where `buf` is the bufix buffer.

---

`api.goto_prev()`
: Go to the previous error

`api.goto_next_file()`
: Go to the next error

`api.goto_prev_file()`
: Go to the prevous error

`api.move_to_next()`
: Move cursor to next error line

`api.move_to_prev()`
: Move cursor to previous error line

`api.goto_error_under_cursor()`
: Go to the error under the cursor

`api.display_error_under_cursor()`
: Visit file containing the error,
but do focus on its window

`api.set_buf({buf})`
: Makes {buf} the current nav buffer.

functions that operate on the current bufix buffer:

  - `api.goto_error_under_cursor()`
  - `api.display_error_under_cursor()`
  - `api.move_to_next()`
  - `api.move_to_prev()`
  - `api.move_to_next_file()`
  - `api.move_to_prev_file()`

`api.register_buf({buf})`
: Register `{buf}` as a bufix buffer

If there's no bufix buffer, then sets `{buf}` as the nav buffer. Otherwise, it
only adds error highlighting and sets `b:bufix_buf = true`. When the current bufix
buffer gets deleted, `{buf}` becomes a potential candidate to be the next bufix
buffer.

For example, if there are two bufix buffers `A` and `B`, and `A` is the current
one. Once buffer `A` gets deleted, buffer `B` becomes the current bufix buffer.

`api.send_to_qflist({buf})`
: Parse `{buf},` and send it the quickfix list
as per the error rules. `{buf}` doesn't have
to be a bufix buffer. If want to use the
built-in `:h :errorformat`, then use
`:h cbuffer` instead.

`api.match({line})`
: Parses `{line}` and returns a `Capture` if successful.

# Highlights

The following highlights are provided:

`BufixFilename`
: highlight group for filename

`BufixLine`
: highlight group for line number

`BufixLineEnd`
: highlight group for ending line number

`BufixCol`
: highlight group for column number

`BufixColEnd`
: highlight group for ending column number

`BufixType`
: highlight group for error type

`BufixCurrent`
: highlight group for the sign column
arrow pointing at current error

# Rules

Errors are parsed according to "rules". There are two types of rules:

1. `:h vim.lpeg` grammars (advanced). Powerful and expressive, but might be
   overkill for simple error messages
2. `:h errorformat`. Uses vim's built-in error formats used in `:h quickfix`.

To add new rules or overwrite existing ones configure the `rules` in `.setup()`.

```lua
require("bufix").setup({
    rules = {
        my_rule = vim.lpeg(<your_rule>)
        another_rule = "<or_your_errorformat>"
    }
})
```

Example using `:h errorformat`:

```lua
require("bufix").setup({
    rules = {
        love = [[Error: %*[^\ ] error: %f:%l: %m]]
    }
})
```

---

Each `lpeg` rule returns a single table (we call it the `Capture`) with entries
in the following form:

```lua
---@class Capture
---@field filename Span // only required part
---@field line? Span
---@field line_end? Span
---@field col? Span
---@field col_end? Span
---@field type? Span
```

(`type` can either be `"E" | "W" | "I"` for errors, warning, and information.
If unset, `"E"` is assumed.  Currently types are unused).

Where `Span` is

```lua
---@class Span
---@field start number
---@field finish number
---@field value string | number
```

(only `filename` and `type` are strings. The rest are numbers)

To be more concrete consider this example:

```lua
local lpeg = vim.lpeg
local P, R, S, = lpeg.P, lpeg.R, lpeg.S,
local Cg, Ct, Cc, Cp = lpeg.Cg, lpeg.Ct, lpeg.Cc, lpeg.Cp

-- helper
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

require("bufix").setup {
    rules = {
        -- disable the gnu rule for whatever reason
        gnu = lpeg(false),

        -- define a new rule for the iar compiler
        -- It has errors of the form:
        -- "foo.c",3  Error[32]: Error message
        -- "foo.c",3  Warning[32]: Error message

        iar = Ct(
            '"' * Cg_span((1 - "")^1, "filename") * '"' * -- "foo.c"
            "," * Cg_span(R("09")^1 / tonumber, "line") * S(" \t")^0 * -- ,3
            (P("Warning") * Cg_span(Cc"W", "type"))^-1 -- Warning (optional)
        )
    }
}
```

Quick explanation:

- `Ct()` is to make the pattern return a table (instead of multiple values)
- `*` is for concatenating patterns
- `Cg_span` is a helper function that
    - Calls `Cp()` to capture the starting and ending positions
    - Calls `Cg()` to "tag" a pattern with a name (such as "value")
    - Passes the pattern to a function to turn into a table with keys `start`,
        `value` and `finish`.
- `R("09")^1` captures one or more digits
- `S(" \t")^0` captures optional white space.

To learn more see `:h vim.lpeg` and `:h vim.re`.

# Acknowledgment

This plugin wouldn't have been possible without inspiration from:

- Emacs
- <https://github.com/ej-shafran/compile-mode.nvim>
- <https://github.com/nvim-neorocks/nvim-best-practices>
