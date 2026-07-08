local DataStorage = require("datastorage")

local GrimmoryLogger = require("grimmory/logger")

local logger = GrimmoryLogger:new()

---@class GrimmoryPluginMetadata
local PluginMetadata = {
    meta = nil,
}

function PluginMetadata.getPluginPath()
    local source = debug.getinfo(1, "S").source
    local path = source:match("@(.*%.koplugin)/")
    if not path then
        path = DataStorage:getDataDir() .. "/plugins/grimmory.koplugin"
    end

    return path
end

function PluginMetadata.getMeta()
    if PluginMetadata.meta == nil then
        local plugin_path = PluginMetadata.getPluginPath()
        local meta_path = plugin_path .. "/_meta.lua"

        local load_ok, meta = pcall(dofile, meta_path)

        if load_ok and type(meta) == "table" then
            PluginMetadata.meta = meta
        else
            logger:err("Failed to load meta:", meta or "Unknown error")
            PluginMetadata.meta = false
        end
    end

    return PluginMetadata.meta or {}
end

---@return boolean has_repository
function PluginMetadata.hasRepository()
    local meta = PluginMetadata.getMeta()

    return type(meta.repository) == "string"
end

---@return string version
function PluginMetadata.getVersion()
    local meta = PluginMetadata.getMeta()

    if type(meta.version) ~= "string" then
        return "0.0.0-snapshot"
    end

    return meta.version
end

---@return string repository
function PluginMetadata.getRepository()
    local meta = PluginMetadata.getMeta()

    if type(meta.repository) ~= "string" then
        return "unknown repository"
    end

    return meta.repository
end

return PluginMetadata