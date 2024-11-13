local M = {}

local rules = require("doit.rules")

-- to speed up searching
local cache = vim.ringbuf(5)

local highlights = {
    filename = "DoitFilename",
    line = "DoitLine",
    col = "DoitCol",
    type = "DoitMsgType",
}

-- TODO: implement a stack system where multiple buffers can register themselves
-- as error buffers. Image a scenario where
-- 1. bufA is set as the error buffer via M.set_buf()
-- 2. bufB is set as the error buffer via M.set_buf()
-- 3. bufB is deleted
--
-- The current behaviour: next() and previous() won't work
-- New behaviour: next() and previos() will automatically call M.set_buf(bufA)
--
-- An easy way to achieve is to make set_buf() sets a buffer variable vim.b[buf].doit_errorbuf = true
-- then when jump_extmark() sees that the current_buf is nil, it will find
-- the first buf in vim.api.nvim_list_bufs() with vim.b.doit_errorbuf is true
-- and set that as the current_buf buf.

-- I'm hesitant to implement this feature because users might find it confusing

local state = {
    current_buf = nil,
    extmark_id = nil,
    autocmd_id = nil,
    ns_id = vim.api.nvim_create_namespace(""),
    extmark_line = nil,
}

---@param buf number
---@param line string
---@param idx number
function M.highlight_line(buf, line, idx)
    local cap = M.match(line)
    if cap == nil then
        return
    end

    buf = buf or state.current_buf

    for k, span in pairs(cap) do
        local byte_start = vim.str_byteindex(line, span.start - 1)
        local byte_finish = vim.str_byteindex(line, span.finish - 1)
        vim.api.nvim_buf_add_highlight(buf, -1, highlights[k], idx, byte_start, byte_finish)
    end
end

local function get_valid_extmark()
    if state.extmark_id == nil then
        return nil
    end

    local extmark = vim.api.nvim_buf_get_extmark_by_id(state.current_buf, state.ns_id, state.extmark_id, { details = true})

    if vim.tbl_isempty(extmark) or extmark[3].invalid then
        vim.api.nvim_buf_del_extmark(state.current_buf, state.ns_id, state.extmark_id)
        state.extmark_id = nil
        return nil
    end

    return extmark
end

---auto remove the extmark when :terminal redraws
---@param buf number
local function attach_term(buf)
    vim.api.nvim_buf_attach(buf, false, {
        on_lines = function(_, _, _, first_idx, last_idx, last_update_idx)
            -- remove extmark if the line it was on has changed
            local extmark = get_valid_extmark()
            if extmark ~= nil and extmark[1] >= first_idx and extmark[1] < last_idx then

                -- HACK: terminal buffers may decide draw the same lines twice (weird)
                -- so we have to check that the new line placed at extmark[1] is NOT the
                -- same as state.extmark_line
                local line  = vim.api.nvim_buf_get_lines(buf, extmark[1], extmark[1]+1, true)[1]
                if state.extmark_line ~= line then
                    -- vim.print({state.extmark_line = state.extmark_line, line = line,  first_idx = first_idx, last_idx = last_idx, state.extmark_idx = extmark[1], last_update_idx = last_update_idx })
                    vim.api.nvim_buf_del_extmark(buf, state.ns_id, state.extmark_id)
                    state.extmark_id = nil
                end
            end
        end
    })
end


---@param buf number
function M.set_buf(buf)

    -- dont do anything if the same buf is passed
    if state.current_buf == buf then
        return
    end

    if not vim.api.nvim_buf_is_valid(buf) then
        error(string.format("buffer %d is not a valid buffer", buf))
    end

    if state.extmark_id ~= nil then
        vim.api.nvim_buf_del_extmark(state.current_buf, state.ns_id, state.extmark_id)
        state.extmark_id = nil
    end

    state.current_buf = buf

    -- remove previous autocmd if it exists
    if state.autocmd_id ~= nil then
        vim.api.nvim_del_autocmd(state.autocmd_id)
    end

    -- clear state.current_buf when the buffer gets deleted
    state.autocmd_id = vim.api.nvim_create_autocmd({ "BufDelete" }, {
        buffer = buf,
        callback = function(_)
            state.current_buf = nil
            state.autocmd_id = nil
        end,
        desc = "doit: remove buf from being the current error buf",
        once = true,
    })

    local buftype = vim.api.nvim_get_option_value('buftype', { buf = buf })
    if buftype == 'terminal' then
        attach_term(buf)
    end

end

