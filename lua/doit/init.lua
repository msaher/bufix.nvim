local M = {}

---@class DoitFullConfig
local default_config = {
    ---@type "never" | "on_error" | "always"
    notify = "never",

    ---@type fun(buf: number, task: Task): number
    open_win = function(buf) return require("doit.task").default_open_win(buf) end,

    ---TODO: maybe make this a function
    ---@type string
    buffer_name = "*Task*",

    ---@type boolean
    kill_running = false,

    ---@type fun(task: Task, buf: number)
    on_task_buf = function(task, buf)
        vim.keymap.set("n", "r", function() task:rerun() end, { buffer = buf })
    end,

    ---@type fun(job_id: number, exit_code: number, event_type: string, buf: number, task: Task)?
    on_exit = nil,

    ---@type boolean
    ask_about_save = true,

    ---@type boolean
    want_error_keymaps = true,

    ---@type number in milliseconds
    locus_highlight_duration = 500,

    ---@type boolean
    prompt_cmd_with_vim_ui = true,

    ---@type table
    rules = {},

}

---@class DoitConfig
---@field notify? "never" | "on_error" | "always"
---@field open_win? fun(buf: number, task: Task): number
---@field buffer_name? string
---@field kill_running? boolean
---@field on_task_buf? fun(buf: number, task: Task)
---@field ask_about_save? boolean
---@field locus_highlight_duration? number
---@field prompt_cmd_with_vim_ui? boolean
---@field rules? table
---@field on_exit? fun(job_id: number, exit_code: number, event_type, buf: number, task: Task)

---@type DoitFullConfig
M.config = default_config

---@param cfg DoitConfig
function M.setup(cfg)
    ---@diagnostic disable-next-line assign-type-mismatch
    M.config = vim.tbl_deep_extend('force', cfg, default_config)
end

return M
