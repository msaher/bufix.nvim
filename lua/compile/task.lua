---@class Task
---@field buf number?
local Task = {}
Task.__index = Task

---@return Task
function Task.new(opts)
    local opts = opts or {}
    local self = setmetatable({}, Task)
    self.cwd = opts.cwd or vim.fn.getcwd()

    return self
end

function Task:run(cmd)
    -- TODO: make cmd a table if shell is false

    self.buf = vim.api.nvim_create_buf(true, true)
    vim.api.nvim_open_win(self.buf, false, {
        split = 'right'
    })

    vim.api.nvim_buf_set_lines(self.buf, 0, -1, true, {
        "Running in " .. self.cwd,
        "Task started at " .. os.date("%a %b %e %H:%M:%S"),
        "",
        cmd,
    })

    local chan = vim.fn.jobstart(cmd, {
        pty = true,     -- run in a pty. Avoids lazy behvaiour
        env = {
            PAGER = "", -- disable paging. This is not interactive
        },
        cwd = self.cwd,
        on_stdout = function(chan, data, name)
            _ = chan
            _ = name
            if data then
                vim.schedule(function()
                    data = string.gsub(data[1], "\r", "")
                    vim.api.nvim_buf_set_lines(self.buf, -1, -1, true, { data })
                end)
            end
        end,
        on_exit = function(chan, exit_code, event)
            _ = event -- always "exit"
            local now = os.date("%a %b %e %H:%M:%S")
            local msg
            if exit_code == 0 then
                msg = "Task finished at " .. now
            else
                msg ="Task existed abnormally with code " .. exit_code " at" .. now
            end

            vim.api.nvim_buf_set_lines(self.buf, -1, -1, true, { msg })
        end
    })

    vim.api.nvim_create_autocmd({ "BufDelete" }, {
        buffer = self.buf,
        callback = function()
            vim.fn.jobstop(chan)
            self.buf = nil
        end,
    })
end
