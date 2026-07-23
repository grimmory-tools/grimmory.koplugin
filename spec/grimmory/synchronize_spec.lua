local assert = require 'luassert'
local match = require 'luassert.match'
local spy = require 'luassert.spy'

package.path = "grimmory.koplugin/?.lua;" .. package.path

local fake_logger = {
    err = spy.new(function() end),
    info = spy.new(function() end),
    dbg = spy.new(function() end),
    warn = spy.new(function() end),
}

package.preload["grimmory/logger"] = function()
    return {
        new = function()
            return fake_logger
        end
    }
end

package.preload["readcollection"] = function()
    return {
        coll = {},
        coll_settings = {},
    }
end

package.preload["ffi/MD5"] = function()
    return {
        sumFile = function() return "" end,
    }
end

package.preload["util"] = function()
    return {
        getFileNameSuffix = function(path)
            return path:match("^.+%.(%w+)$") or ""
        end,
        partialMD5 = function() return "" end,
        fileExists = function() return false end,
        getSafeFilename = function(name) return name end,
        findFiles = function() end,
        makePath = function() return true end,
        removeFile = function() return true end,
        directoryExists = function() return false end,
    }
end

local GrimmorySynchronize = require("grimmory/synchronize")

describe("GrimmorySynchronize", function()
    local fake_settings, fake_repository, fake_api
    local synchronize

    before_each(function()
        fake_settings = {
            getSyncReadingSessions = spy.new(function() return true end),
            getSessionThresholdSeconds = spy.new(function() return 30 end),
            getSessionThresholdPages = spy.new(function() return 0 end),
        }

        fake_repository = {
            getPendingSessions = spy.new(function() return {} end),
            updateBookSyncTimestamp = spy.new(function() return true end),
        }

        fake_api = {
            recordSession = spy.new(function() return true end),
        }

        synchronize = GrimmorySynchronize:new({
            settings = fake_settings,
            repository = fake_repository,
            api = fake_api,
        })
    end)

    describe("pushBookSessions", function()
        it("derives the book type from the file extension instead of hardcoding EPUB", function()
            fake_repository.getPendingSessions = spy.new(function()
                return {
                    {
                        grimmory_id = 42,
                        book_path = "/books/some-comic.cbz",
                        start_time = 1000,
                        end_time = 1100,
                        start_page = 1,
                        end_page = 5,
                        start_progress = 0,
                        end_progress = 10,
                    },
                }
            end)

            synchronize:pushBookSessions(1, function() end)

            assert.spy(fake_api.recordSession).was_called_with(
                match._,
                42,
                "CBZ",
                1000, 1100, 0, 10, "1", "5"
            )
        end)
    end)
end)
