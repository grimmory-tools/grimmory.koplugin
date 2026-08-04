local Version = {}

local function number(value)
    return tonumber(value) or 0
end

--- Parse upstream and fork components from tags such as v.0.0.31-hC-0.0.1.
function Version.parse(value)
    local text = tostring(value or "")
    local major, minor, patch, fork_major, fork_minor, fork_patch
    major, minor, patch, fork_major, fork_minor, fork_patch = text:match("^v%.(%d+)%.(%d+)%.(%d+)-hC-(%d+)%.(%d+)%.(%d+)$")
    if not major then major, minor, patch, fork_major, fork_minor, fork_patch = text:match("^v?([0-9]+)%.([0-9]+)%.([0-9]+)-hC-(%d+)%.(%d+)%.(%d+)$") end
    if not major then major, minor, patch = text:match("^v?([0-9]+)%.([0-9]+)%.([0-9]+)$") end
    if not major and (text == "0.0.0-snapshot" or text == "v0.0.0-snapshot") then
        major, minor, patch = "0", "0", "0"
    end
    if not major then
        return { valid = false, major = 0, minor = 0, patch = 0, fork_major = 0, fork_minor = 0, fork_patch = 0 }
    end
    return {
        major = number(major), minor = number(minor), patch = number(patch),
        fork_major = number(fork_major), fork_minor = number(fork_minor), fork_patch = number(fork_patch),
        valid = true,
    }
end

function Version.compare(a, b)
    local left, right = Version.parse(a), Version.parse(b)
    if not left.valid or not right.valid then return 0 end
    for _, field in ipairs({ "major", "minor", "patch", "fork_major", "fork_minor", "fork_patch" }) do
        if left[field] ~= right[field] then
            return left[field] < right[field] and -1 or 1
        end
    end
    return 0
end

function Version.isLater(current, candidate)
    if not Version.parse(candidate).valid then return false end
    return Version.compare(current, candidate) < 0
end

return Version
