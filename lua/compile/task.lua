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

function Task:stop()

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
    A.nvim_set_current_buf(self:get_buf())
    vim.opt_local.modified = false
    self.job = fn.termopen(self.opts.cmd, {
        detach = false,
        shell = true,
        cwd = self.opts.cwd or fn.getcwd(),
        stderr_buffered = true,
        stdout_buffered = true,

        on_exit = function(job_id, exit_code, event)
            self.job = nil

            if self.opts.on_exit ~= nil then
                self.opts.on_exit(self, job_id, exit_code, event)
            end

            if self.opts.close then
                A.nvim_buf_delete(self.buf, {})

            elseif self.opts.open then
                self:open()
            end


        end,
    })

    self:set_buf_name()
end

function Task:_execute()
    if not self:has_buf() then
        self.buf = A.nvim_create_buf(true, true)
        -- set file type
        A.nvim_set_option_value('filetype', 'task', { buf = self:get_buf() })
    end

    local win = self:get_win()
    local win_curr = A.nvim_get_current_win()

    if win == nil then
        win = self.opts.opener.open()
        A.nvim_win_set_buf(win, self:get_buf())
    end

    local buf_curr = A.nvim_get_current_buf()
    self:_termopen()

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
    self:stop()
    self:_execute()
end

--- Restarts the task. Does not change the currently focused window
function Task:restart()
    if not self:has_buf() then
        self:_execute()
        return
    end

    -- make sure buffer is not lost on_exit
    local close = self.opts.close
    self.opts.close = false
    self:stop()
    self.opts.close = close

    local win_curr = A.nvim_get_current_win()
    if self:get_win() == nil then
        self:open()
    end

    A.nvim_set_current_win(self:get_win())
    self:_termopen()
    A.nvim_set_current_win(win_curr)
end

---Kills the task
function Task:die()
    self:stop()

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
        A.nvim_buf_set_name(buf, self:get_name())
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
    local win_curr = A.nvim_get_current_win()
    local win_list = A.nvim_tabpage_list_wins(0)

    local is_last_window = (#win_list == 1 and win_curr == win)

    if not is_last_window then
        A.nvim_win_close(win, true)
    end

end

function Task:toggle()
    if self:has_win() then
        self:close()
    else
        self:open()
    end
end

-- TODO: support custom efm
function Task:to_qflist()
    local buf = self:get_buf()
    if buf == nil then
        error("Task has no buffer assocaited with it " .. self:get_name())
    end

    -- terminal buffers usually have extra empty lines.
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, true)
    lines = vim.tbl_filter(function(line)
        return line ~= ""
    end, lines)

    U.trim_trailing_strings(lines)

    local last_line = lines[#lines]
    -- remove [process exit] message, if it exists
    if U.startswith(last_line, "[Process") then
        lines[#lines] = nil
    end

    vim.fn.setqflist({}, 'r', {
        lines = lines,
    })

end


return Task
