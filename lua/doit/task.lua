-- pattern to strip ansi escape sequences and carriage carriage-return
local strip_ansii_cr = "[\27\155\r][]?[()#;?%d]*[A-PRZcf-ntqry=><~]?"
-- local strip_ansii_cr = "[\27\155][]?[()#;?%d]*[A-PRZcf-ntqry=><~]?"

local SIGFAULT = 139
local SIGINT = 130
local SIGTERM = 143


-- BUG: probably doesn't work the same way on windows
local exit_messages = {
    [0] = "Task finished",
    -- HACK: a program may exit with 139 but not necessarily segfault.
    [SIGFAULT] = "Task segmentation fault (core dumped)",
    [SIGINT] = "Task interrupt",
    [SIGTERM] = "Task terminated",
}

---@param last_item string
---@param data string[]
---@return string
---@return number
local function pty_append_to_buf(buf, last_item, data)
    -- EOF is when data == {" "}. See :h channel-lines
    -- If we receive EOF then there's nothing to do
    local eof = (#data == 1) and (data[1] == "")
    if eof then
        return "", #data
    end

    -- as per :h channel-lines, the first and last items may be partial when
    -- jobstart is passed the pty = true option.
    -- We set the first item as the first element and return the last item
    data[1] = last_item .. data[1]
    if #data > 1 then
        last_item = data[#data] -- next first item
        data[#data] = nil
    else
        last_item = ""
    end

    -- strip ansii sequences and remove \r character
    data = vim.tbl_map(function(line)
        line = select(1, string.gsub(line, strip_ansii_cr, ""))
        return line
    end, data)

    vim.schedule(function()
        vim.api.nvim_buf_set_lines(buf, -1, -1, true, data)
    end)

    return last_item, #data
end

---@return boolean true if user exited with esc
local function save_some_buffers()
    local buffers = vim.iter(vim.api.nvim_list_bufs())
        :filter(function(b)
            return
                vim.api.nvim_buf_is_loaded(b)
                and vim.api.nvim_get_option_value('modified', { buf = b })
                and vim.api.nvim_buf_get_name(b) ~= ""
                and vim.api.nvim_get_option_value('buflisted', { buf = b })
        end)
        :totable()

    for _, bufnum in ipairs(buffers) do
        local buffer_name = vim.api.nvim_buf_get_name(bufnum):gsub("^" .. vim.env.HOME, "~")
        local ans = vim.fn.confirm("Save changes to " .. buffer_name .. "?", "&Yes\n&No\n&Quit")

        if ans == 1 then     -- yes
			vim.cmd.bufdo { args = { "write" }, range = { bufnum }, mods = { silent = true } }
        -- elseif ans == 2 then -- no
        --     continue
        elseif ans == 3 then -- quit (skip all buffers)
			break
        elseif ans == 0 then -- exit
            return true
		end

    end

    return false
end

---@class Task
---@field chan number?
---@field last_cmd (string | string[])?
---@field last_cwd string?
---@field last_buffer_name string?
---@field on_task_buf fun(task: Task, buf: number)?
---@field last_stdin string?
local Task = {}
Task.__index = Task

---@return Task
function Task.new()
    local self = setmetatable({}, Task)
    return self
end

---@param buf number
---@return number
function Task.default_open_win(buf)
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
        ---@cast win number
        return win
    else
        split = "below"
    end

    ---@diagnostic disable-next-line return-type-mismatch
    return vim.api.nvim_open_win(buf, false, {
        split = split,
        win = 0,
    })
end

---@param win number
local function matchadd(win)
    vim.api.nvim_win_call(win, function()
        vim.fn.matchadd("DoitTaskSuccess", [[Task \zsfinished\ze]])

        vim.fn.matchadd("DoitTaskAbnormal", [[Task exited \zsabnormally\ze with code \d\+]])
        vim.fn.matchadd("DoitTaskAbnormal", [[Task exited abnormally with code \zs\d\+\ze]])

        vim.fn.matchadd("DoitTaskSegfault", [[Task \zssegmentation fault\ze (core dumped) at]])

        vim.fn.matchadd("DoitTaskTerminate", [[Task \zsterminated\ze at]])

        vim.fn.matchadd("DoitTaskInterrupt", [[Task \zsinterrupt\ze at]])
    end)
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

    -- set buf as error buffer
    ---@cast buf number
    require("doit.nav").set_buf(buf)

    local config = require("doit").config
    if config.want_task_keymaps then
        vim.keymap.set("n", "r", function() task:rerun() end, { buffer = buf, desc = "Rerun task" })
        vim.keymap.set("n", "<C-c>", function() task:interrupt() end, { buffer = buf, desc = "Interrupt task"})
    end

    local on_buf = task.on_task_buf or config.on_task_buf
    if on_buf ~= nil then
        on_buf(task, buf)
    end

    return buf
end

---@param buffer_name string
---@return number?
local function get_buf_by_name(buffer_name)
    local buf = vim.iter(vim.api.nvim_list_bufs())
        :filter(function(b) return vim.api.nvim_buf_is_loaded(b) end)
        :find(function(b) return vim.fs.basename(vim.api.nvim_buf_get_name(b)) == buffer_name end)

    return buf
end

---@param cmd string | string[]
---@param buf number
---@param cwd string
---@param notify ("never" | "on_error" | "always")
---@param stdin string?
---@param on_exit fun(job_id: number, exit_code: number, event_type, buf: number, task: Task)?
function Task:_jobstart(cmd, buf, cwd, notify, stdin, on_exit)
    local time_format = require("doit").config.time_format

    local modeline = "vim: filetype=doit:path+=" .. cwd:gsub("^" .. vim.env.HOME, "~")
    vim.api.nvim_buf_set_lines(buf, 0, -1, true, {
        modeline,
        "Task started at " .. os.date(time_format),
        "",
        cmd,
    })
    local line_count = 4
    local last_item = ""

    if stdin then
        -- NOTE: always run in shell in stdin is set
        -- If we really want to send stdin to nonshell cmds
        -- we'll have to use chansend() and chanclose() after calling
        -- jobstart()
        if type(cmd) == "table" then
            cmd = table.concat(cmd, " ")
        end

        cmd = cmd .. "<<EOF\n" .. stdin .. "\nEOF"
    end

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
            last_item, added = pty_append_to_buf(buf, last_item, data)
            line_count = line_count + added
        end,

        on_exit = function(chan, exit_code, event_type)
            local now = os.date(time_format)

            local msg = exit_messages[exit_code]
            if not msg then
                msg = "Task exited abnormally with code " .. exit_code
            end

            if notify == "always" then
                vim.notify(msg, (exit_code == 0 and vim.log.levels.INFO) or vim.log.levels.ERROR)
            elseif notify == "on_error" and exit_code ~= 0 then
                vim.notify(msg, vim.log.levels.ERROR)
            end

            msg = msg .. " at " .. now
            vim.api.nvim_buf_set_lines(buf, -1, -1, true, { "", msg })

            self.chan = nil

            on_exit = on_exit or require("doit").config.on_exit
            if on_exit then
                on_exit(chan, exit_code, event_type, buf, self)
            end

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

---@class RunOpts
---@field cwd string?
---@field buffer_name string?
---@field always_terminate boolean?
---@field open_win (fun(buf: number, task: Task): number)?
---@field notify ("never" | "on_error" | "always")?
---@field ask_about_save boolean?
---@field stdin string?

---@param cmd string | string[]
---@param opts RunOpts?
function Task:run(cmd, opts)
    opts = opts or {}
    local config = require("doit").config

    if opts.ask_about_save or config.ask_about_save then
        local exit = save_some_buffers()
        if exit then
            return
        end
    end

    local buffer_name = opts.buffer_name or self.last_buffer_name or config.buffer_name

    local buf = nil
    if self.last_buffer_name ~= nil then
        buf = get_buf_by_name(self.last_buffer_name)
    end

    if buf == nil then
        self.chan = nil
        buf = create_task_buf(self)
    elseif self.chan == nil then
        vim.api.nvim_buf_set_lines(buf, 0, -1, true, {}) -- clear buffer
    else
        local terminate = opts.always_terminate or config.always_terminate
        if not terminate then
            local choice = vim.fn.confirm("A task process is running; kill it?", "&No\n&Yes")
            if choice ~= 2 then -- if not yes
                return
            end
        end

        vim.fn.jobwait({ self.chan }, 1000)
        self.chan = nil
    end

    vim.api.nvim_buf_set_name(buf, buffer_name) -- update name

    -- if a cwd is not passed, use the current window's cwd
    local cwd = opts.cwd or vim.fn.getcwd(0)

    local win = vim.fn.bufwinid(buf)
    if win == -1 then
        local open_win = opts.open_win or require("doit").config.open_win
        win = open_win(buf, self)
        vim.api.nvim_win_set_buf(win, buf)
        matchadd(win)

        vim.api.nvim_set_option_value("number", false, { win = win })
    end

    -- change cwd of task window
    vim.api.nvim_win_call(win, function()
        vim.cmd("lcd " .. cwd)
    end)

    local noitfy = opts.notify or require("doit").config.notify
    self:_jobstart(cmd, buf, cwd, noitfy, opts.stdin)

    -- may reuse in next call to run()
    self.last_cmd = cmd
    self.last_cwd = cwd
    self.last_buffer_name = buffer_name
    self.last_stdin = opts.stdin -- only reused by rerun()

end

---@param opts RunOpts?
function Task:rerun(opts)
    if self.last_cmd == nil then
        vim.notify("nothing to rerun", vim.log.levels.INFO)
        return
    end

    opts = opts or {}
    opts.cwd = self.last_cwd
    opts.stdin = self.last_stdin

    self:run(self.last_cmd, opts)
end

---@return false | number
function Task:stop()
    if self.chan ~= nil then
        local res = vim.fn.jobstop(self.chan)
        self.chan = nil
        return res
    end

    return false
end

-- NOTE: wont work on windows

---@param signal number
function Task:kill(signal)
    if self.chan then
        local pid = vim.fn.jobpid(self.chan)
        return vim.system({'kill', '-s', signal, pid})
    end
end

function Task:interrupt()
    return self:kill(SIGINT-128)
end

-- completion function for prompt_for_cmd()
-- credit goes to https://github.com/ej-shafran/compile-mode.nvim
-- Thank you!
vim.cmd[[
function! DoitInputComplete(ArgLead, CmdLine, CursorPos)
    let HasNoSpaces = a:CmdLine =~ '^\S\+$'
    let Results = getcompletion('!' . a:CmdLine, 'cmdline')
    let TransformedResults = map(Results, 'HasNoSpaces ? v:val : a:CmdLine[:strridx(a:CmdLine, " ") - 1] . " " . v:val')
    return TransformedResults
endfunction
]]

---@param opts RunOpts?
function Task:prompt_for_cmd(opts)
    local settings =  {
        prompt = "Command to run: ",
        default = self.last_cmd or "",
        completion = "customlist,DoitInputComplete",
    }

    local use_vim_ui = require("doit").config.prompt_cmd_with_vim_ui
    if use_vim_ui then
        vim.ui.input(settings, function(input)
            if input ~= nil and input ~= "" then
                self:run(input, opts)
            end
        end
        )
    else
        local input = vim.fn.input(settings)
        if input ~= nil and input ~= "" then
            self:run(input, opts)
        end
    end

end

do
    vim.api.nvim_set_hl(0, "DoitTaskSuccess",   { link = "Title",      default = true })
    vim.api.nvim_set_hl(0, "DoitTaskAbnormal",  { link = "WarningMsg", default = true })
    vim.api.nvim_set_hl(0, "DoitTaskSegfault",  { link = "WarningMsg", default = true })
    vim.api.nvim_set_hl(0, "DoitTaskTerminate", { link = "WarningMsg", default = true })
    vim.api.nvim_set_hl(0, "DoitTaskInterrupt", { link = "WarningMsg", default = true })
end


local task = Task.new()

return task
