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
    local buf = vim.iter(vim.api.nvim_list_bufs())
        :filter(function(b) return vim.api.nvim_buf_is_loaded(b) end)
        :find(function(b) return vim.api.nvim_buf_get_name(b) == data.filename end)

    if buf == nil then
        local path = vim.fs.joinpath(cwd, data.filename)
        -- TODO: if the file doesn't really exist prompt before adding
        buf = vim.fn.bufadd(path)
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

    if data.line ~= nil then
        local col = data.col or 1
        col = col - 1 -- 0-based
        vim.api.nvim_win_set_cursor(win, {
            data.line,
            col,
        })

    end

end

return M
