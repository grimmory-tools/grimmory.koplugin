local assert = require 'luassert'
local spy = require 'luassert.spy'

package.path = "grimmory.koplugin/?.lua;" .. package.path

package.preload["readcollection"] = function()
    return {}
end

package.preload["ffi/MD5"] = function()
    return {
        sumFile = function() return "md5" end,
    }
end

package.preload["util"] = function()
    return {}
end

package.preload["grimmory/logger"] = function()
    return {
        new = function()
            return {
                err = spy.new(function() end),
                warn = spy.new(function() end),
                info = spy.new(function() end),
                dbg = spy.new(function() end),
            }
        end
    }
end

local GrimmorySynchronize = require("grimmory/synchronize")

local function synchronizerWithLibraries(target_libraries)
    return GrimmorySynchronize:new({
        settings = {
            getDownloadTargetLibraries = function()
                return target_libraries
            end,
            getDownloadTargetShelves = function()
                return {}
            end,
        },
    })
end

describe("GrimmorySynchronize", function()
    describe("isTargetBook", function()
        it("keeps existing all-library behavior when no target libraries are configured", function()
            local synchronizer = synchronizerWithLibraries({})

            local result = synchronizer:isTargetBook({
                primary_file = {
                    filename = "Example.epub",
                },
                library_id = 99,
            })

            assert.are.equal(true, result)
        end)

        it("allows books from selected libraries", function()
            local synchronizer = synchronizerWithLibraries({
                {
                    id = 3,
                    name = "Ebooks",
                },
            })

            local result = synchronizer:isTargetBook({
                primary_file = {
                    filename = "Example.epub",
                },
                library_id = 3,
            })

            assert.are.equal(true, result)
        end)

        it("skips books from unselected libraries", function()
            local synchronizer = synchronizerWithLibraries({
                {
                    id = 3,
                    name = "Ebooks",
                },
            })

            local result = synchronizer:isTargetBook({
                primary_file = {
                    filename = "Example.m4b",
                },
                library_id = 4,
            })

            assert.are.equal(false, result)
        end)
    end)

    describe("isTargetLibrary", function()
        it("treats all libraries as target when no target libraries are configured", function()
            local synchronizer = synchronizerWithLibraries({})

            local result = synchronizer:isTargetLibrary({
                library_id = 4,
            })

            assert.are.equal(true, result)
        end)

        it("skips books with missing library IDs when target libraries are configured", function()
            local synchronizer = synchronizerWithLibraries({
                {
                    id = 3,
                    name = "Ebooks",
                },
            })

            local result = synchronizer:isTargetLibrary({})

            assert.are.equal(false, result)
        end)
    end)
end)
