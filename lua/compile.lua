local A = vim.api
local fn = vim.fn
local M = {}

Compile = {}
Compile.__index = Compile

local default_config = {
    job_opts = {
    }
}

function Compile:new(o)
   local obj = vim.tbl_deep_extend('force', default_config, o)
   return setmetatable(obj, self)
end

function Compile:has_buf()
    return self.buf ~= nil
end

function Compile:get_win()
    if self.buf == nil  then
        return nil
    end

    local wid = fn.bufwinid(self.buf)
    if wid == -1 then
        wid = nil
    end

    return wid
end

function Compile:_has_buf()
    -- return self.buf ~= nil
    return fn.bufexists(self.buf) ~= 0
end

function Compile:_rest()

    if self.job ~= nil then
        fn.jobstop(self.job)
        self.job = nil
    end

    if self:_has_buf() then
        A.nvim_buf_delete(self.buf, {force = true})
    end

end

function Compile:_execute()
    if not self:_has_buf() then
        self.buf = A.nvim_create_buf(true, true)
    end

    -- TODO: make the window opening function dynamic
    local win = self:get_win()
    local win_curr = A.nvim_get_current_win()
    if win == nil then
        vim.cmd.split()
        vim.cmd.wincmd('J')
        win = A.nvim_get_current_win()
    end

    A.nvim_win_set_buf(win, self.buf)

    local buf_curr = A.nvim_get_current_buf()
    A.nvim_set_current_buf(self.buf)
    vim.opt_local.modified = false
    self.job = fn.termopen(self.cmd, {
        detach = false,
        cwd = fn.getcwd(),
        stderr_buffered = true,
        stdout_buffered = true,
    })

    A.nvim_buf_set_name(self.buf, '*compile*: ' .. table.concat(self.cmd, " "))

    -- go back
    A.nvim_set_current_buf(buf_curr)
    A.nvim_set_current_win(win_curr)

end

function Compile:start()
    self:_rest()
    self:_execute()
end

return Compile
