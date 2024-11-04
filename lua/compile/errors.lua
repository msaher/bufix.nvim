local M = {}

local rules = require("compile.rules")

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


local current_buf = nil
local extmark_id = nil
local autocmd_id = nil
local ns_id = vim.api.nvim_create_namespace("")

---@param buf number
function M.set_buf(buf)

    -- dont do anything if the same buf is passed
    if current_buf == buf then
        return
    end

    current_buf = buf

    -- TODO: vim notify
    if not vim.api.nvim_buf_is_valid(buf) then
        vim.print("invalid buffer. ignoring...")
        return
    end

    -- remove previous autocmd if it exists
    if autocmd_id ~= nil and vim.api.nvim_buf_is_valid(current_buf) then
        vim.api.nvim_del_autocmd(autocmd_id)
    end

    -- clear current_buf when the buffer gets deleted
    autocmd_id = vim.api.nvim_create_autocmd({ "BufDelete" }, {
        buffer = buf,
        callback = function(_)
            current_buf = nil
            return true
        end,
    })
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
---@param cwd? string
function M.enter(data, row, cwd)
    -- TODO: get working dir from window
    cwd = cwd or vim.fn.getcwd()
    local filename = data.filename.value
    local buf = vim.iter(vim.api.nvim_list_bufs())
        :filter(function(b) return vim.api.nvim_buf_is_loaded(b) end)
        :find(function(b) return vim.api.nvim_buf_get_name(b) == filename end)

    if buf == nil then
        buf = vim.fn.bufadd(filename)
    end

    local win = vim.fn.bufwinid(buf)

    -- TODO: provide an option to reuse the last accessed window like emacs
    if win == -1 then
        win = vim.api.nvim_open_win(buf, true, {
            split = "below",
            win = 0,
        })
    else
        vim.api.nvim_set_current_win(win)
    end

    local line = data.line and data.line.value
    if line == nil then
        return
    end

    local col = data.col and data.col.value or 1
    col = col - 1 -- colums are 0-based
    -- TODO: wrap in pcall and show a msg
    -- might fail if buf is open in another nvim isntance
    vim.api.nvim_win_set_cursor(win, { line, col, })

    M.set_extmark(row)
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
        invalidate = true, -- remove the mark if the line gets deleted
        undo_restore = false, -- delete the mark when its gets invalidated. breaks undo
    })
end

-- function M.jump()
-- end

---@param dir number
local function jump(step)
    -- TODO: display a message vim.notify()
    if current_buf == nil then
        return
    end

    if step == 0 then
        step = 1
    end

    local last_idx
    if step < 0 then
        last_idx = 0
    else
        last_idx = vim.api.nvim_buf_line_count(current_buf)
    end

    local extmark_row = nil
    if extmark_id ~= nil then
        extmark_row = vim.api.nvim_buf_get_extmark_by_id(current_buf, ns_id, extmark_id, {})[1]
    end

    local i
    if extmark_row ~= nil then
        i = extmark_row + step
    else
        i = 1
    end

    while i ~= last_idx do
        local line = vim.api.nvim_buf_get_lines(current_buf, i, i + 1, true)[1]
        vim.print(line)
        local data = M.match(line)
        if data ~= nil then
            M.enter(data, i)
            return
        end

        i = i + step
    end

    -- TODO: vim.notify
    vim.print("No more errors")
end

function M.next()
    return jump(1)
end

function M.prev()
    return jump(-1)
end

return M
