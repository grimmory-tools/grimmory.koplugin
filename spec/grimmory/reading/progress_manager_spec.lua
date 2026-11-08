local assert = require 'luassert'
local spy = require 'luassert.spy'
local match = require 'luassert.match'

package.path = "grimmory.koplugin/?.lua;" .. package.path

describe("ReadingProgressManager reset boundary", function()
    local manager, reset_at, remote, enabled, saved_preload, saved_loaded
    local names = { "ui/event", "util", "ffi/sha2", "grimmory/logger",
        "grimmory/reading/progress_manager", "grimmory/reading/recorder" }

    before_each(function()
        saved_preload, saved_loaded = {}, {}
        for _, name in ipairs(names) do
            saved_preload[name], saved_loaded[name] = package.preload[name], package.loaded[name]
            package.loaded[name] = nil
        end
        package.preload["ui/event"] = function()
            return { new = function(_, name, value) return { name = name, value = value } end }
        end
        package.preload["util"] = function() return { partialMD5 = function() return "md5" end } end
        package.preload["ffi/sha2"] = function() return { md5 = function(value) return value end } end
        package.preload["grimmory/logger"] = function()
            return { new = function() return { dbg = function() end, err = function() end } end }
        end
        local Manager = require("grimmory/reading/progress_manager")
        local Recorder = require("grimmory/reading/recorder")
        reset_at, enabled = 100, true
        remote = { timestamp = 99, percentage = 0.8, progress = "80", document = "md5" }
        manager = Manager:new({
            settings = { getSyncBookReadStatus = function() return enabled end },
            doc_metadata = { getProgressResetAt = function() return reset_at end },
            api = { getReadingProgress = function() return true, remote end },
            ui = { document = { file = "book.epub", info = { has_pages = true } },
                handleEvent = spy.new(function() end) },
            reading_recorder = Recorder:new({ session_id = 7, session_book_path = "book.epub", last_page = 80 }),
        })
        manager.getCredentials = function() return "user", "secret" end
        manager.reading_recorder.emitSessionEvent = spy.new(function() end)
    end)

    after_each(function()
        for _, name in ipairs(names) do
            package.preload[name], package.loaded[name] = saved_preload[name], saved_loaded[name]
        end
    end)

    it("suppresses old, equal-boundary and missing remote timestamps", function()
        for _, timestamp in ipairs({ 99, 100, false }) do
            remote.timestamp = timestamp or nil
            local _, _, progress = manager:getRemoteProgressForBook("book.epub")
            assert.is_nil(progress)
        end
    end)

    it("accepts fresh remote progress and bypasses the marker when the feature is disabled", function()
        remote.timestamp = 101
        local _, _, fresh = manager:getRemoteProgressForBook("book.epub")
        assert.equals(101, fresh.end_time)
        enabled = false
        remote.timestamp = 99
        local _, _, old = manager:getRemoteProgressForBook("book.epub")
        assert.equals(99, old.end_time)
    end)

    it("on-open comparison ignores historical local progress but accepts fresh remote progress", function()
        manager.getLocalProgressForBook = function()
            return { end_time = 99, end_progress = 80, end_page = 80 }
        end
        remote.timestamp, remote.percentage, remote.progress = 101, 0.1, "10"
        local _, _, fresh = manager:getNewerProgressForBook("book.epub")
        assert.equals(10, fresh.end_page)
        remote.timestamp = 100
        assert.is_nil(manager:getNewerProgressForBook("book.epub"))
    end)

    it("navigates the live book to the beginning without recording the obsolete position", function()
        assert.is_false(manager:resetActiveBookPosition("other.epub"))
        assert.equals(7, manager.reading_recorder.session_id)
        assert.is_true(manager:resetActiveBookPosition("book.epub"))
        assert.spy(manager.ui.handleEvent).was.called_with(manager.ui, { name = "GotoPage", value = 1 })
        assert.spy(manager.reading_recorder.emitSessionEvent).was_not.called()
        assert.is_nil(manager.reading_recorder.session_id)
        assert.is_nil(manager.reading_recorder.last_page)
        assert.is_nil(manager.reading_recorder.session_book_path)
        manager.ui.document.info.has_pages = false
        manager:resetActiveBookPosition("book.epub")
        assert.spy(manager.ui.handleEvent).was.called_with(manager.ui, { name = "GoToPercent", value = 0 })
    end)

    it("still records normal session endings", function()
        manager.reading_recorder:onSessionEnd()
        assert.spy(manager.reading_recorder.emitSessionEvent).was.called(1)
        assert.spy(manager.reading_recorder.emitSessionEvent).was.called_with(
            match._, 7, "session-end")
        assert.is_nil(manager.reading_recorder.session_id)
        assert.is_nil(manager.reading_recorder.session_book_path)
        assert.is_nil(manager.reading_recorder.last_page)
    end)

    it("rejects a stale queued position again at application time", function()
        manager:applyProgress({ book_path = "book.epub", end_time = 100, end_page = 80 })
        assert.spy(manager.ui.handleEvent).was_not.called()
        assert.spy(manager.reading_recorder.emitSessionEvent).was_not.called()
    end)
end)
