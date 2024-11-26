# Introduction

> This plugin is currently in the testing phase.

a command runner inspired by emacs' M-x compile

`doit.nvim` is a versatile task execution and navigation plugin for Neovim. It
streamlines running commands, parsing their output, and navigating through
errors or file paths directly within Neovim.

- Run commands and view their output in a dedicated, easily manageable buffer.
- (Optional) Integratation with `:terminal`.

## Installation

This plugin requires nvim >= 0.10

With lazy

```lua
{
    "msaher/doit.nvim"
    -- calling setup is optional :)
}
```

## Quickstart

Execute `:Doit run` to get prompted for a command. If the output contains paths
(try `grep -rn` or a compiler), then you'll be able to jump through
them using `:Doit next` and `:Doit prev`. You can also press `<CR>` on a path to
jump directly to it. If you'd like to rerun the last command use `:Doit rerun`.

Handy keymaps:

```lua
vim.keymap.set("n", "<leader>k", "<cmd>Doit run<CR>",  { desc = "Run command"})
vim.keymap.set("n", "]e",        "<cmd>Doit next<CR>", { desc = "Go to next error"})
vim.keymap.set("n", "[e",        "<cmd>Doit prev<CR>", { desc = "Go to prev error"})

--- or if you prefer to use the API
vim.keymap.set("n", "<leader>r", function() require("doit.task"):prompt_for_cmd() end , { desc = "Run command"})
vim.keymap.set("n", "]e",        function() require("doit.nav").goto_next()       end , { desc = "Go to next error"}))
vim.keymap.set("n", "[e",        function() require("doit.nav").goto_prev()       end , { desc = "Go to prev error"}))
```

If you want `:h :terminal` to act just like a task buffer, then add this
autocommand:

```lua
local group = vim.api.nvim_create_augroup("DoitTerm", { clear = true })
vim.api.nvim_create_autocmd("TermOpen", {
    group = group,
    callback = function(opts)
        require("doit.nav").register_buf(opts.buf) -- make it work with goto_next() and friends
    end,
    desc = "doit: auto register terminal buffer as an error buffer with the default keymaps",
})
```

# Commands

`:Doit`
: Prompts for a sub command

`:[range]Doit run [cmd]`
: If [cmd] is set, runs [cmd] in the task buffer. Otherwise, prompts for a
command to run.

If [range] is present, then the specified lines are used as stdin for [cmd]

Accepts the following command modifiers:

- `:h silent!` :  Never notify on exit. Even if the task exists with an error (non-zero exit code)
- `:h silent` : Only notify on error.
- `:h unsilent` : Always notify.
- `:h vertical`
- `:h horizontal`
- `:h aboveleft`
- `:h belowright`
- `:h topleft`
- `:h botright`

You can combine these for custom behaviour:

```
:silent! horizontal botright Doit run grep -rn TODO
```

`:Doit rerun`
: Reruns the last command.

Accepts the same command modifiers as `:Doit run`

`:Doit stop`
: Sends `SIGTERM` to the running task.

If the process doesn't terminate after a timeout, a `SIGKILL` signal is sent.
Works Like `:h jobstop`

`:Doit interrupt`
: Sends `SIGINT` to the running task.

This is Equivalent to typing ctrl-c `C-c` in a termianl.

`:Doit next`
: Go to the next error in the nav buffer

`:Doit prev`
: Go to the previous error in the nav buffer

`:Doit next-file`
: Go to the next file in the nav buffer

`:Doit prev-file`
: Go to the previous file in the nav buffer

# Configuration

Configuration is done through calling `require("doit").setup()`. It justs sets
`cfg` to the `require("doit").config` table. The default configuration is:

