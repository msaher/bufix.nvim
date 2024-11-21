local M = {}

-- to speed up searching
local cache = vim.ringbuf(5)

local highlights = {
    filename = "DoitFilename",
    line = "DoitLine",
    line_end = "DoitLineEnd",
    col = "DoitCol",
    col_end = "DoitColEnd",
    type = "DoitMsgType",
}

-- TODO: try to use sum types for added safety to prevent mistakes
-- merge extmark and extmark_line into a single tuple
-- merge current_buf and autocmd_id into a single tuple
-- rust inspired psuedo code:
-- enum State {
--  Initial,
--  withBuf(current_buf, autocmd_id),
--  WithExtmark(current_buf, autocmd_id, extmark_id, extmark_line)
-- }
-- maybe a type annotation like this could help @field type "Initial" | "WithBuf" | "WithExtmark"
-- and then a few helper functions for state transitions

---@class State
local state = {
    ---@type number?
    current_buf = nil,

    ---@type number?
    extmark_id = nil,

    ---@type number?
    autocmd_id = nil,

    ---@type number
    ns_id = vim.api.nvim_create_namespace(""),

    ---@type string?
    extmark_line = nil,

    ---@type number
    locus_ns = vim.api.nvim_create_namespace(""),

    ---@type table? uv_timer_t
    locus_timer = nil,

}

---@param line string
---@return Capture?
local function match(line)
    for _, rule in pairs(cache._items) do
        local data = rule:match(line)
        if data ~= nil then
            return data
        end
    end
    local rules = require("doit.rules")

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


---@param buf number
---@param line string
---@param idx number
local function highlight_line(buf, line, idx)

    local cap = match(line)
    if cap == nil then
        vim.api.nvim_buf_clear_namespace(buf, -1, idx, idx+1)
        return
    end

    for k, span in pairs(cap) do
        local byte_start = vim.str_byteindex(line, span.start - 1)
        local byte_finish = vim.str_byteindex(line, span.finish - 1)
        ---@cast byte_start number
        ---@cast byte_finish number
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

---Used for highlighting
local function attach_highlights(buf)

    -- we process the entire buffer manually first.
    -- because nvim_buf_attach()'s second argument for sending the entire buffer
    -- is ignored in lua
    local all_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    for i, line in ipairs(all_lines) do
        highlight_line(buf, line, i-1)
    end

    vim.api.nvim_buf_attach(buf, false, {
        on_lines = function(_, _, _, first_idx, _, last_update_idx)
            local lines = vim.api.nvim_buf_get_lines(buf, first_idx, last_update_idx, false)
            for i, line in ipairs(lines) do
                highlight_line(buf, line, first_idx+i-1)
            end
        end
    })
end


