local A = vim.api
local fn = vim.fn
local U = require("compile.utils")

---@class Task
---@field opts table
local Task = {}
Task.__index = Task

local default_config = {
    auto_start = true,
    opener = require('compile.openers').split,
    hidden = false,
    startinsert = false,
    cwd = nil,
}

--- Creates a new task
---@param o table
---@return Task
function Task:new(o)
   local opts = vim.tbl_deep_extend('force', default_config, o)
   local task = setmetatable({}, self)
   task.opts = opts

   if opts.auto_start then
       task:start()
   end

   return task
end

--- Get the window id, if any
---@return number | nil
function Task:get_win()
    if self.buf == nil  then
        return nil
    end

    local wid = fn.bufwinid(self.buf)
    if wid == -1 then
        wid = nil
    end

    return wid
end

--- Check if the task has a buffer associated with it
---@return boolean
function Task:has_buf()
    -- return self.buf ~= nil
    return fn.bufexists(self.buf) ~= 0
end

function Task:has_win()
    return self:get_win() ~= nil
end

--- Returns the buffer id associated with the task
---@return number | nil
function Task:get_buf()
    if fn.bufexists(self.buf) ~= 0 then
        return self.buf
    else
        return nil
    end
end

function Task:_rest()

    if self.job ~= nil then
        fn.jobstop(self.job)
        self.job = nil

        -- Give time for the '[process existed 0] message to show up.
        -- Otherwise, they'll show up in the wrong place
        -- This is only needed for jobs that haven't finished running
        vim.cmd.sleep('15ms')
    end

end

--- Opens up a new terminal in the current window its the responsiblity of the
--caller to ensure that the intended window is currently focused.
function Task:_termopen()
    A.nvim_set_current_buf(self.buf)
    vim.opt_local.modified = false
    self.job = fn.termopen(self.opts.cmd, {
        detach = false,
        shell = true,
        cwd = self.opts.cwd or fn.getcwd(),
        stderr_buffered = true,
        stdout_buffered = true,

        on_exit = function(job_id, exit_code, event)
            if self.opts.on_exit ~= nil then
                self.opts.on_exit(self, job_id, exit_code, event)
            end

            if self.opts.close then
                A.nvim_buf_delete(self.buf, {})

            -- TODO: clean this up
            elseif self.opts.open then
                self:open()
            end


        end,
    })

end

function Task:_execute()
    if not self:has_buf() then
        self.buf = A.nvim_create_buf(true, true)
        -- set file type
        A.nvim_set_option_value('filetype', 'task', { buf = self.buf })
    end

    local win = self:get_win()
    local win_curr = A.nvim_get_current_win()

    if win == nil then
        win = self.opts.opener.open()
        A.nvim_win_set_buf(win, self.buf)
    end

    local buf_curr = A.nvim_get_current_buf()
    self:_termopen()

    A.nvim_buf_set_name(self.buf, self:get_name())
    self:set_buf_name()

    -- go back to original buffer
    A.nvim_set_current_buf(buf_curr)

    if not self.opts.opener.focus then
        A.nvim_set_current_win(win_curr) -- go back to original window

    elseif self.opts.startinsert then
        vim.cmd.startinsert()
    end

    if self.opts.hidden then
        A.nvim_win_close(win, true)
    end

end

--- Starts the task. If the task is already running, then it will be re-started
function Task:start()
    self:_rest()
    self:_execute()
end

--- An alias for task:start()
function Task:restart()
    self:start()
end

---Kills the task
function Task:die()
    self:_rest()

    if self:has_buf() then
        A.nvim_buf_delete(self.buf, {force = true})
        self.buf = nil
    end
end

--- Returns the name of the task
---@return string
function Task:get_name()
    local name = self.opts.name
    if name == nil then
        name = "*task*: " .. self:get_cmd()
    end

    return name
end

--- Sets the name of the task
function Task:set_name(name)
    self.opts.name = name
    self:set_buf_name()
end

function Task:set_buf_name()
    local buf = self:get_buf()
    if buf ~= nil then
        A.nvim_buf_set_name(self.buf, self:get_name())
    end
end

--- Returns the command as a string
---@return string
function Task:get_cmd()
    local cmd

    if type(self.opts.cmd) == 'table' then
        cmd = table.concat(self.opts.cmd, " ")
    else
        cmd = self.opts.cmd
    end

    return cmd
end

function Task:open()
    -- TODO: clean this up
    if self:get_buf() == nil then
        self:start()
    end

    local win_curr = A.nvim_get_current_win()
    if self:get_win() == nil then
        local win = self.opts.opener.open()
        A.nvim_win_set_buf(win, self:get_buf())
        if not self.opts.opener.focus then
            A.nvim_set_current_win(win_curr)
        end
    end
end

--- Closes the window the task resdies in
function Task:close()
    local win = self:get_win()
    if win ~= nil then
        A.nvim_win_close(win, {})
    end

end

function Task:toggle()
    if self:has_win() then
        self:close()
    else
        self:open()
    end
end

return Task
