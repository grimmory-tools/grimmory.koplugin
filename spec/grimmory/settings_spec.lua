local assert = require 'luassert'
local spy = require 'luassert.spy'

package.path = "grimmory.koplugin/?.lua;" .. package.path

describe("GrimmorySettings book read status", function()
    local Settings
    local names = { "gettext", "datastorage", "luasettings", "random", "device", "grimmory/logger" }
    local saved_preload, saved_loaded, saved_settings
    before_each(function()
        saved_preload, saved_loaded = {}, {}
        saved_settings = package.loaded["grimmory/settings"]
        for _, name in ipairs(names) do
            saved_preload[name], saved_loaded[name] = package.preload[name], package.loaded[name]
            package.loaded[name] = nil
        end
        package.preload["gettext"] = function() return function(value) return value end end
        package.preload["datastorage"] = function() return {} end
        package.preload["luasettings"] = function() return {} end
        package.preload["random"] = function() return { uuid = function() return "test-id" end } end
        package.preload["device"] = function() return { model = "test-device" } end
        package.preload["grimmory/logger"] = function() return { new = function() return {} end } end
        package.loaded["grimmory/settings"] = nil
        Settings = require("grimmory/settings")
    end)

    after_each(function()
        for _, name in ipairs(names) do
            package.preload[name], package.loaded[name] = saved_preload[name], saved_loaded[name]
        end
        package.loaded["grimmory/settings"] = saved_settings
    end)

    it("defaults on for existing configurations and persists toggles independently", function()
        local settings = setmetatable({
            data = { sync_reading_progress = false }, write = spy.new(function() end),
        }, { __index = Settings })
        assert.is_true(settings:getSyncBookReadStatus())
        settings:toggleSyncBookReadStatus()
        assert.is_false(settings:getSyncBookReadStatus())
        assert.is_false(settings:getSyncReadingProgress())
        settings:toggleSyncBookReadStatus()
        assert.is_true(settings:getSyncBookReadStatus())
        assert.spy(settings.write).was.called(2)
    end)
end)
