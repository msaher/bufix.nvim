---@type table<string, Subcommand>
local subcommand_tbl = {

    register = {
        impl = function()
            require("bufix.api").register_buf(0)
        end
    },

    next = {
        impl = function()
            require("bufix.api").goto_next()
        end
    },

    ["next-file"] = {
        impl = function()
            require("bufix.api").goto_next_file()
        end
    },

    ["prev-file"] = {
        impl = function()
            require("bufix.api").goto_prev_file()
        end
    },

    prev = {
        impl = function()
            require("bufix.api").goto_prev()
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
        vim.notify("Bufix: Unknown command: " .. subcommand_key, vim.log.levels.ERROR)
        return
    end
    -- Invoke the subcommand
    subcommand.impl(args, opts)
end

vim.api.nvim_create_user_command("Bufix", cmd, {
    nargs = "*",
    range = true,
    desc = "Bufix commands",
    complete = function(arg_lead, cmdline, _)
        -- Get the subcommand.
        local subcmd_key, subcmd_arg_lead = cmdline:match("^['<,'>]*Bufix[!]*%s(%S+)%s(.*)$")
        if subcmd_key
            and subcmd_arg_lead
            and subcommand_tbl[subcmd_key]
            and subcommand_tbl[subcmd_key].complete
        then
            -- The subcommand has completions. Return them.
            local subcmd_line = cmdline:gsub("^['<,'>]*Bufix[!]*%s+", "")
            return subcommand_tbl[subcmd_key].complete(subcmd_arg_lead, subcmd_line)
        end
        -- Check if cmdline is a subcommand
        if cmdline:match("^['<,'>]*Bufix[!]*%s+%w*$") then
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