local function get_or_make_error_win()
    local win = vim.fn.bufwinid(state.current_buf)
    if win == -1 then
        win = vim.api.nvim_open_win(state.current_buf, false, {
            split = "below",
        })
    end

    return win
end


-- if window containing buffer is present, use it
-- if current window is quickfix reuse last accessed window.
-- if current window is NOT quickfix, use it
-- If only one window, open split above
--- Emulates quickfix window behaviour
--- TODO: might want to respect 'switchbuf' option
local function get_or_make_target_win(buf)
    local current_win = vim.api.nvim_get_current_win()
    local all_wins = vim.api.nvim_list_wins()

    if #all_wins == 1 and vim.api.nvim_win_get_buf(current_win) == state.current_buf then
        return vim.api.nvim_open_win(buf, false, { split = "above", win = -1 })
    end

    local target_win = vim.fn.bufwinid(buf)
    if target_win ~= -1 then
        return target_win
    end

    if current_win ~= vim.fn.bufwinid(state.current_buf) then
        return vim.api.nvim_get_current_win()
    end

    -- focus on previous and go back
    vim.cmd.wincmd({"p"})
    local win = vim.api.nvim_get_current_win()
    vim.cmd.wincmd({"p"})

    return win

end

---@param line string
---@return Capture?
function M.match(line)
    for _, rule in pairs(cache._items) do
        local data = rule:match(line)
        if data ~= nil then
            return data
        end
    end

    for k, rule in pairs(rules) do
        local data = rule:match(line)
        if data ~= nil then
            cache:push(rule)
            vim.print(k)
            return data
        end
    end

    return nil
end

---@param data Capture
---@param row number 0-base
---@param opts? { focus: boolean }
function M.enter(data, row, opts)
    opts = opts or {}

    local filename = data.filename.value
    local buf = vim.iter(vim.api.nvim_list_bufs())
        :filter(function(b) return vim.api.nvim_buf_is_loaded(b) end)
        :find(function(b) return vim.api.nvim_buf_get_name(b) == filename end)

    if buf == nil then
        buf = vim.fn.bufadd(filename)
    end

    local win = get_or_make_target_win(buf)
    vim.api.nvim_win_set_buf(win, buf)

    local focus = opts.focus
    if focus == nil then
        focus = true
    end

    if focus then
        vim.api.nvim_set_current_win(win)
    end

    local line = data.line and data.line.value
    if line == nil then
        return
    end

    local col = data.col and data.col.value or 1
    col = col - 1 -- colums are 0-based
    pcall(vim.api.nvim_win_set_cursor, win, { line, col, })


    M.set_extmark(row)
end

---@param data Capture
---@param row number 0-base
function M.display(data, row)
    M.enter(data, row, { focus = false})
end

---@param row number
function M.set_extmark(row)
    if state.current_buf == nil then
        return
    end

    -- clean up previous extmark
    if state.extmark_id ~= nil then
        vim.api.nvim_buf_del_extmark(state.current_buf, state.ns_id, state.extmark_id)
    end

    state.extmark_id = vim.api.nvim_buf_set_extmark(state.current_buf, state.ns_id, row, 0, {
        sign_text = ">",
        sign_hl_group = "DoitCurrent",
        invalidate = true, -- invalidate the extmark if the line gets deleted
    })

    state.extmark_line = vim.api.nvim_buf_get_lines(state.current_buf, row, row+1, true)[1]

    local win = get_or_make_error_win()
    vim.api.nvim_win_set_cursor(win, { row+1, 0 })

    -- FIXME: would be nice to center the the window around the cursor if its currently
    -- focused on the last visible line. However, this needs scroll information
    -- which neovim currently doesn't expose
    -- vim.api.nvim_win_call(win, function()
    --     vim.cmd.normal({"zz", bang = true })
    -- end)

end

---@param step number
---@param start number
---@return { data: Capture, row: number}?
local function jump(step, start)
    if state.current_buf == nil then
        return
    end

    if step == 0 then
        step = 1
    end

    local last_idx
    if step < 0 then
        last_idx = -1
    else
        last_idx = vim.api.nvim_buf_line_count(state.current_buf)
    end

    local i = start
    while i ~= last_idx do
        local line = vim.api.nvim_buf_get_lines(state.current_buf, i, i + 1, true)[1]
        local data = M.match(line)
        if data ~= nil then
            return { data = data, row = i }
        end

        i = i + step
    end

    if step < 0 then
        vim.notify("Moved back before first error", vim.log.levels.INFO)
    else
        vim.notify("Moved past last error", vim.log.levels.INFO)

    end
end

