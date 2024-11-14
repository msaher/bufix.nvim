local M = {}

M.task = require("doit.task").new() -- default task. Covers 99% of use cases

-- completion function for prompt_for_cmd()
-- credit goes to https://github.com/ej-shafran/compile-mode.nvim
vim.cmd[[
function! DoitInputComplete(ArgLead, CmdLine, CursorPos)
    let HasNoSpaces = a:CmdLine =~ '^\S\+$'
    let Results = getcompletion('!' . a:CmdLine, 'cmdline')
    let TransformedResults = map(Results, 'HasNoSpaces ? v:val : a:CmdLine[:strridx(a:CmdLine, " ") - 1] . " " . v:val')
    return TransformedResults
endfunction
]]


---@param opts RunOpts?
function M.prompt_for_cmd(opts)
    local input = vim.fn.input({
        prompt = "Command to run: ",
        default = M.task.last_cmd or "",
        completion = "customlist,DoitInputComplete",
    })

    if input ~= nil and input ~= "" then
        M.task:run(input, opts)
    end
end

