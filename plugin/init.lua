---@class Subcommand
---@field impl fun(args:string[], opts: table) command implementation
---@field complete? fun(sub_arg_lead: string, sub_cmdline: string?): string[]  Command completions callback, taking the lead of the subcommand's arguments

local split_mapping = {
    horizontal = {
        aboveleft = {split = "above", win = 0},
        belowright = {split = "below", win = 0},
        topleft = {split = "above", win = -1},
        botright = {split = "below", win = -1},
        default = function()
            return {split = vim.o.splitbelow and "below" or "above", win = 0}
        end
    },
    vertical = {
        aboveleft = {split = "left", win = 0},
        belowright = {split = "right", win = 0},
        topleft = {split = "left", win = -1},
        botright = {split = "right", win = -1},
        default = function()
            return {split = vim.o.splitright and "right" or "left", win = 0}
        end
    }
}

---@return {split: string, win: number}
local function get_win_config(smods)
    local mode = smods.horizontal and "horizontal" or smods.vertical and "vertical"
    local config = mode and split_mapping[mode][smods.split] or nil
    return config or mode and split_mapping[mode].default()
end

---@type table<string, Subcommand>
local subcommand_tbl = {

    rerun = {
        impl = function()
            require("doit.task"):rerun()
        end,
    },

    next = {
        impl = function()
            require("doit.errors").goto_next()
        end
    },

    ["next-file"] = {
        impl = function()
            require("doit.errors").goto_next_file()
        end
    },

    ["prev-file"] = {
        impl = function()
            require("doit.errors").goto_prev_file()
        end
    },

    prev = {
        impl = function()
            require("doit.errors").goto_prev()
        end
    },


    run = {
        impl = function(args, ctx)
            local opts = {}

            local smods = ctx.smods
            if smods.unsilent then
                opts.notify = 'always'
            elseif smods.silent then
                opts.notify = 'on_error'
            elseif ctx.emsg_silent then
                opts.notify = 'never'
            end

            local win_config = get_win_config(ctx.smods)

            if win_config then
                opts.open_win = function(buf)
                    return vim.api.nvim_open_win(buf, false, {
                        split = win_config.split,
                        win = win_config.win
                    })
                end
            end

            if #args == 0 then
                require("doit.task"):prompt_for_cmd(opts)
            else
                require("doit.task"):run(table.concat(args, " "), opts)
            end
        end,
        complete = function(arg_lead)
            return vim.fn.getcompletion("!" .. arg_lead, 'cmdline')
        end
    },

}
---@param opts table :h lua-guide-commands-create
local function cmd(opts)
    local fargs = opts.fargs
    local subcommand_key = fargs[1]

    if subcommand_key == nil then
        local subcommand_keys = vim.tbl_keys(subcommand_tbl)
        vim.ui.select(subcommand_keys, {
            prompt = "Select one of: "
        }, function(subcmd)
                if subcmd ~= nil then
                    subcommand_tbl[subcmd].impl({}, {})
                end
            end)
        return
    end


    -- Get the subcommand's arguments, if any
    local args = #fargs > 1 and vim.list_slice(fargs, 2, #fargs) or {}
    local subcommand = subcommand_tbl[subcommand_key]
    if not subcommand and not opts.smods.emsg_silent then
        vim.notify("Doit: Unknown command: " .. subcommand_key, vim.log.levels.ERROR)
        return
    end
    -- Invoke the subcommand
    subcommand.impl(args, opts)
end

vim.api.nvim_create_user_command("Doit", cmd, {
    nargs = "*",
    desc = "Doit commands",
    complete = function(arg_lead, cmdline, _)
        -- Get the subcommand.
        local subcmd_key, subcmd_arg_lead = cmdline:match("^['<,'>]*Doit[!]*%s(%S+)%s(.*)$")
        if subcmd_key
            and subcmd_arg_lead
            and subcommand_tbl[subcmd_key]
            and subcommand_tbl[subcmd_key].complete
        then
            -- The subcommand has completions. Return them.
            local subcmd_line = cmdline:gsub("^['<,'>]*Doit[!]*%s+", "")
            return subcommand_tbl[subcmd_key].complete(subcmd_arg_lead, subcmd_line)
        end
        -- Check if cmdline is a subcommand
        if cmdline:match("^['<,'>]*Doit[!]*%s+%w*$") then
            -- Filter subcommands that match
            local subcommand_keys = vim.tbl_keys(subcommand_tbl)
            return vim.iter(subcommand_keys)
                :filter(function(key)
                    return key:find(arg_lead) ~= nil
                end)
                :totable()
        end
    end,
})
