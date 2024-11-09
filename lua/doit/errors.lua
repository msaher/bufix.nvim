local M = {}

local rules = require("doit.rules")

-- to speed up searching
local cache = vim.ringbuf(5)

-- highlight
-- TODO: allow users to override this. Also create actual highlight grups
M.highlights = {
    filename = "Directory",
    line = "ModeMsg",
    col = "Question",
    type = "WarningMsg",
}

-- TODO: implement a stack system where multiple buffers can attach themselves
-- as error buffers
local current_buf = nil
local cwd = nil
local extmark_id = nil
local autocmd_id = nil
local ns_id = vim.api.nvim_create_namespace("")

---@param buf number
function M.set_buf(buf)

    -- dont do anything if the same buf is passed
    if current_buf == buf then
        return
    end

    if not vim.api.nvim_buf_is_valid(buf) then
        error(string.format("buffer %d is not a valid buffer", buf))
    end

    current_buf = buf

    -- remove previous autocmd if it exists
    if autocmd_id ~= nil then
        vim.api.nvim_del_autocmd(autocmd_id)
    end

    -- clear current_buf when the buffer gets deleted
    autocmd_id = vim.api.nvim_create_autocmd({ "BufDelete" }, {
        buffer = buf,
        callback = function(_)
            current_buf = nil
            autocmd_id = nil
            return true -- deletes autocmd
        end,
    })

end

---@param cwd string
function M.set_cwd(cwd)
    M.cwd = cwd
end

local function get_or_make_error_win()
    local win = vim.fn.bufwinid(current_buf)
    if win == -1 then
        win = vim.api.nvim_open_win(current_buf, false, {
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

    if #all_wins == 1 and vim.api.nvim_win_get_buf(current_win) == current_buf then
        return vim.api.nvim_open_win(buf, false, { split = "above", win = -1 })
    end

    local target_win = vim.fn.bufwinid(buf)
    if target_win ~= -1 then
        return target_win
    end

    if current_win ~= vim.fn.bufwinid(current_buf) then
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
    for k, rule in pairs(cache._items) do
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
---@param opts? { focus: bool }
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
    if current_buf == nil then
        return
    end

    -- clean up previous extmark
    if extmark_id ~= nil then
        vim.api.nvim_buf_del_extmark(current_buf, ns_id, extmark_id)
    end

    extmark_id = vim.api.nvim_buf_set_extmark(current_buf, ns_id, row, 0, {
        sign_text = ">",
        sign_hl_group = "TODO",
        invalidate = true, -- invalidate the extmark if the line gets deleted
    })

    local win = get_or_make_error_win()
    vim.api.nvim_win_set_cursor(win, { row+1, 0 })

    -- FIXME: would be nice to center the the window around the cursor if its currently
    -- focused on the last visible line. However, this needs scroll information
    -- which neovim currently doesn't expose
    -- vim.api.nvim_win_call(win, function()
    --     vim.cmd.normal({"zz", bang = true })
    -- end)

end

local function get_valid_extmark()
    if extmark_id == nil then
        return nil
    end

    local extmark = vim.api.nvim_buf_get_extmark_by_id(current_buf, ns_id, extmark_id, { details = true})

    if vim.tbl_isempty(extmark) or extmark[3].invalid then
        vim.api.nvim_buf_del_extmark(current_buf, ns_id, extmark_id)
        extmark_id = nil
        return nil
    end

    return extmark
end

---@param step number
---@param start number
---@return { data: Capture, row: number}?
local function jump(step, start)
    if current_buf == nil then
        return
    end

    if step == 0 then
        step = 1
    end

    local last_idx
    if step < 0 then
        last_idx = -1
    else
        last_idx = vim.api.nvim_buf_line_count(current_buf)
    end

    local i = start
    while i ~= last_idx do
        local line = vim.api.nvim_buf_get_lines(current_buf, i, i + 1, true)[1]
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
---@param number
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

function M.next()
    local res = jump_extmark(1)
    if res ~= nil then
        M.enter(res.data, res.row)
    end
end

function M.prev()
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
    if current_buf == nil then
        return
    end

    local win = get_or_make_error_win()
    local row = vim.api.nvim_win_get_cursor(win)[1]                     -- 1-based
    local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, true)[1] -- 0-based

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
        res = jump(step, row+step)
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
---@param start number
---@return {data: Capture, row: number}?
local function move_to_file(step)
    local win = get_or_make_error_win()
    local row = vim.api.nvim_win_get_cursor(win)[1]-1
    local skip_file = vim.tbl_get(get_capture_under_cursor() or {}, "data", "filename", "value")
    local res = jump_to_file(step, row+step, skip_file)

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

end

return M
