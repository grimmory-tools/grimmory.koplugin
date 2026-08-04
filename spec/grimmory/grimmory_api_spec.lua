local assert = require 'luassert'
local spy = require 'luassert.spy'

package.path = "grimmory.koplugin/?.lua;" .. package.path

local original_plugin_metadata_preload = package.preload["grimmory/plugin_metadata"]
local original_plugin_metadata_loaded = package.loaded["grimmory/plugin_metadata"]
local original_gettext_preload = package.preload["gettext"]
local original_gettext_loaded = package.loaded["gettext"]
local original_logger_preload = package.preload["grimmory/logger"]
local original_logger_loaded = package.loaded["grimmory/logger"]
local original_api_loaded = package.loaded["grimmory/grimmory_api"]
local dependency_names = { "socket.http", "ssl.https", "json", "ltn12" }
local original_dependency_preload = {}
local original_dependency_loaded = {}
for _, name in ipairs(dependency_names) do
    original_dependency_preload[name] = package.preload[name]
    original_dependency_loaded[name] = package.loaded[name]
end

package.preload["socket.http"] = function()
    return {}
end

package.preload["ssl.https"] = function()
    return {}
end

package.preload["json"] = function()
    return {
        encode = function() return "" end,
        decode = function() return {} end,
    }
end

package.preload["ltn12"] = function()
    return {
        source = {
            string = function() return function() end end,
        },
        sink = {
            table = function() return function() end end,
            file = function() return function() end end,
        },
    }
end

package.preload["gettext"] = function()
    return function(text) return text end
end

package.preload["grimmory/logger"] = function()
    return {
        new = function()
            return {
                err = spy.new(function() end),
                warn = spy.new(function() end),
                dbg = spy.new(function() end),
            }
        end
    }
end

package.preload["grimmory/plugin_metadata"] = function()
    return {
        getVersion = function() return "0.0.0-test" end,
        getRepository = function() return "test/repo" end,
    }
end

package.loaded["grimmory/plugin_metadata"] = nil
package.loaded["grimmory/logger"] = nil
package.loaded["gettext"] = nil
package.loaded["grimmory/grimmory_api"] = nil
for _, name in ipairs(dependency_names) do
    package.loaded[name] = nil
end
local GrimmoryAPI = require("grimmory/grimmory_api")

package.preload["grimmory/plugin_metadata"] = original_plugin_metadata_preload
package.loaded["grimmory/plugin_metadata"] = original_plugin_metadata_loaded
package.preload["gettext"] = original_gettext_preload
package.loaded["gettext"] = original_gettext_loaded
package.preload["grimmory/logger"] = original_logger_preload
package.loaded["grimmory/logger"] = original_logger_loaded
package.loaded["grimmory/grimmory_api"] = original_api_loaded
for _, name in ipairs(dependency_names) do
    package.preload[name] = original_dependency_preload[name]
    package.loaded[name] = original_dependency_loaded[name]
end

describe("GrimmoryAPI", function()
    describe("getBooks", function()
        it("parses library fields from paged books", function()
            local api = GrimmoryAPI:new()

            function api:request(_, path)
                assert.are.equal("/api/v1/books/page?sort=addedOn&page=0", path)
                return true, 200, {
                    content = {
                        {
                            id = 10,
                            libraryId = 3,
                            libraryName = "Ebooks",
                            addedOn = "2026-01-01T00:00:00Z",
                            shelves = {},
                            metadata = {},
                            primaryFile = {
                                fileName = "Example.epub",
                            },
                        },
                    },
                    page = {
                        totalElements = 1,
                    },
                }
            end

            local ok, books, total = api:getBooksPage(0)

            assert.are.equal(true, ok)
            assert.are.equal(1, total)
            assert.are.equal(3, books[1].library_id)
            assert.are.equal("Ebooks", books[1].library_name)
        end)

        it("iterates parsed books", function()
            local api = GrimmoryAPI:new()

            function api:getBooksPage(page_number)
                if page_number > 0 then
                    return true, {}, 1
                end

                return true, {
                    {
                        id = 10,
                        library_id = 3,
                        library_name = "Ebooks",
                        shelves = {},
                        metadata = {},
                        primary_file = {
                            filename = "Example.epub",
                        },
                    }
                }, 1
            end

            local nextBook = api:getBooks()
            local book = nextBook()

            assert.are.equal(3, book.library_id)
            assert.are.equal("Ebooks", book.library_name)
        end)
    end)

    describe("getLibraries", function()
        it("reads app library summaries", function()
            local api = GrimmoryAPI:new()

            function api:request(_, path)
                assert.are.equal("/api/v1/app/libraries", path)
                return true, 200, {
                    {
                        id = 3,
                        name = "Ebooks",
                        bookCount = 42,
                    },
                }
            end

            local ok, libraries = api:getLibraries()

            assert.are.equal(true, ok)
            assert.are.equal(3, libraries[1].id)
            assert.are.equal("Ebooks", libraries[1].name)
            assert.are.equal(42, libraries[1].book_count)
        end)

        it("falls back to base libraries endpoint", function()
            local api = GrimmoryAPI:new()
            local paths = {}

            function api:request(_, path)
                table.insert(paths, path)
                if path == "/api/v1/app/libraries" then
                    return false, 404, "Not Found"
                end

                return true, 200, {
                    {
                        id = 4,
                        name = "Archive",
                    },
                }
            end

            local ok, libraries = api:getLibraries()

            assert.are.equal(true, ok)
            assert.are.same({ "/api/v1/app/libraries", "/api/v1/libraries" }, paths)
            assert.are.equal(4, libraries[1].id)
            assert.are.equal("Archive", libraries[1].name)
        end)
    end)
end)
