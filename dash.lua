#!/usr/bin/env luajit
--[[
Kindle-Dash: Grid-based dashboard with touch input for Kindle e-readers
--]]

-- Set up paths relative to script location
local basedir = debug.getinfo(1, "S").source:match("@?(.*/)") or "./"
package.path = basedir .. "?.lua;" .. basedir .. "ffi/?.lua;" .. package.path
package.cpath = basedir .. "libs/?.so;" .. package.cpath

local ffi = require("ffi")

-- Load FBInk FFI declarations
require("fbink_h")

-- Load FBInk library
local ok, FBInk = pcall(ffi.load, "fbink")
if not ok then
    local paths = {
        "/mnt/us/koreader/libs/libfbink.so",
        "/mnt/us/libfbink.so",
        "/usr/lib/libfbink.so",
    }
    for _, path in ipairs(paths) do
        ok, FBInk = pcall(ffi.load, path)
        if ok then break end
    end
    if not ok then
        io.stderr:write("Error: Could not load libfbink.so\n")
        os.exit(1)
    end
end

print("Loaded FBInk " .. ffi.string(FBInk.fbink_version()))

-- Load modules
local Input = require("input")
local Grid = require("grid")

-- Open framebuffer
local fbfd = FBInk.fbink_open()
if fbfd == -1 then
    io.stderr:write("Error: Failed to open framebuffer\n")
    os.exit(1)
end

-- Initialize FBInk
local init_cfg = ffi.new("FBInkConfig")
init_cfg.fontname = 19  -- TERMINUS
if FBInk.fbink_init(fbfd, init_cfg) < 0 then
    io.stderr:write("Error: Failed to initialize FBInk\n")
    FBInk.fbink_close(fbfd)
    os.exit(1)
end

-- Get device state
local state = ffi.new("FBInkState")
FBInk.fbink_get_state(init_cfg, state)
print(string.format("Device: %s (%dx%d @ %d bpp)",
    ffi.string(state.device_name),
    state.screen_width, state.screen_height,
    state.bpp))

-- Initialize tiles (all empty)
local tiles = {}
for c = 0, Grid.COLS - 1 do
    tiles[c] = {}
    for r = 0, Grid.ROWS - 1 do
        tiles[c][r] = { type = "empty" }
    end
end

-- Find and open touch device
local touch_path = Input.find_touch_device()
local touch_fd = nil
if touch_path then
    print("Touch device: " .. touch_path)
    touch_fd = Input.open(touch_path)
    if not touch_fd then
        print("Warning: Could not open touch device, running without touch input")
    end
else
    print("Warning: No touch device found, running without touch input")
end

-- Initial full render
Grid.draw_all(fbfd, FBInk, state, tiles)

-- Full-screen refresh with GC16 flash for clean start
local refresh_cfg = ffi.new("FBInkConfig")
refresh_cfg.is_flashing = true
refresh_cfg.wfm_mode = 2  -- WFM_GC16
FBInk.fbink_refresh(fbfd, 0, 0, state.screen_width, state.screen_height, refresh_cfg)
FBInk.fbink_wait_for_complete(fbfd, FBInk.fbink_get_last_marker())

print("Dashboard rendered, entering event loop")

-- Handle a tile tap: brief invert for visual feedback
local last_tap_time = 0
local TAP_COOLDOWN_US = 400000  -- 400ms minimum between processed taps

local function handle_tile_tap(col, row)
    -- Cooldown: ignore taps that arrive too soon after the last one
    local now_tv = ffi.new("struct timeval")
    ffi.C.gettimeofday(now_tv, nil)
    local now_us = tonumber(now_tv.tv_sec) * 1000000 + tonumber(now_tv.tv_usec)
    if now_us - last_tap_time < TAP_COOLDOWN_US then
        return
    end
    last_tap_time = now_us

    print(string.format("Tap: tile [%d,%d]", col, row))

    local ok, err = pcall(function()
        local rect = Grid.tile_rect(state.screen_width, state.screen_height, col, row)

        -- Invert the tile region for visual feedback
        local inv_rect = ffi.new("FBInkRect")
        inv_rect.left = rect.x
        inv_rect.top = rect.y
        inv_rect.width = rect.w
        inv_rect.height = rect.h

        local inv_cfg = ffi.new("FBInkConfig")
        inv_cfg.is_nightmode = true
        inv_cfg.no_refresh = true
        FBInk.fbink_cls(fbfd, inv_cfg, inv_rect, false)
        Grid.refresh_tile(fbfd, FBInk, state, col, row)

        -- Brief pause then redraw normal
        ffi.C.select(0, nil, nil, nil, ffi.new("struct timeval", { tv_sec = 0, tv_usec = 150000 }))

        -- Redraw the tile normally
        Grid.draw_tile(fbfd, FBInk, state, col, row, tiles[col][row])
        Grid.refresh_tile(fbfd, FBInk, state, col, row)
    end)
    if not ok then
        io.stderr:write("Warning: tap handler error: " .. tostring(err) .. "\n")
    end
end

-- Event loop
local CLOCK_INTERVAL = 30  -- seconds
local running = true

while running do
    local has_input = false
    if touch_fd then
        has_input = Input.wait(touch_fd, CLOCK_INTERVAL)
    else
        -- No touch device: just sleep for clock interval
        ffi.C.select(0, nil, nil, nil, ffi.new("struct timeval", { tv_sec = CLOCK_INTERVAL, tv_usec = 0 }))
    end

    if has_input and touch_fd then
        local taps = Input.read_taps(touch_fd)
        -- Only handle the last tap to debounce rapid input
        if #taps > 0 then
            local tap = taps[#taps]
            local col, row = Grid.hit_test(state.screen_width, state.screen_height, tap.x, tap.y)
            if col then
                handle_tile_tap(col, row)
            end
            -- Drain any events that arrived during the tap animation
            Input.drain(touch_fd)
        end
    else
        -- Timeout: update clock
        Grid.draw_clock(fbfd, FBInk, state)
        Grid.refresh_header(fbfd, FBInk, state)
    end
end

-- Cleanup
if touch_fd then Input.close(touch_fd) end
FBInk.fbink_close(fbfd)
