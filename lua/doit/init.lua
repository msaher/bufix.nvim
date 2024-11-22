local M = {}

---@class DoitFullConfig
local default_config = {
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
    prompt_cmd_with_vim_ui = false,

    --- Extra error rules
    ---@type table
    rules = {},

}

---@class DoitConfig
---@field notify? "never" | "on_error" | "always"
---@field open_win? fun(buf: number, task: Task): number
---@field buffer_name? string
---@field always_terminate? boolean
---@field on_task_buf? fun(buf: number, task: Task)
---@field on_exit? fun(job_id: number, exit_code: number, event_type, buf: number, task: Task)
---@field ask_about_save? boolean
---@field want_task_keymaps? boolean
---@field want_nav_keymaps? boolean
---@field time_format string?
---@field locus_highlight_duration? number
---@field prompt_cmd_with_vim_ui? boolean
---@field rules? table

---@type DoitFullConfig
M.config = default_config

---@param cfg DoitConfig?
function M.setup(cfg)
    ---@diagnostic disable-next-line assign-type-mismatch
    if cfg ~= nil then
        M.config = vim.tbl_deep_extend('force', cfg, M.config)
    end
end

return M
