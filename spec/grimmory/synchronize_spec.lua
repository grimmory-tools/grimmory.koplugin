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

describe("GrimmorySynchronize", function()
    describe("book read status", function()
        local synchronizer, progress, callback, remote_status, enabled, remote_ok
        local original_partial_md5
        before_each(function()
            local util = require("util")
            original_partial_md5 = util.partialMD5
            util.partialMD5 = function() return "md5" end
            remote_status, enabled, remote_ok = "READ", true, true
            progress = { book_path = "book.epub", book_md5 = "md5", grimmory_id = 7, end_time = 20 }
            callback = spy.new(function() end)
            synchronizer = GrimmorySynchronize:new({
                settings = {
                    getSyncBookReadStatus = function() return enabled end,
                    getSyncReadingProgress = function() return true end,
                    getSyncReadingSessions = function() return true end,
                    getSessionThresholdPages = function() return 0 end,
                    getSessionThresholdSeconds = function() return 0 end,
                    getDownloadsBooks = function() return false end,
                },
                repository = {
                    getReadingProgress = function() return true, progress end,
                    getBookSyncTimestamp = function() return true, 10 end,
                    upsertBook = spy.new(function() return true, 1, 7 end),
                    updateBookSyncTimestamp = spy.new(function() end),
                    getPendingSessions = function() return { {
                        book_path = "book.epub", grimmory_id = 7,
                        start_time = 1, end_time = 20, start_page = 1, end_page = 2,
                    } } end,
                    findBooksByGrimmoryId = function()
                        return true, { { book_path = "book.epub", book_md5 = "md5" } }
                    end,
                },
                api = {
                    getBook = spy.new(function()
                        return remote_ok, remote_ok and { id = 7, read_status = remote_status } or nil
                    end),
                    recordSession = spy.new(function() return true end),
                    getBooks = function()
                        local done = false
                        return function()
                            if done then return nil end
                            done = true
                            return { id = 7, read_status = remote_status }
                        end
                    end,
                },
                doc_metadata = { setBookReadStatus = spy.new(function() return true end) },
                reading_progress_manager = { pushRemoteProgress = spy.new(function() return true end) },
            })
        end)

        after_each(function()
            require("util").partialMD5 = original_partial_md5
        end)

        it("defers historical progress when the file was replaced without marking the replacement finished", function()
            require("util").partialMD5 = function() return "replacement-md5" end
            synchronizer:pushBookProgress(1, callback)
            assert.spy(synchronizer.repository.upsertBook).was_not.called()
            assert.spy(synchronizer.api.getBook).was_not.called()
            assert.spy(synchronizer.doc_metadata.setBookReadStatus).was_not.called()
            assert.spy(synchronizer.reading_progress_manager.pushRemoteProgress).was_not.called()
            assert.spy(synchronizer.repository.updateBookSyncTimestamp).was_not.called()
        end)

        it("protects Read before uploading progress while still uploading sessions", function()
            synchronizer:pushBookMetadata(1, callback)
            assert.spy(synchronizer.repository.upsertBook).was_not.called()
            assert.spy(synchronizer.api.getBook).was.called_with(synchronizer.api, 7)
            assert.spy(synchronizer.doc_metadata.setBookReadStatus).was.called_with(
                synchronizer.doc_metadata, "book.epub", "complete")
            assert.spy(synchronizer.reading_progress_manager.pushRemoteProgress).was_not.called()
            assert.spy(synchronizer.api.recordSession).was.called(1)
            assert.spy(synchronizer.repository.updateBookSyncTimestamp).was.called_with(
                synchronizer.repository, 1, "sessions", 20)
        end)

        it("protects rereading, paused and abandoned statuses while uploading sessions", function()
            for _, status in ipairs({ "RE_READING", "PAUSED", "ABANDONED" }) do
                remote_status = status
                synchronizer:pushBookMetadata(1, callback)
            end
            assert.spy(synchronizer.reading_progress_manager.pushRemoteProgress).was_not.called()
            assert.spy(synchronizer.api.recordSession).was.called(3)
            assert.spy(synchronizer.repository.updateBookSyncTimestamp).was.called(3)
        end)

        it("allows normal Reading progress to upload through completion", function()
            remote_status = "READING"
            progress.end_progress = 100
            synchronizer:pushBookProgress(1, callback)
            assert.spy(synchronizer.doc_metadata.setBookReadStatus).was.called_with(
                synchronizer.doc_metadata, "book.epub", "reading")
            assert.spy(synchronizer.reading_progress_manager.pushRemoteProgress).was.called_with(
                synchronizer.reading_progress_manager, progress)
            assert.spy(synchronizer.repository.updateBookSyncTimestamp).was.called_with(
                synchronizer.repository, 1, "progress", 20)
        end)

        it("maps all supported remote states and emits their actual target status", function()
            local cases = {
                { "READ", "complete" }, { "READING", "reading" }, { "RE_READING", "reading" },
                { "PAUSED", "abandoned" }, { "ABANDONED", "abandoned" },
            }
            for _, case in ipairs(cases) do
                synchronizer:applyBookReadStatus("book.epub", { read_status = case[1] }, callback)
                assert.spy(synchronizer.doc_metadata.setBookReadStatus).was.called_with(
                    synchronizer.doc_metadata, "book.epub", case[2])
                assert.spy(callback).was.called_with({
                    state = "book-status-updated", book_path = "book.epub", status = case[2],
                })
            end
            assert.spy(synchronizer.doc_metadata.setBookReadStatus).was.called(5)
        end)

        it("emits no update when the local status already matches", function()
            synchronizer.doc_metadata.setBookReadStatus = function() return false end
            synchronizer:applyBookReadStatus("book.epub", { read_status = "PAUSED" }, callback)
            assert.spy(callback).was_not.called()
        end)

        it("keeps progress pending when status lookup fails", function()
            remote_ok = false
            synchronizer:pushBookProgress(1, callback)
            assert.spy(synchronizer.reading_progress_manager.pushRemoteProgress).was_not.called()
            assert.spy(synchronizer.repository.updateBookSyncTimestamp).was_not.called()
        end)

        it("uploads normal progress without changing status for all other statuses", function()
            for _, status in ipairs({ "UNREAD", "PARTIALLY_READ", "WONT_READ", "UNSET", "unknown", false }) do
                remote_status = status
                synchronizer:pushBookProgress(1, callback)
            end
            assert.spy(synchronizer.reading_progress_manager.pushRemoteProgress).was.called(6)
            synchronizer:applyBookReadStatus("book.epub", {}, callback)
            assert.spy(synchronizer.doc_metadata.setBookReadStatus).was_not.called()
        end)

        it("does not retrieve or apply status when disabled", function()
            enabled = false
            synchronizer:pushBookProgress(1, callback)
            synchronizer:pullBookReadStatus("book.epub", 7, callback)
            synchronizer:pullBooks(callback)
            assert.spy(synchronizer.api.getBook).was_not.called()
            assert.spy(synchronizer.doc_metadata.setBookReadStatus).was_not.called()
            assert.spy(synchronizer.reading_progress_manager.pushRemoteProgress).was.called(1)
        end)

        it("updates known books with downloads and reading progress disabled", function()
            remote_status = "PAUSED"
            local util = require("util")
            local old_exists, old_md5 = util.fileExists, util.partialMD5
            util.fileExists = function() return true end
            util.partialMD5 = function() return "md5" end
            synchronizer.settings.getSyncReadingProgress = function() return false end
            synchronizer:pullBooks(callback)
            util.fileExists, util.partialMD5 = old_exists, old_md5
            assert.spy(synchronizer.doc_metadata.setBookReadStatus).was.called_with(
                synchronizer.doc_metadata, "book.epub", "abandoned")
            assert.spy(callback).was.called_with({
                state = "book-status-updated", book_path = "book.epub", status = "abandoned",
            })
        end)

        it("applies status to existing and newly downloaded books", function()
            local util = require("util")
            local old_exists = util.fileExists
            for _, exists in ipairs({ true, false }) do
                util.fileExists = function() return exists end
                synchronizer.getBookDownloadPath = function() return "book.epub" end
                synchronizer.downloadBook = function() return true end
                synchronizer.associateWithShelves = function() end
                synchronizer.pullBookProgress = function() end
                local path, downloaded = synchronizer:pullBook({ id = 7, read_status = "RE_READING" }, callback)
                assert.equals("book.epub", path)
                assert.equals(not exists, downloaded)
            end
            util.fileExists = old_exists
            assert.spy(synchronizer.doc_metadata.setBookReadStatus).was.called(2)
            assert.spy(synchronizer.doc_metadata.setBookReadStatus).was.called_with(
                synchronizer.doc_metadata, "book.epub", "reading")
        end)

        it("pulls status during individual sync even without reading progress", function()
            remote_status = "ABANDONED"
            synchronizer.checkForHealthyServer = function() return true end
            synchronizer.pushBookAnnotations = function() end
            synchronizer.pullBookAnnotations = function() end
            synchronizer.settings.getSyncReadingProgress = function() return false end
            synchronizer.pullBookProgress = function() end
            synchronizer:synchronizeBook("book.epub", false, callback)
            assert.spy(synchronizer.doc_metadata.setBookReadStatus).was.called_with(
                synchronizer.doc_metadata, "book.epub", "abandoned")
            assert.spy(synchronizer.reading_progress_manager.pushRemoteProgress).was_not.called()
        end)

        it("finishes individual sync with the server status after progress completes a Reading book", function()
            remote_status = "READING"
            progress.end_progress = 100
            local local_status = "complete"
            local updates = {}
            synchronizer.doc_metadata.setBookReadStatus = function(_, _, status)
                local_status = status
                table.insert(updates, status)
                return true
            end
            synchronizer.checkForHealthyServer = function() return true end
            synchronizer.pushBookAnnotations = function() end
            synchronizer.pullBookAnnotations = function() end
            synchronizer.pullBookProgress = function() end
            synchronizer.reading_progress_manager.pushRemoteProgress = spy.new(function(_, pending)
                assert.equals(100, pending.end_progress)
                assert.equals("reading", local_status)
                remote_status = "READ"
                return true
            end)

            synchronizer:synchronizeBook("book.epub", false, callback)

            assert.equals("complete", local_status)
            assert.same({ "reading", "complete" }, updates)
            assert.spy(synchronizer.api.getBook).was.called(2)
            assert.spy(synchronizer.reading_progress_manager.pushRemoteProgress).was.called(1)
            assert.spy(callback).was.called_with({
                state = "book-status-updated", book_path = "book.epub", status = "complete",
            })
        end)
    end)

end)
