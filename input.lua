--[[
Touch input module for Kindle-Dash
Reads raw touch events from the Linux input subsystem
--]]

local ffi = require("ffi")
local C = ffi.C
local bit = require("bit")

local Input = {}

-- Linux input event constants
local EV_SYN = 0
local EV_ABS = 3
local SYN_REPORT = 0
local ABS_X = 0x00
local ABS_Y = 0x01
local ABS_MT_POSITION_X = 0x35
local ABS_MT_POSITION_Y = 0x36

-- open() flags
local O_RDONLY = 0
local O_NONBLOCK = 2048

local INPUT_EVENT_SIZE = ffi.sizeof("struct input_event")

-- Parse /proc/bus/input/devices to find the touchscreen event device
function Input.find_touch_device()
    local f = io.open("/proc/bus/input/devices", "r")
    if not f then return nil end

    local current_handlers = nil
    local found = false

    for line in f:lines() do
        -- Track the Handlers line for each device block
        local handlers = line:match("^H: Handlers=(.*)")
        if handlers then
            current_handlers = handlers
        end

        -- Look for ABS bitmap with MT position bits
        -- ABS_MT_POSITION_X = 0x35 = bit 53, which is in the second 32-bit word
        -- Bit 53 in second word = bit 21 → 0x200000
        local abs_bits = line:match("^B: ABS=(.*)")
        if abs_bits then
            -- If the bitmap has enough words and the MT bits are set
            -- Also accept single-touch (ABS_X/ABS_Y in first word: bits 0,1 → 0x3)
            local words = {}
            for w in abs_bits:gmatch("%x+") do
                table.insert(words, 1, tonumber(w, 16))  -- reverse order (LSB first)
            end

            -- Check for MT position bits (word index 1, bits for 0x35/0x36)
            if #words >= 2 and bit.band(words[2], 0x600000) ~= 0 then
                found = true
            -- Fallback: check for single-touch ABS_X/ABS_Y
            elseif #words >= 1 and bit.band(words[1], 0x3) ~= 0 then
                found = true
            end

            if found and current_handlers then
                local event_dev = current_handlers:match("event(%d+)")
                if event_dev then
                    f:close()
                    return "/dev/input/event" .. event_dev
                end
            end
            found = false
        end
    end

    f:close()
    return nil
end

-- Open an input device for non-blocking reads
function Input.open(path)
    local fd = C.open(path, bit.bor(O_RDONLY, O_NONBLOCK))
    if fd < 0 then return nil end
    return fd
end

-- Close the input device
function Input.close(fd)
    if fd and fd >= 0 then
        C.close(fd)
    end
end

-- fd_set helpers (for select)
local NFDBITS = ffi.sizeof("unsigned long") * 8

local function FD_ZERO(set)
    ffi.fill(set, ffi.sizeof("fd_set"), 0)
end

local function FD_SET(fd, set)
    local word = math.floor(fd / NFDBITS)
    local bitmask = bit.lshift(1ULL, fd % NFDBITS)
    set.fds_bits[word] = bit.bor(set.fds_bits[word], bitmask)
end

local function FD_ISSET(fd, set)
    local word = math.floor(fd / NFDBITS)
    local bitmask = bit.lshift(1ULL, fd % NFDBITS)
    return bit.band(set.fds_bits[word], bitmask) ~= 0
end

-- Wait for input with timeout. Returns true if data ready, false on timeout.
function Input.wait(fd, timeout_sec)
    local rfds = ffi.new("fd_set")
    FD_ZERO(rfds)
    FD_SET(fd, rfds)

    local tv = ffi.new("struct timeval")
    tv.tv_sec = timeout_sec
    tv.tv_usec = 0

    local ret = C.select(fd + 1, rfds, nil, nil, tv)
    return ret > 0
end

-- Read all pending input events and extract tap coordinates
-- Returns list of {x=N, y=N} for completed touch points
function Input.read_taps(fd)
    local taps = {}
    local cur_x, cur_y = nil, nil
    local buf = ffi.new("struct input_event[16]")

    while true do
        local n = C.read(fd, buf, INPUT_EVENT_SIZE * 16)
        if n <= 0 then break end

        local count = math.floor(n / INPUT_EVENT_SIZE)
        for i = 0, count - 1 do
            local ev = buf[i]
            if ev.type == EV_ABS then
                if ev.code == ABS_MT_POSITION_X or ev.code == ABS_X then
                    cur_x = ev.value
                elseif ev.code == ABS_MT_POSITION_Y or ev.code == ABS_Y then
                    cur_y = ev.value
                end
            elseif ev.type == EV_SYN and ev.code == SYN_REPORT then
                if cur_x and cur_y then
                    table.insert(taps, { x = cur_x, y = cur_y })
                end
                cur_x, cur_y = nil, nil
            end
        end
    end

    return taps
end

-- Drain all pending input events (discard them)
function Input.drain(fd)
    local buf = ffi.new("struct input_event[16]")
    while true do
        local n = C.read(fd, buf, INPUT_EVENT_SIZE * 16)
        if n <= 0 then break end
    end
end

return Input