---Like jump(), but start is set at row of the extmark
---@return { data: Capture, row: number}?
local function jump_extmark(step)
    local extmark = get_valid_extmark()
    local start
    if extmark ~= nil then
        start = extmark[1] + step
    else
        start = 0
    end

    return jump(step, start)
end

function M.next_error()
    local res = jump_extmark(1)
    if res ~= nil then
        M.enter(res.data, res.row)
    end
end

function M.prev_error()
    local res = jump_extmark(-1)
    if res ~= nil then
        M.enter(res.data, res.row)
    end
end

---@param step number
local function move_to(step)
    local win = get_or_make_error_win()
    local row = vim.api.nvim_win_get_cursor(win)[1]-1
    local res = jump(step, row+step)

    if res ~= nil then
        vim.api.nvim_win_set_cursor(win, {res.row+1, 0})
    end

end

function M.move_to_next_error()
    move_to(1)
end

function M.move_to_prev_error()
    move_to(-1)
end

---@return {data: Capture, row: number}?
local function get_capture_under_cursor()
    M.set_buf(vim.api.nvim_get_current_buf())

    local win = get_or_make_error_win()
    local row = vim.api.nvim_win_get_cursor(win)[1]                     -- 1-based
    local line = vim.api.nvim_buf_get_lines(state.current_buf, row - 1, row, true)[1] -- 0-based

    local data = M.match(line)
    if data ~= nil then
        return { data = data, row = row-1 }
    end

end

function M.goto_error_under_cursor()
    local res = get_capture_under_cursor()

    if res ~= nil then
        M.enter(res.data, res.row)
    end

end

function M.display_error_under_cursor()
    local res = get_capture_under_cursor()

    if res ~= nil then
        M.display(res.data, res.row)
    end

end

---Like jump(), but tries to find a file different from skip_file
---@param step number
---@param start number
---@param skip_file string name of file to skip over
---@return {data: Capture, row: number}?
local function jump_to_file(step, start, skip_file)

    local row = start
    while true do
        local res = jump(step, row+step)
        if res == nil then
            return
        elseif res.data.filename.value ~= skip_file then
            return res
        else
            row = res.row
        end
    end

end

---@param step number
---@return {data: Capture, row: number}?
local function move_to_file(step)
    local win = get_or_make_error_win()
    local row = vim.api.nvim_win_get_cursor(win)[1]-1
    local skip_file = vim.tbl_get(get_capture_under_cursor() or {}, "data", "filename", "value")
    local res = jump_to_file(step, row, skip_file)

    if res ~= nil then
        vim.api.nvim_win_set_cursor(win, {res.row+1, 0})
    end

end

function M.move_to_next_file()
    move_to_file(1)
end

function M.move_to_prev_file()
    move_to_file(-1)
end

function M.goto_file(step)
    local extmark = get_valid_extmark()

    if extmark == nil then
        local res = jump_extmark(step)
        if res ~= nil then
            M.enter(res.data, res.row)
            return
        end
    end

    local row = extmark[1]
    local line = vim.api.nvim_buf_get_lines(state.current_buf, row, row+1, true)[1] -- 0-based
    local skip_file = M.match(line).filename.value -- must succeed
    ---@cast skip_file string

    local res = jump_to_file(step, row + step, skip_file)
    if res ~= nil then
        M.enter(res.data, res.row)
    end

end

function M.goto_next_file()
    return M.goto_file(1)
end

function M.goto_prev_file()
    return M.goto_file(-1)
end

function M.set_default_keymaps(buf)
    vim.keymap.set("n", "<CR>", M.goto_error_under_cursor, { buffer = buf })
    vim.keymap.set("n", "<leader><CR>", M.display_error_under_cursor, { buffer = buf })
    vim.keymap.set("n", "gj", M.move_to_next_error, { buffer = buf })
    vim.keymap.set("n", "gk", M.move_to_prev_error, { buffer = buf })
    vim.keymap.set("n", "]]", M.move_to_next_file, { buffer = buf })
    vim.keymap.set("n", "[[", M.move_to_prev_file, { buffer = buf })
end

do
    vim.api.nvim_set_hl(0, "DoitFilename", { link = "QuickfixLine", default = true })
    vim.api.nvim_set_hl(0, "DoitLine", { link = "ModeMsg", default = true })
    vim.api.nvim_set_hl(0, "DoitCol", { link = "Question", default = true })
    vim.api.nvim_set_hl(0, "DoitType", { link = "WarningMsg", default = true })
    vim.api.nvim_set_hl(0, "DoitCurrent", { link = "Removed", default = true })
end

return M
