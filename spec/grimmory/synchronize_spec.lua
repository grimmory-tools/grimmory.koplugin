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

-- Paths considered to exist on disk by the fake `util.fileExists` below,
-- reset before each test.
local existing_files = {}

package.preload["util"] = function()
    return {
        getFileNameSuffix = function(path)
            return path:match("^.+%.(%w+)$") or ""
        end,
        partialMD5 = function() return "" end,
        fileExists = function(path) return existing_files[path] == true end,
        getSafeFilename = function(name) return name end,
        findFiles = function() end,
        makePath = function() return true end,
        removeFile = function() return true end,
        directoryExists = function() return false end,
    }
end

local GrimmorySynchronize = require("grimmory/synchronize")

---@param book_list table iterated once per call, mirrors GrimmoryAPI:getBooks()
local function fakeGetBooksIterator(book_list)
    local index = 0
    return function()
        index = index + 1
        return book_list[index]
    end
end

describe("GrimmorySynchronize", function()
    local fake_settings, fake_repository, fake_api, fake_doc_metadata
    local synchronize
    local callback

    before_each(function()
        existing_files = {}

        fake_settings = {
            getSyncReadingSessions = spy.new(function() return true end),
            getSyncReadingProgress = spy.new(function() return true end),
            getSessionThresholdSeconds = spy.new(function() return 30 end),
            getSessionThresholdPages = spy.new(function() return 0 end),
            getDownloadDirectory = spy.new(function() return "/downloads" end),
        }

        fake_repository = {
            getPendingSessions = spy.new(function() return {} end),
            updateBookSyncTimestamp = spy.new(function() return true end),
            getUnlinkedBooksWithEvents = spy.new(function() return {} end),
            getUnlinkedBooks = spy.new(function() return {} end),
            upsertBook = spy.new(function() return true end),
            findBooksByGrimmoryId = spy.new(function() return true, {} end),
        }

        fake_api = {
            recordSession = spy.new(function() return true end),
            getBooks = spy.new(function() return fakeGetBooksIterator({}) end),
        }

        fake_doc_metadata = {
            isBook = spy.new(function() return false end),
        }

        synchronize = GrimmorySynchronize:new({
            settings = fake_settings,
            repository = fake_repository,
            api = fake_api,
            doc_metadata = fake_doc_metadata,
        })

        callback = spy.new(function() end)
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

            synchronize:pushBookSessions(1, callback)

            assert.spy(fake_api.recordSession).was_called_with(
                match._,
                42,
                "CBZ",
                1000, 1100, 0, 10, "1", "5"
            )
        end)

        it("skips pending sessions once when book isn't linked, without erroring per-session", function()
            fake_repository.getPendingSessions = spy.new(function()
                return {
                    {
                        grimmory_id = nil,
                        book_path = "/books/unlinked.epub",
                        start_time = 1000,
                        end_time = 1100,
                        start_page = 1,
                        end_page = 5,
                        start_progress = 0,
                        end_progress = 10,
                    },
                    {
                        grimmory_id = nil,
                        book_path = "/books/unlinked.epub",
                        start_time = 1200,
                        end_time = 1300,
                        start_page = 5,
                        end_page = 9,
                        start_progress = 10,
                        end_progress = 20,
                    },
                }
            end)

            synchronize:pushBookSessions(1, callback)

            assert.spy(fake_api.recordSession).was_not_called()
            assert.spy(callback).was_called(1)
            assert.spy(callback).was_called_with(match.same({
                state = "session-unlinked",
                bookPath = "/books/unlinked.epub",
            }))
        end)

        it("still records sessions normally once a book is linked", function()
            fake_repository.getPendingSessions = spy.new(function()
                return {
                    {
                        grimmory_id = 7,
                        book_path = "/books/linked.epub",
                        start_time = 1000,
                        end_time = 1100,
                        start_page = 1,
                        end_page = 5,
                        start_progress = 0,
                        end_progress = 10,
                    },
                }
            end)

            synchronize:pushBookSessions(1, callback)

            assert.spy(fake_api.recordSession).was_called(1)
            assert.spy(fake_repository.updateBookSyncTimestamp).was_called_with(match._, 1, "sessions", 1100)
        end)
    end)

    describe("associateUnlinkedBooks", function()
        it("does nothing when there are no unlinked books", function()
            synchronize:associateUnlinkedBooks(callback)

            assert.spy(fake_api.getBooks).was_not_called()
            assert.spy(callback).was_not_called()
        end)

        it("fetches the remote catalog once and links matching books", function()
            fake_repository.getUnlinkedBooksWithEvents = spy.new(function()
                return {
                    { id = 1, book_path = "/books/a.epub" },
                    { id = 2, book_path = "/books/b.epub" },
                }
            end)

            local remote_book_a = { id = 100 }
            local remote_book_b = { id = 200 }

            fake_api.getBooks = spy.new(function()
                return fakeGetBooksIterator({ remote_book_a, remote_book_b })
            end)

            fake_doc_metadata.isBook = spy.new(function(_, path, book)
                if path == "/books/a.epub" then
                    return book == remote_book_a
                end
                if path == "/books/b.epub" then
                    return book == remote_book_b
                end
                return false
            end)

            synchronize:associateUnlinkedBooks(callback)

            -- The catalog should only be fetched once, even though there
            -- are two unlinked local books to match against it.
            assert.spy(fake_api.getBooks).was_called(1)

            assert.spy(fake_repository.upsertBook).was_called_with(match._, "/books/a.epub", 100)
            assert.spy(fake_repository.upsertBook).was_called_with(match._, "/books/b.epub", 200)

            assert.spy(callback).was_called(2)
            assert.spy(callback).was_called_with(match.same({
                state = "book-linked",
                book_id = 1,
                book_path = "/books/a.epub",
                grimmory_id = 100,
            }))
            assert.spy(callback).was_called_with(match.same({
                state = "book-linked",
                book_id = 2,
                book_path = "/books/b.epub",
                grimmory_id = 200,
            }))
        end)

        it("does not call the callback for unlinked books that still have no match", function()
            fake_repository.getUnlinkedBooksWithEvents = spy.new(function()
                return {
                    { id = 1, book_path = "/books/unknown.epub" },
                }
            end)

            fake_doc_metadata.isBook = spy.new(function() return false end)

            synchronize:associateUnlinkedBooks(callback)

            assert.spy(fake_repository.upsertBook).was_not_called()
            assert.spy(callback).was_not_called()
        end)
    end)

    describe("pushAllPendingBookMetadata", function()
        it("still syncs already-linked books when associateUnlinkedBooks fails", function()
            fake_repository.getUnlinkedBooksWithEvents = spy.new(function()
                return { { id = 1, book_path = "/books/a.epub" } }
            end)

            -- Simulate a failure while trying to reach the remote catalog
            -- (e.g. a network error mid-pagination), which associateBook
            -- would otherwise raise via `error(...)`.
            fake_api.getBooks = spy.new(function()
                error("network error")
            end)

            fake_repository.getBooksPendingSync = spy.new(function() return { 42 } end)

            synchronize:pushAllPendingBookMetadata(callback)

            assert.spy(fake_repository.getBooksPendingSync).was_called(1)
            assert.spy(callback).was_called_with(match.same({
                state = "push-book-metadata",
                book_id = 42,
                pushed_books = 1,
                total_books = 1,
            }))
        end)
    end)

    describe("getBookDownloadPath", function()
        local remote_book

        before_each(function()
            remote_book = {
                id = 734,
                primary_file = { filename = "Norte & Sul.epub" },
            }
        end)

        it("reuses a previously downloaded file tracked for this grimmory_id", function()
            existing_files["/downloads/existing.epub"] = true

            fake_repository.findBooksByGrimmoryId = spy.new(function()
                return true, { { book_path = "/downloads/existing.epub", book_md5 = "" } }
            end)

            local download_path = synchronize:getBookDownloadPath(remote_book)

            assert.equal("/downloads/existing.epub", download_path)
        end)

        it("reuses a local file already on disk under a different name/path", function()
            existing_files["/mnt/us/calibre/Some Other Name.epub"] = true

            fake_repository.getUnlinkedBooks = spy.new(function()
                return {
                    { id = 1, book_path = "/mnt/us/calibre/Some Other Name.epub" },
                }
            end)

            fake_doc_metadata.isBook = spy.new(function(_, path, book)
                return path == "/mnt/us/calibre/Some Other Name.epub" and book == remote_book
            end)

            local download_path = synchronize:getBookDownloadPath(remote_book)

            assert.equal("/mnt/us/calibre/Some Other Name.epub", download_path)
        end)

        it("falls back to a fresh download path when there is no local match", function()
            local download_path = synchronize:getBookDownloadPath(remote_book)

            assert.equal("/downloads/Norte & Sul.epub", download_path)
        end)
    end)
end)
