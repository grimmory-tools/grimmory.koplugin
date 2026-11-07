local assert = require 'luassert'
local match = require 'luassert.match'
local spy = require 'luassert.spy'
local stub = require 'luassert.stub'

package.path = "grimmory.koplugin/?.lua;" .. package.path

local fake_logger = {
    err = spy.new(function() end),
    info = spy.new(function() end),
    dbg = spy.new(function() end),
}

package.preload["grimmory/logger"] = function()
    return {
        new = function()
            return fake_logger
        end
    }
end

local fake_cache = {}

package.preload["cache"] = function()
    return {
        new = function()
            return {
                get = function(key)
                    return fake_cache[key]
                end,
                insert = function(key, value)
                    fake_cache[key] = value
                end
            }
        end,
    }
end

local fake_doc_settings = {}
local status_cache_update = spy.new(function() end)
package.preload["ui/widget/booklist"] = function()
    return { setBookInfoCacheProperty = status_cache_update }
end

package.preload["docsettings"] = function()
    return {
        open = function()
            return fake_doc_settings
        end
    }
end

package.preload["document/documentregistry"] = function()
    return {
        hasProvider = spy.new(function() return false end),
    }
end

package.preload["util"] = function()
    return {
        partialMD5 = function() return "example" end
    }
end

local GrimmoryDocMetadata = require("grimmory/doc_metadata")

