-- completion function
-- credit goes to https://github.com/ej-shafran/compile-mode.nvim
vim.cmd[[
function! DoitInputComplete(ArgLead, CmdLine, CursorPos)
    let HasNoSpaces = a:CmdLine =~ '^\S\+$'
    let Results = getcompletion('!' . a:CmdLine, 'cmdline')
    let TransformedResults = map(Results, 'HasNoSpaces ? v:val : a:CmdLine[:strridx(a:CmdLine, " ") - 1] . " " . v:val')
    return TransformedResults
endfunction
]]

local M = {}

---@type Task?
local the_task = nil

---@return Task
local function get_task()
    if the_task == nil then
        the_task = require("doit.task").new()
    end

    return the_task
end

---@param cmd string
---@param opts RunOpts
function M.run(cmd, opts)
    if opts.bufname == nil then
        opts.bufname = vim.tbl_get(vim.g, "doit", "bufname")
    end

    get_task():run(cmd, opts)
end

function M.rerun()
    get_task():rerun()
end

function M.prompt_for_cmd()
    local input = vim.fn.input({
        prompt = "Command to run: ",
        default = get_task().last_cmd or "",
        completion = "customlist,DoitInputComplete",
    })

    if input ~= nil and input ~= "" then
        get_task():run(input, {bufname = "*" .. input .. "*"})
    end

end

---termopen() wrapper that sets the opened terminal buffer
---as the current error buffer
---@param cmd string | string[] same as :h termopen
---@param opts table? same as :h termopen
---@param enable_default_keymaps? boolean
function M.termopen(cmd, opts, enable_default_keymaps)
    opts = opts or {}
    local buf = vim.api.nvim_get_current_buf()
    local errors = require("doit.errors")

    local o = {
        on_exit = function(chan, data, event)
            if opts.on_exit then
                opts.on_exit(chan, data, event)
            end

            local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, true)
            for idx, line in ipairs(lines) do
                errors.highlight_line(line, idx-1, buf)
            end
        end,
    }

    o = vim.tbl_extend("keep", o, opts)

    vim.fn.termopen(cmd, o)

    errors.set_buf(buf)

    if enable_default_keymaps == nil then
        enable_default_keymaps = true
    end
    if enable_default_keymaps then
        errors.set_default_keymaps(buf)
    end

end

return M
