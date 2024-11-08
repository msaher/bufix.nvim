local A = vim.api

local pub = {}

pub.split = {
    open = function()
        vim.cmd.split()
        local dir = vim.o.splitbelow and "J" or "K"
        vim.cmd.wincmd(dir)

        local win = A.nvim_get_current_win()
        return win
    end,

    focus = false,
}

pub.vsplit = {
    open = function()
        vim.cmd.vsplit()
        local dir = vim.o.splitright and "L" or "H"
        vim.cmd.wincmd(dir)

        local win = A.nvim_get_current_win()
        return win
    end,

    focus = false,
}

pub.float = {
    open = function()
        local scrn_w = vim.o.columns
        local scrn_h = vim.o.lines
        local width = math.ceil(scrn_w*0.95)
        local height = math.ceil(scrn_h*0.95 - 4)

        local row = math.ceil((scrn_h-height)/2 - 1)
        local col = math.ceil((scrn_w-width)/2)

        local opts = {
            style = "minimal",
            relative = "editor",
            width = width,
            height = height,
            row = row,
            col = col,
            border = "single",
        }

        return vim.api.nvim_open_win(0, true, opts)

    end,

    focus = true,
}

pub.current = {
    open = function()
        return A.nvim_get_current_win()
    end,

    -- doesn't matter what we put here
    focus = true,
}

return pub