describe("GrimmoryDocMetadata", function()
    describe("setBookReadStatus", function()
        it("mirrors a background update in the active summary without flushing stale document data", function()
            local data = { summary = { status = "reading", note = "keep", rating = 3 }, last_page = 12 }
            local settings = {
                readSetting = function(_, key) return data[key] end,
                saveSetting = spy.new(function(_, key, value) data[key] = value end),
                flush = spy.new(function() end),
            }
            local metadata = GrimmoryDocMetadata:new({
                ui = { document = { file = "active.epub" }, doc_settings = settings },
            })
            assert.is_false(metadata:updateActiveBookReadStatus("other.epub", "abandoned"))
            assert.spy(settings.saveSetting).was_not.called()
            assert.is_true(metadata:updateActiveBookReadStatus("active.epub", "abandoned"))
            assert.same({ status = "abandoned", note = "keep", rating = 3,
                modified = os.date("%Y-%m-%d") }, data.summary)
            assert.equals(12, data.last_page)
            assert.spy(settings.saveSetting).was.called(1)
            assert.spy(settings.flush).was_not.called()
            assert.is_false(metadata:updateActiveBookReadStatus("active.epub", "abandoned"))
            assert.spy(settings.saveSetting).was.called(1)
        end)

        it("preserves summary fields and reading position in the active document", function()
            local data = {
                summary = { status = "reading", rating = 4, note = "Keep this" },
                percent_finished = 0.25, last_page = 42, last_xpointer = "position",
            }
            local settings = {
                readSetting = function(_, key) return data[key] end,
                saveSetting = spy.new(function(_, key, value) data[key] = value end),
                flush = spy.new(function() end),
            }
            local metadata = GrimmoryDocMetadata:new({
                ui = { document = { file = "active.epub" }, doc_settings = settings },
            })
            assert.is_true(metadata:setBookReadStatus("active.epub", "complete"))
            assert.same({ status = "complete", rating = 4, note = "Keep this",
                modified = os.date("%Y-%m-%d") }, data.summary)
            assert.equals(0.25, data.percent_finished)
            assert.equals(42, data.last_page)
            assert.equals("position", data.last_xpointer)
            assert.spy(settings.saveSetting).was.called(1)
            assert.spy(settings.flush).was.called(1)
            assert.spy(status_cache_update).was.called_with("active.epub", "status", "complete")
            assert.is_false(metadata:setBookReadStatus("active.epub", "complete"))
            assert.spy(settings.flush).was.called(1)
        end)

        it("creates a summary for an unopened book", function()
            local settings = {
                readSetting = function() return nil end,
                saveSetting = spy.new(function() end),
                flush = spy.new(function() end),
            }
            local metadata = GrimmoryDocMetadata:new()
            metadata.getDocSettings = function(_, path)
                assert.equals("new.epub", path)
                return settings
            end
            assert.is_true(metadata:setBookReadStatus("new.epub", "complete"))
            assert.spy(settings.saveSetting).was.called_with(settings, "summary", {
                status = "complete", modified = os.date("%Y-%m-%d"),
            })
        end)

        it("persists each supported status and caches it without changing reading position", function()
            for _, status in ipairs({ "complete", "reading", "abandoned" }) do
                local data = { summary = { status = "new", note = "keep", rating = 5 },
                    percent_finished = 0.4, last_page = 10, last_xpointer = "keep-position" }
                local settings = {
                    readSetting = function(_, key) return data[key] end,
                    saveSetting = spy.new(function(_, key, value) data[key] = value end),
                    flush = spy.new(function() end),
                }
                local metadata = GrimmoryDocMetadata:new()
                metadata.getDocSettings = function() return settings end
                assert.is_true(metadata:setBookReadStatus("book.epub", status))
                assert.same({ status = status, note = "keep", rating = 5,
                    modified = os.date("%Y-%m-%d") }, data.summary)
                assert.equals(0.4, data.percent_finished)
                assert.equals(10, data.last_page)
                assert.equals("keep-position", data.last_xpointer)
                assert.spy(status_cache_update).was.called_with("book.epub", "status", status)
                assert.is_false(metadata:setBookReadStatus("book.epub", status))
                assert.spy(settings.flush).was.called(1)
                assert.spy(settings.saveSetting).was.called(1)
            end
        end)

        it("does not clear status for missing or unsupported target values", function()
            local settings = { saveSetting = spy.new(function() end), flush = spy.new(function() end) }
            local metadata = GrimmoryDocMetadata:new()
            metadata.getDocSettings = function() return settings end
            assert.is_false(metadata:setBookReadStatus("book.epub", nil))
            assert.is_false(metadata:setBookReadStatus("book.epub", "new"))
            assert.spy(settings.saveSetting).was_not.called()
            assert.spy(settings.flush).was_not.called()
        end)
    end)

    before_each(function()
        fake_doc_settings["readSetting"] = stub:new({}, "readSetting")
        for key in pairs(fake_cache) do
            fake_cache[key] = nil
        end
    end)

    describe("getIdentifier", function()
        it("reads value", function()
            fake_doc_settings.readSetting
                .on_call_with(match._, "doc_props")
                .returns({
                    identifiers = "foo:bar"
                })

            local metadata = GrimmoryDocMetadata:new()

            local actual = metadata:getIdentifier("example", "foo")
            assert.are.equal("bar", actual)
        end)

        it("allows special characters in key", function()
            fake_doc_settings.readSetting
                .on_call_with(match._, "doc_props")
                .returns({
                    identifiers = "^foo*:b ar:baz"
                })

            local metadata = GrimmoryDocMetadata:new()

            local actual = metadata:getIdentifier("example", "^foo*:b ar")
            assert.are.equal("baz", actual)
        end)

        it("uses last value when duplicates", function()
            fake_doc_settings.readSetting
                .on_call_with(match._, "doc_props")
                .returns({
                    identifiers = "foo:bar\nfoo:baz"
                })

            local metadata = GrimmoryDocMetadata:new()

            local actual = metadata:getIdentifier("example", "foo")
            assert.are.equal("baz", actual)
        end)

        it("handles missing identifiers doc prop", function()
            fake_doc_settings.readSetting
                .on_call_with(match._, "doc_props")
                .returns({})

            local metadata = GrimmoryDocMetadata:new()

            local actual = metadata:getISBN("example")
            assert.are.equal(nil, actual)
        end)
    end)

    describe("getISBN", function()
        it("is nil when no ISBN", function()
            fake_doc_settings.readSetting
                .on_call_with(match._, "doc_props")
                .returns({
                    identifiers = ""
                })

            local metadata = GrimmoryDocMetadata:new()

            local actual = metadata:getISBN("example")
            assert.are.equal(nil, actual)
        end)

        it("reads urn:isbn identifier", function()
            fake_doc_settings.readSetting
                .on_call_with(match._, "doc_props")
                .returns({
                    identifiers = "urn:isbn:1234"
                })

            local metadata = GrimmoryDocMetadata:new()

            local actual = metadata:getISBN("example")
            assert.are.equal("1234", actual)
        end)

        it("prioritizes isbn13 identifier", function()
            fake_doc_settings.readSetting
                .on_call_with(match._, "doc_props")
                .returns({
                    identifiers = "isbn:4567\nisbn13:1234"
                })

            local metadata = GrimmoryDocMetadata:new()

            local actual = metadata:getISBN("example")
            assert.are.equal("1234", actual)
        end)
    end)

    describe("getASIN", function()
        it("reads urn:amazon", function()
            fake_doc_settings.readSetting
                .on_call_with(match._, "doc_props")
                .returns({
                    identifiers = "urn:amazon:ABC123"
                })

            local metadata = GrimmoryDocMetadata:new()

            local actual = metadata:getASIN("example")
            assert.are.equal("ABC123", actual)
        end)

        it("prioritizes amazon over urn:amazon", function()
            fake_doc_settings.readSetting
                .on_call_with(match._, "doc_props")
                .returns({
                    identifiers = "mobi-asin:DEF456\namazon:ABC123"
                })

            local metadata = GrimmoryDocMetadata:new()

            local actual = metadata:getASIN("example")
            assert.are.equal("ABC123", actual)
        end)

        it("reads amazon asin", function()
            fake_doc_settings.readSetting
                .on_call_with(match._, "doc_props")
                .returns({
                    identifiers = "amazon:ABC123"
                })

            local metadata = GrimmoryDocMetadata:new()

            local actual = metadata:getASIN("example")
            assert.are.equal("ABC123", actual)
        end)
    end)
end)
