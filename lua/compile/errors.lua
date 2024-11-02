local M = {}

local rules = require("compile.rules")

-- to speed up searching
local cache = vim.ringbuf(5)

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
---@param cwd? string
function M.enter(data, cwd)
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
    vim.api.nvim_win_set_cursor(win, { line, col, })

end

return M