```lua

-- DONT COPY PASTE THIS ITS JUST THE DEFAULT CONFIG
-- Read the next section to learn more about the options
require("doit").setup({
    --- notifying when the command finishes
    ---@type "never" | "on_error" | "always"
    notify = "never",

    --- Function that returns the window number that the task buffer will be
    --- placed in.
    ---@type fun(buf: number, task: Task): number
    open_win = function(buf) return require("doit.task").default_open_win(buf) end,

    --- Name of the task buffer.
    ---@type string
    buffer_name = "*Task*",

    -- Callback that runs after the task buffer is created. Use this if you want
    -- to create custom keymaps.
    ---@type fun(task: Task, buf: number)?
    on_task_buf = nil,

    -- Callback that runs after a buffer is registered as a navigation buffer.
    -- Use this to create custom keymaps. ALL task bufers are nav buffers. nav
    -- buffers are what's responsible for the jumping logic.
    ---@type fun(buf: number)?
    on_nav_buf = nil,

    --- Callback that runs after task exits. Similar to `jobstart()`. See :h on_exit for more.
    ---@type fun(job_id: number, exit_code: number, event_type: string, buf: number, task: Task)?
    on_exit = nil,

    --- Prompts to save if there are unsaved changes. Useful to avoid compiling
    --- old code.
    ---@type boolean
    ask_about_save = true,

    --- Do not ask for confirmation before terminating a command
    ---@type boolean
    always_terminate = false,

    --- Buffer local keymaps in nav buffers. Such as <CR> to jump or <C-q> to
    --- send to qflist
    ---@type boolean
    want_navbuf_keymaps = true,

    --- Buffer local keymaps in task buffers. Such as "r" to rerun or "<C-c"> to
    --- interrupt.
    ---@type boolean
    want_task_keymaps = true,

    --- Default timestamp fromat used in task buffers. Accepts same format as
    --- :h os.date() in lua
    ---@type string
    time_format = "%a %b %e %H:%M:%S",

    --- How long to highlight the cursor after jumping. Set it to 0 to disable
    --- it.
    ---@type number in milliseconds
    locus_highlight_duration = 500,

    --- If true, use vim.ui.input() to prompt.
    ---@type boolean
    prompt_cmd_with_vim_ui = true,

})
```

If `want_task_keymaps` is true, these buffer local keymaps are set for task
buffers:

```lua
vim.keymap.set("n", "r", function() task:rerun() end, { buffer = buf })
vim.keymap.set("n", "<C-c>", function() task:interrupt() end, { buffer = buf })
```

If `want_navbuf_keymaps` is true, then these buffer local mappings are set for
nav buffers (like task buffers):

```lua
    vim.keymap.set("n", "<CR>" , require("doit.nav").goto_error_under_cursor,    { buffer = buf,  desc = "Go to error under cursor"})
    vim.keymap.set("n", "g<CR>", require("doit.nav").display_error_under_cursor, { buffer = buf,  desc = "Dispaly error under cursor"})
    vim.keymap.set("n", "gj"   , require("doit.nav").move_to_next,               { buffer = buf,  desc = "Move cursor to next error"})
    vim.keymap.set("n", "gk"   , require("doit.nav").move_to_prev,               { buffer = buf,  desc = "Move cursor to prev error"})
    vim.keymap.set("n", "]]"   , require("doit.nav").move_to_next_file,          { buffer = buf,  desc = "Move cursor to next file"})
    vim.keymap.set("n", "[["   , require("doit.nav").move_to_prev_file,          { buffer = buf,  desc = "Move cursor to prev file"})

    vim.keymap.set("n", "<C-q>", function()
        require("doit.nav").send_to_qflist()
        vim.cmd.copen()
    end,
    { buffer = buf, desc = "Send errors to qflist"})
```

where `buf` is the nav buffer.

# Task

A task object represents a process that may or may not be running. In 99% of
cases you don't have to create a task yourself because a default one was
created for you. You can access it like this:

```lua
    local task = require("doit.task")
    task:run("echo hello world")
    -- ...
    task:rerun()
```

If you'd like to run multiple tasks, then navigate to the task buffer, and
rename it using `:h :file_f`

You can create a your own task object if you really want to

```lua
    local task = require("doit.task").new()
    task:run("echo hello I made a task object")
```

Tasks do not run in a `:h :terminal`, which makes them avoid terminal reflow
issues at the cost of interactivity and colors.