---auto remove the extmark when :terminal redraws
---Only makes sense when buf is state.current_buf
---@param buf number
local function attach_term(buf)
    vim.api.nvim_buf_attach(buf, false, {
        on_lines = function(_, _, _, first_idx, last_idx)
            if buf ~= state.current_buf then
                return
            end
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

local function attach(buf)
    attach_highlights(buf)
    local buftype = vim.api.nvim_get_option_value('buftype', { buf = buf })
    if buftype == 'terminal' then
        attach_term(buf)
    end

    if require("doit").config.want_error_keymaps then
        M.set_default_keymaps(buf)
    end
end

---@param buf number
function M.register_buf(buf)
    if state.current_buf == nil then
        M.set_buf(buf)
    elseif not vim.b[buf].doit_errorbuf then
        ---@diagnostic disable-next-line: cast-local-type
        buf = (buf == 0) and vim.api.nvim_get_current_buf() or buf
        vim.b[buf].doit_errorbuf = true
        attach(buf)
    end
end

---@param buf number
function M.set_buf(buf)
    -- dont do anything if the same buf is passed
    if state.current_buf == buf then
        return
    end

    ---@diagnostic disable-next-line: cast-local-type
    buf = (buf == 0) and vim.api.nvim_get_current_buf() or buf
    if not vim.api.nvim_buf_is_valid(buf) then
        error(string.format("buffer %d is not a valid buffer", buf))
    end

    if state.extmark_id ~= nil then
        vim.api.nvim_buf_del_extmark(state.current_buf, state.ns_id, state.extmark_id)
        state.extmark_id = nil
        state.extmark_line = nil
    end

    -- remove previous autocmd if it exists
    if state.autocmd_id ~= nil then
        vim.api.nvim_del_autocmd(state.autocmd_id)
    end

    ---@cast buf number
    state.current_buf = buf

    -- clear state.current_buf when the buffer gets deleted
    state.autocmd_id = vim.api.nvim_create_autocmd({ "BufDelete" }, {
        buffer = buf,
        callback = function(_)
            if state.extmark_id ~= nil then
                vim.api.nvim_buf_del_extmark(state.current_buf, state.ns_id, state.extmark_id)
                state.extmark_id = nil
                state.extmark_line = nil
            end
            state.current_buf = nil
            state.autocmd_id = nil

            -- set the next error buffer by looking for the first buffer that
            -- sets b:doit_errorbuf to true
            local next_buf = vim.iter(vim.api.nvim_list_bufs())
                :filter(function(b) return vim.api.nvim_buf_is_loaded(b) end)
                :filter(function(b) return vim.b[b].doit_errorbuf == true end)
                :find(function(b) return state.current_buf ~= b end)

            if next_buf ~= nil then
                M.set_buf(next_buf)
            end

        end,
        desc = "doit: remove buf from being the current error buf",
        once = true,
    })

    if not vim.b[buf].doit_errorbuf then
        vim.b[buf].doit_errorbuf = true
        attach(buf)
    end
end

local function get_or_make_error_win()
    local win = vim.fn.bufwinid(state.current_buf)
    if win == -1 then
        ---@diagnostic disable-next-line: cast-local-type
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

---@param row number
local function set_extmark(row)
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

---@param buf number
---@param win number
---@param line number 1-base
---@param col number 1-base
---@param end_col number? 1-base
local function set_cursor(buf, win, line, col, end_col)
    -- nvim_win_set_cursor() may fail.
    -- This happens when nvim isn't allowed to edit the buffer, and thus
    -- nvim opens an empty buffer with the same name
    col = col - 1 -- colums are 0-based
    local ok = pcall(vim.api.nvim_win_set_cursor, win, { line, col })
    if not ok then
        return
    end

    line = line - 1 -- back to 0-base again.
    if end_col == nil then
        end_col = vim.api.nvim_buf_get_lines(buf, line, line + 1, false)[1]:len()
    else
        end_col = end_col - 1
    end

    -- remove current highlight if it exists
    if state.locus_timer ~= nil and state.locus_timer:is_active() then
        -- wrap in pcall because timer might've closed already
        pcall(function () state.locus_timer:close() end)
        pcall(vim.api.nvim_buf_clear_namespace, buf, state.locus_ns, 0, -1)
        state.locus_timer = nil
    end

    vim.highlight.range(buf, state.locus_ns, "DoitLocus", { line, col } , { line, end_col }, {
        regtype = 'v',
        inclusive = true,
    })

    state.locus_timer = vim.defer_fn(function()
        vim.api.nvim_buf_clear_namespace(buf, state.locus_ns, line, line+1)
    end, 500)

end


---@param data Capture
---@param row number 0-base
---@param opts? { focus: boolean }
local function enter(data, row, opts)
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

    local line = vim.tbl_get(data, "line", "value")
    if line == nil then
        return
    end
    ---@cast line number

    local col = vim.tbl_get(data, "col", "value") or 1
    local end_col = vim.tbl_get(data, "end_col", "value")

    set_cursor(buf, win, line, col, end_col)
    set_extmark(row)
end

---@param data Capture
---@param row number 0-base
function M.display(data, row)
    enter(data, row, { focus = false})
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
        local data = match(line)
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

function M.goto_next()
    local res = jump_extmark(1)
    if res ~= nil then
        enter(res.data, res.row)
    end
end

function M.goto_prev()
    local res = jump_extmark(-1)
    if res ~= nil then
        enter(res.data, res.row)
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

function M.move_to_next()
    move_to(1)
end

function M.move_to_prev()
    move_to(-1)
end

---@return {data: Capture, row: number}?
local function get_capture_under_cursor()
    local buf = vim.api.nvim_get_current_buf()
    if not vim.b[buf].doit_errorbuf then
        return
    end

    ---@cast buf number
    M.set_buf(buf)

    local win = get_or_make_error_win()
    local row = vim.api.nvim_win_get_cursor(win)[1]                     -- 1-based
    local line = vim.api.nvim_buf_get_lines(state.current_buf, row - 1, row, true)[1] -- 0-based

    local data = match(line)
    if data ~= nil then
        return { data = data, row = row-1 }
    end

end

function M.goto_error_under_cursor()
    local res = get_capture_under_cursor()

    if res ~= nil then
        enter(res.data, res.row)
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

local function goto_file(step)
    local extmark = get_valid_extmark()

    if extmark == nil then
        local res = jump_extmark(step)
        if res ~= nil then
            enter(res.data, res.row)
        end
        return
    end

    local row = extmark[1]
    local line = vim.api.nvim_buf_get_lines(state.current_buf, row, row+1, true)[1] -- 0-based
    local skip_file = match(line).filename.value -- must succeed
    ---@cast skip_file string

    local res = jump_to_file(step, row, skip_file)
    if res ~= nil then
        enter(res.data, res.row)
    end

end

function M.goto_next_file()
    return goto_file(1)
end

function M.goto_prev_file()
    return goto_file(-1)
end

function M.set_default_keymaps(buf)
    vim.keymap.set("n", "<CR>" , M.goto_error_under_cursor,    { buffer = buf })
    vim.keymap.set("n", "g<CR>", M.display_error_under_cursor, { buffer = buf })
    vim.keymap.set("n", "gj"   , M.move_to_next,               { buffer = buf })
    vim.keymap.set("n", "gk"   , M.move_to_prev,               { buffer = buf })
    vim.keymap.set("n", "]]"   , M.move_to_next_file,          { buffer = buf })
    vim.keymap.set("n", "[["   , M.move_to_prev_file,          { buffer = buf })
end

do
    vim.api.nvim_set_hl(0, "DoitFilename", { link = "QuickfixLine", default = true })
    vim.api.nvim_set_hl(0, "DoitLine",     { link = "ModeMsg",      default = true })
    vim.api.nvim_set_hl(0, "DoitLineEnd",  { link = "Title",        default = true })
    vim.api.nvim_set_hl(0, "DoitCol",      { link = "Question",     default = true })
    vim.api.nvim_set_hl(0, "DoitColEnd",   { link = "Directory",    default = true })
    vim.api.nvim_set_hl(0, "DoitType",     { link = "WarningMsg",   default = true })
    vim.api.nvim_set_hl(0, "DoitCurrent",  { link = "Removed",      default = true })
    vim.api.nvim_set_hl(0, "DoitLocus",    { link = "Visual",       default = true })
end

return M
