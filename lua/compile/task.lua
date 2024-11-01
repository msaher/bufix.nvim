local errors = require("compile.errors")

---@class Task
---@field bufname number?
---@field chan number?
local Task = {}
Task.__index = Task

---@return Task
function Task.new(bufname)
    local self = setmetatable({}, Task)
    self.bufname = bufname
    return self
end

function Task:run(cmd, opts)

    -- first buffer with name `self.bufname`
    local buf = vim.iter(vim.api.nvim_list_bufs())
        :filter(function(b) return vim.api.nvim_buf_is_loaded(b) end)
        :find(function(b)
        return vim.fs.basename(vim.api.nvim_buf_get_name(b)) == self.bufname
    end)

    if buf ~= nil then
        if self.chan ~= nil then
            local choice = vim.fn.confirm("A task process is running; kill it?", "&No\n&Yes")

            if choice == 2 then -- yes
                vim.fn.jobwait({ self.chan }, 1500)
                self.chan = nil
            else
                return
            end
        else
            -- clear buffer
            vim.api.nvim_buf_set_lines(buf, 0, -1, true, {})
        end
    else
        self.chan = nil
        buf = vim.api.nvim_create_buf(true, true)

        -- set buffer options
        vim.api.nvim_set_option_value("expandtab", false, { buf = buf })
        vim.api.nvim_set_option_value("tabstop", 8, { buf = buf })

        vim.keymap.set("n", "<CR>", function()
            local win = vim.api.nvim_get_current_win()
            local cwd = vim.fn.getcwd(win)
            local row = vim.api.nvim_win_get_cursor(win)[1] -- 1-based
            local line = vim.api.nvim_buf_get_lines(buf, row-1, row, true)[1] -- 0-based

            local data = errors.match(line)
            if data ~= nil then
                errors.enter(data, cwd)
            end
        end,
        { buffer = buf }
        )

        vim.api.nvim_buf_set_name(buf, "*Task*")
    end

    -- if a cwd is not passed, use the current window's cwd
    opts = opts or {}
    local cwd = opts.cwd or vim.fn.getcwd(vim.api.nvim_get_current_win())

    local win = vim.fn.bufwinid(buf)
    if win == -1 then
        -- TODO: make this an opt
        win = vim.api.nvim_open_win(buf, false, {
            split = "below",
            win = -1,
        })
    end

    -- change cwd of task window
    vim.api.nvim_win_call(win, function()
        vim.cmd("lcd " .. cwd)
    end)

    vim.api.nvim_buf_set_lines(buf, 0, -1, true, {
        "Running in " .. cwd,
        "Task started at " .. os.date("%a %b %e %H:%M:%S"),
        "",
        cmd,
    })
    local line_count = 4

    self.chan = vim.fn.jobstart(cmd, {
        pty = true,     -- run in a pty. Avoids lazy behvaiour and quirks
        env = {
            PAGER = "", -- disable paging. This is not interactive
        },
        cwd = cwd,
        on_stdout = function(chan, data, name)
            _ = chan
            _ = name
            if not data then
                return
            end

            -- remove "\r" from non-empty strings
            -- remove empty strings
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
                vim.api.nvim_buf_set_lines(buf, -1, -1, true, data)

                for i, line in ipairs(data) do
                    local cap = errors.match(line)
                    if cap ~= nil then
                        vim.api.nvim_buf_add_highlight(buf, -1, "Question", line_count+i-1, 0, -1)
                    end
                end

                line_count = line_count + #data
            end)
        end,
        on_exit = function(chan, exit_code, event)
            _ = event -- always "exit"

            local now = os.date("%a %b %e %H:%M:%S")
            local msg
            if exit_code == 0 then
                msg = "Task finished at " .. now
            else
                msg = "Task existed abnormally with code " .. exit_code .. " at " .. now
            end
            vim.api.nvim_buf_set_lines(self.buf, -1, -1, true, { "", msg })
            self.chan = nil
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

            return true
        end,
    })
end
