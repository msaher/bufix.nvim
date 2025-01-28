local M = {}

---@class BufixFullConfig
local default_config = {
    --- Buffer local keymaps in bufix buffers. Such as <CR> to jump or <C-q> to
    --- send to qflist
    ---@type boolean
    want_buffer_keymaps = true,

    --- How long to highlight the cursor after jumping. Set it to 0 to disable
    --- it.
    ---@type number in milliseconds
    locus_highlight_duration = 500,

    ---Add any aditional parsing rules
    ---See `:h bufix-rules` to learn more
    ---@type table
    rules = {}
}

---@class BufixConfig
---@field want_nav_keymaps? boolean
---@field locus_highlight_duration? number
---@field rules? table

---@type BufixFullConfig
M.config = default_config

M.rules = require("bufix.rules")

---@param cfg BufixConfig?
function M.setup(cfg)
    ---@diagnostic disable-next-line assign-type-mismatch
    if cfg ~= nil then

        M.config = vim.tbl_deep_extend('force', M.config, cfg)

        M.rules = vim.tbl_deep_extend('force', M.rules, M.config.rules)

        if package.loaded["bufix.api"] then
            require("bufix.api").cache:clear()
        end
    end

end

return M
