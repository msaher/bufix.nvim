local A = vim.api
local fn = vim.fn

-- @class Task
local Task = {}
Task.__index = Task

local default_config = {
    auto_start = false,
    opener = require('compile.openers').current,
    hidden = false,
    startinsert = false,
    cwd = fn.getcwd()
}

-- @param o table
-- @field string | string[]
-- @field auto_start boolean
-- @field hidden boolean
-- @field close boolean
-- @field open boolean
-- @return Task
function Task:new(o)
   local opts = vim.tbl_deep_extend('force', default_config, o)
   local task = setmetatable({}, self)
   task.opts = opts

   if opts.auto_start then
       task:start()
   end

   return task
end

-- @return number | nil
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

-- @return boolean
function Task:has_buf()
    -- return self.buf ~= nil
    return fn.bufexists(self.buf) ~= 0
end

-- @return nil
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

-- opens up a new terminal in the current window
-- its the responsiblity of the caller to ensure
-- that the intended window is currently focused.
-- @return nil
function Task:_termopen()
    A.nvim_set_current_buf(self.buf)
    vim.opt_local.modified = false
    self.job = fn.termopen(self.opts.cmd, {
        detach = false,
        shell = true,
        cwd = self.opts.cwd,
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
                local win_curr = A.nvim_get_current_win()
                if self:get_win() == nil then
                    local win = self.opts.opener.open()
                    A.nvim_win_set_buf(win, self.buf)
                    if not self.opts.opener.focus then
                        A.nvim_set_current_win(win_curr)
                    end
                end

            end


        end,
    })

end

-- @return nil
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

    local name
    if type(self.opts.cmd) == 'table' then
        name = table.concat(self.opts.cmd, " ")
    else
        name = self.opts.cmd
    end

    A.nvim_buf_set_name(self.buf, '*task*: ' .. name)

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

-- Starts the task
-- @return nil
function Task:start()
    self:_rest()
    self:_execute()
end

-- restart is an alias for start
Task.restart = Task.start


-- Kills the task
-- @return nil
function Task:die()
    self:_rest()

    if self:has_buf() then
        A.nvim_buf_delete(self.buf, {force = true})
        self.buf = nil
    end
end

return Task
