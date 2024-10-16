---@class Task
---@field buf number?
---@field chan number?
local Task = {}
Task.__index = Task

---@return Task
function Task.new()
    local self = setmetatable({}, Task)
    return self
end

function Task:run(cmd, opts)
    -- TODO: make cmd a table if shell is false

    if self.buf ~= nil then
        if self.chan ~= nil then
            -- TODO: use vim.ui.input()
            vim.print("Something is running... ignoring you")
        else
            -- clear buffer
            vim.api.nvim_buf_set_lines(self.buf, 0, -1, true, {})
        end
    else
        self.buf = vim.api.nvim_create_buf(true, true)
        vim.api.nvim_buf_set_name(self.buf, "*Task*")
    end

    local has_no_win = vim.fn.bufwinid(self.buf) == -1
    if has_no_win then
        vim.api.nvim_open_win(self.buf, false, {
            split = "right"
        })
    end

    opts = opts or {}
    self.cwd = opts.cwd or self.cwd or vim.fn.getcwd()

    vim.api.nvim_buf_set_lines(self.buf, 0, -1, true, {
        "Running in " .. self.cwd,
        "Task started at " .. os.date("%a %b %e %H:%M:%S"),
        "",
        cmd,
    })

    self.chan = vim.fn.jobstart(cmd, {
        pty = true,     -- run in a pty. Avoids lazy behvaiour
        env = {
            PAGER = "", -- disable paging. This is not interactive
        },
        cwd = self.cwd,
        on_stdout = function(chan, data, name)
            _ = chan
            _ = name
            if not data then
                return
            end

            -- remove "\r" from non-empty strings
            -- remove empty strings and...
            -- Empty strings usually appear at the end {"foo\r", ""}
            local i = 1
            while i <= #data do
                if data[i]:sub(-1) == "\r" then
                    data[i] = data[i]:sub(1, -2)
                    i = i + 1
                elseif data[i] == "" then
                    table.remove(data, i)
                else
                    i = i + 1
                end
            end

            vim.schedule(function()
                vim.api.nvim_buf_set_lines(self.buf, -1, -1, true, data)
            end)
        end,
        on_exit = function(chan, exit_code, event)
            _ = event -- always "exit"
            self.chan = nil
            local now = os.date("%a %b %e %H:%M:%S")
            local msg
            if exit_code == 0 then
                msg = "Task finished at " .. now
            else
                msg ="Task existed abnormally with code " .. exit_code .. " at" .. now
            end

            vim.api.nvim_buf_set_lines(self.buf, -1, -1, true, { msg })
        end
    })

    vim.api.nvim_create_autocmd({ "BufDelete" }, {
        buffer = self.buf,
        callback = function(data)
            _ = data
            if self.chan ~= nil then
                vim.fn.jobstop(self.chan)
            end
            self.chan = nil
            self.buf = nil
        end,
    })
end
