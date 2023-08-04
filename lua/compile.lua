local A = vim.api
local fn = vim.fn
local M = {}

Compile = {}
Compile.__index = Compile

local default_config = {
    job_opts = {
    }
}

function Compile:new(o)
   local obj = vim.tbl_deep_extend('force', default_config, o)
   return setmetatable(obj, self)
end

function Compile:has_buf()
    return self.buf ~= nil
end

function Compile:get_win()
    if self.buf == nil  then
        return nil
    end

    local wid = fn.bufwinid(self.buf)
    if wid == -1 then
        wid = nil
    end

    return wid
end

function Compile:_has_buf()
    -- return self.buf ~= nil
    return fn.bufexists(self.buf) ~= 0
end
