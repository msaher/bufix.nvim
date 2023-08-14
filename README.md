# Introduction

This plugin aims to provide an interface similar to that of emacs's `M-x compile`.

It's currently WIP, but it's pretty usable at it's currents state. Here's how I use it

```lua
local Compile = require('compile.compile')

local function on_exit(compile, job_id, exit_code, event)
    vim.cmd.cgetbuffer(compile.buf)
end

local c = Compile:new({cmd = {'ls'}, on_exit = on_exit})

vim.api.nvim_create_user_command('Compile', function(data)
    if #data.fargs ~= 0 then
        c.cmd = data.fargs
    end
    c:start()
end, {nargs = '*', complete = 'file'})

vim.keymap.set('n', '<leader>c', function()
    local cmd_name = table.concat(c.cmd, ' ')
    vim.api.nvim_feedkeys(':Compile ' ..  cmd_name .. ' ', 'n', true)
end)
```