If you you want a terminal buffer to turn into a nav buffer (allowing you to use `:Doit
next` and friends, then add this auto command

```lua
local group = vim.api.nvim_create_augroup("DoitTerm", { clear = true })
vim.api.nvim_create_autocmd("TermOpen", {
    group = group,
    callback = function(opts)
        require("doit.nav").register_buf(opts.buf) -- make it work with goto_next() and friends
    end,
    desc = "doit: auto register terminal buffer as an error buffer with the default keymaps",
})
```

---

`task:run({cmd}, {opts})`
: Runs {cmd} in a task buffer.

- Parameters:
    * `{cmd}`: string or list of strings. If its a string, then it runs in a `:h
      'shell'`.
    * `{opts}`: Optional parameters. They have higher priority then
      [config](#Configuration)
        + `cwd`: string. Working directory of the task. Defaults to the current
          working directory.
        + `buffer_name`: The name of the task buffer.
        + `ask_about_save`: If true, prompt to save any unsaved buffers. If `q`
          is pressed, then skip saving buffers. If `<esc>` is pressed, then
          abort running {cmd} entirely.
        + `always_terminate`. If true, don't ask before terminating a task.
        + `open_win`: Function used to open task window. Arguments:
            + `buf`: buffer number of the task
            + `task`: Task object
        + `notify`: How to notify when a task finishes. One of
            + `"never"`: Never notify when a task finishes.
            + `"on_error"`: only notify on errors.
            + `"always"`: Always notify.
        + `stdin`: string. Standard input to pass to {cmd}. If non-nil,
          `{cmd}` always runs in `:h shell`. Even if {cmd} is a list of
          strings

`task:prompt_for_cmd({opts})`
: Prompts for a command to run.
internally usees `vim.ui.input()`
if `prompt_cmd_with_vim_ui` is set in [config](#Configuration).
Takes same `{opts}` as `:h doit-task:run()`

`task:rerun({opts})`
: Reruns the last command.

Accepts same `{opts}` as `:h doit-task:run()` except:

- `cwd` is always the same as the last cwd used by the task buffer
- `stdin` is always the same as the last stdin used by the task buffer


`task:stop()`
: Like `:h doit-:Doit-stop`


`task:interrupt()`
: Like `:h doit-:Doit-interrupt`

`task:kill({signal})`
: Send `{signal}` to task using the unix
`kill` command.

# Nav

`require("doit.nav")` provides an interface that allows any buffer to act
like a `:h quickfix` list. `h doit-task` internally use this interface.
Other plugins can make use of it too. All they need to do is call
`nav.register_buf()` or `nav.set_buf()`. `:h doit-nav.set_buf()`, `:h
doit-nav.register_buf()`

Nav buffers are similar to the quickfix list. Some differnces:

- Nav buffers work on "live" buffers. like terminals or tasks. This makes them
  useful when running servers or logging commands like `tail -f`. They
  additionally can be used with interactive buffers like `:h termianl`.

- Nav buffers use `:h vim.lpeg` to parse error messages.

- Unlike the quickfix list, you don't have to mess with `:h errorformat`.

- The cursor gets highlighted when jumping through errors.

---

`nav.goto_prev()`
: Go to the previous error

`nav.goto_next_file()`
: Go to the next error

`nav.goto_prev_file()`
: Go to the prevous error

`nav.move_to_next()`
: Move cursor to next error line

`nav.move_to_prev()`
: Move cursor to previous error line

`nav.goto_error_under_cursor()`
: Go to the error under the cursor

`nav.display_error_under_cursor()`
: Visit file containg the error,
but do focus on its window

`nav.set_buf({buf})`
: Makes {buf} the current nav buffer.

functions that operate on the current nav buffer:

  - `nav.goto_error_under_cursor()`
  - `nav.display_error_under_cursor()`
  - `nav.move_to_next()`
  - `nav.move_to_prev()`
  - `nav.move_to_next_file()`
  - `nav.move_to_prev_file()`

`nav.register_buf({buf})`
: Register `{buf}` as a nav buffer

If there's no nav buffer, then sets `{buf}` as the nav buffer. Otherwise, it
only adds error highlighting and sets `b:doit_navbuf = true`. When the current nav
buffer gets deleted, `{buf}` becomes a potential candidate to be the next nav
buffer.

For example, if there are to nav buffers `A` and `B`, and `A` is the current
one. Once buffer `A` gets deleted, buffer `B` becomes the current nav buffer.

`nav.send_to_qflist({buf})`
: Parse `{buf},` and send it the quickfix list
as per the error rules. `{buf}` doesn't have
to be a nav buffer. If want to use the
built-in `:h :errorformat`, then use
`:h cbuffer` instead.

# Highlights

The following highlights are provided:

`DoitTaskSuccess`
: highlight group for when the task
finishes successfully

`DoitTaskAbnormal`
: highlight group for when task exists
abnormally

`DoitTaskSegfault`
: highlight group for when task segfaults

`DoitTaskTerminate`
: highlight group for when task terminates

`DoitFilename`
: highlight group for filename

`DoitLine`
: highlight group for line number

`DoitLineEnd`
: highlight group for ending line number

`DoitCol`
: highlight group for column number

`DoitColEnd`
: highlight group for ending column number

`DoitType`
: highlight group for error type

`DoitCurrent`
: highlight group for the sign column
arrow pointing at current error

# Rules

Errors are parsed according to "rules". There are two types of rules:

1. `:h vim.lpeg` grammars (advanced). Powerful and expressive, but might be
   overkill for simple error messages
2. `:h errorformat`. Uses vim's built-in error formats used in `:h quickfix`.

To add new rules or overwrite existing ones configure the `rules` in `.setup()`.

```lua
require("doit").setup({
    rules = {
        my_rule = vim.lpeg(<your_rule>)
        another_rule = "<or_your_errorformat>"
    }
})
```

Example using `:h errorformat`:

```lua
require("doit").setup({
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
If unset, `"E"` is assumed)

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

require("doit").setup {
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

- Emacs (duh)
- <https://github.com/ej-shafran/compile-mode.nvim>
- <https://github.com/nvim-neorocks/nvim-best-practices>
