local errors = require("doit.errors")

-- pattern to strip ansi escape sequences and carriage carriage-return
local strip_ansii_cr = "[\27\155\r][]?[()#;?%d]*[A-PRZcf-ntqry=><~]?"

--- TODO: might want to put this somewhere else
---@param buf number
local function open_win_sensibly(buf)
    local width = vim.api.nvim_win_get_width(0)
    local height = vim.api.nvim_win_get_height(0)

    local split
    if height >= 80 then
        split = "below"
    elseif width >= 160 then
        split = "right"
    elseif #vim.api.nvim_list_wins() > 1 then
        -- reuse last window if theres no space and there are other windows
        -- BUG: if the last window has been closed, then wincmd("p") does
        -- nothing
        vim.cmd.wincmd("p")
        local win = vim.api.nvim_get_current_win()
        vim.cmd.wincmd("p")
        return win
    else
        split = "below"
    end

    return vim.api.nvim_open_win(buf, false, {
        split = split,
        win = 0,
    })
end

---@param first_item string
---@param data string[]
---@param line_count number
---@return string
---@return number
local function pty_append_to_buf(buf, first_item, data, line_count)
    -- as per :h channel-lines, the first and last items may be partial when
    -- jobstart is passed the pty = true option.
    -- We set the first item as the first element and return the last item
    data[1] = first_item .. data[1]
    first_item = data[#data] -- next first item
    data[#data] = nil

    -- strip ansii sequences and remove \r character
    data = vim.tbl_map(function(line)
        return select(1, string.gsub(line, strip_ansii_cr, ""))
    end, data)

    vim.schedule(function()
        vim.api.nvim_buf_set_lines(buf, -1, -1, true, data)

        -- highlight captures
        for i, line in ipairs(data) do
            errors.highlight_line(line, line_count + i - 1)
        end
    end)

    return first_item, #data
end

---@class Task
---@field bufname string?
---@field chan number?
---@field last_cmd (string | string[])?
---@field last_cwd string?
---@field last_bufname string?
---@field enable_default_keymaps boolean?
---@field on_buf_create fun(buf: number, task: Task)?
local Task = {}
Task.__index = Task

---@param opts? { enable_default_keymaps: boolean?, on_buf_create: fun(buf: number, task: Task)? }
---@return Task
function Task.new(opts)
    local self = setmetatable(opts or {}, Task)
    return self
end

---Creates a buffer ready for receiving pty job stdout.
---@param task Task
---@return number
local function create_task_buf(task)
    local buf = vim.api.nvim_create_buf(true, true)

    -- set buffer options
    -- breaks otherwise because programs expect tab to be a certain width
    vim.api.nvim_set_option_value("expandtab", false, { buf = buf })
    vim.api.nvim_set_option_value("tabstop", 8, { buf = buf })

    vim.api.nvim_set_option_value("filetype", "doit", { buf = buf})

    local enable = task.enable_default_keymaps or vim.tbl_get(vim.g, "doit", "enable_default_keymaps")
    if enable == nil then
        enable = true
    end
    if enable then
        errors.set_default_keymaps(buf)
        vim.keymap.set("n", "r", function() task:rerun() end, { buffer = buf })
    end

    return buf
end

---@param bufname string
---@return number?
local function get_buf_by_name(bufname)
    local buf = vim.iter(vim.api.nvim_list_bufs())
        :filter(function(b) return vim.api.nvim_buf_is_loaded(b) end)
        :find(function(b) return vim.fs.basename(vim.api.nvim_buf_get_name(b)) == bufname end)

    return buf
end

---@class RunOpts
---@field cwd string?
---@field bufname string?
---@field notify ("never" | "on_error" | "always")?
---@field open_win fun(buf: number, task: Task)?

function Task:rerun()
    if self.last_cmd ~= nil then
        self:run(self.last_cmd, { cwd = self.last_cwd })
    end
end

---@param cmd string | string[]
---@param buf number
---@param cwd string
---@param notify ("never" | "on_error" | "always")
function Task:_jobstart(cmd, buf, cwd, notify)

    vim.api.nvim_buf_set_lines(buf, 0, -1, true, {
        "Running in " .. cwd,
        "Task started at " .. os.date("%a %b %e %H:%M:%S"),
        "",
        cmd,
    })
    local line_count = 4
    local first_item = ""

    self.chan = vim.fn.jobstart(cmd, {
        pty = true,        -- run in a pty. Avoids lazy behvaiour and quirks
        env = {
            PAGER = "",    -- disable paging. This is not interactive
            TERM = "dumb", -- tells programs to avoid actual terminal behvaiour. avoids stuff like colors
        },
        cwd = cwd,
        stdout_buffered = false, -- we'll buffer stdout ourselves
        on_stdout = function(_, data)
            local added
            first_item, added = pty_append_to_buf(buf, first_item, data, line_count)
            line_count = line_count + added
        end,

        on_exit = function(_, exit_code)
            local now = os.date("%a %b %e %H:%M:%S")
            local msg

            if exit_code == 0 then
                msg = "Task finished"
            else
                msg = "Task existed abnormally with code " .. exit_code
            end

            if notify == "always" then
                vim.notify(msg, (exit_code == 0 and vim.log.levels.INFO) or vim.log.levels.ERROR)
            elseif notify == "on_error" and exit_code ~= 0 then
                vim.notify(msg, vim.log.levels.ERROR)
            end

            msg = msg .. " at " .. now
            vim.api.nvim_buf_set_lines(buf, -1, -1, true, { "", msg })

            self.chan = nil
        end
    })

    vim.api.nvim_create_autocmd({ "BufDelete" }, {
        buffer = buf,
        callback = function(_)
            if self.chan ~= nil then
                vim.fn.jobstop(self.chan)
            end
            self.chan = nil

        end,
        desc = "doit: force stop task",
        once = true,
    })


end

---@param cmd string | string[]
---@param opts RunOpts?
function Task:run(cmd, opts)
    opts = opts or {}
    local bufname = opts.bufname or self.last_bufname or "*Task*"

    local buf = nil
    if self.last_bufname ~= nil then
        buf = get_buf_by_name(self.last_bufname)
    end

    if buf == nil then
        self.chan = nil
        buf = create_task_buf(self)
        if self.on_buf_create then
            self.on_buf_create(buf, self)
        end
    elseif self.chan == nil then
        vim.api.nvim_buf_set_lines(buf, 0, -1, true, {}) -- clear buffer
    else
        local choice = vim.fn.confirm("A task process is running; kill it?", "&No\n&Yes")
        if choice ~= 2 then -- if not yes
            return
        end

        vim.fn.jobwait({ self.chan }, 1500)
        self.chan = nil
    end

    vim.api.nvim_buf_set_name(buf, bufname) -- update name

    -- if a cwd is not passed, use the current window's cwd
    local cwd = opts.cwd or vim.fn.getcwd(0)

    local win = vim.fn.bufwinid(buf)
    if win == -1 then
        local open_win = opts.open_win or open_win_sensibly
        win = open_win(buf)
        vim.api.nvim_win_set_buf(win, buf)

        vim.api.nvim_set_option_value("number", false, { win = win })
    end

    -- change cwd of task window
    vim.api.nvim_win_call(win, function()
        vim.cmd("lcd " .. cwd)
    end)

    local notify = opts.notify or vim.tbl_get(vim.g, "doit", "notify") or "never"
    self:_jobstart(cmd, buf, cwd, notify)

    -- save last_cmd
    self.last_cmd = cmd
    self.last_cwd = cwd
    self.last_bufname = bufname

    -- set buf as error buffer
    errors.set_buf(buf)
end

return Task
