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

