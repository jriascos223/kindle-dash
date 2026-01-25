#!/usr/bin/env luajit
--[[
Kindle-Dash: Display a banner on the e-ink screen using FBInk
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
    -- Try common paths on Kindle
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

-- Open framebuffer
local fbfd = FBInk.fbink_open()
if fbfd == -1 then
    io.stderr:write("Error: Failed to open framebuffer\n")
    os.exit(1)
end

-- Create config for centered text
local cfg = ffi.new("FBInkConfig")
cfg.is_centered = true
cfg.is_cleared = true      -- clear screen first
cfg.is_flashing = true     -- full refresh for clean display

-- Initialize FBInk
if FBInk.fbink_init(fbfd, cfg) < 0 then
    io.stderr:write("Error: Failed to initialize FBInk\n")
    FBInk.fbink_close(fbfd)
    os.exit(1)
end

-- Get device state for info
local state = ffi.new("FBInkState")
FBInk.fbink_get_state(cfg, state)
print(string.format("Device: %s (%dx%d @ %d bpp)",
    ffi.string(state.device_name),
    state.screen_width, state.screen_height,
    state.bpp))

-- Clear the screen
FBInk.fbink_cls(fbfd, cfg, nil, false)

-- Configure for banner display
local banner_cfg = ffi.new("FBInkConfig")
banner_cfg.is_centered = true
banner_cfg.fontmult = 2           -- 2x font size
banner_cfg.fontname = 19          -- TERMINUS font (clear, readable)

-- Print the banner lines
local banner = {
    " _  ___           _ _        ",
    "| |/ (_)         | | |       ",
    "| ' / _ _ __   __| | | ___   ",
    "|  < | | '_ \\ / _` | |/ _ \\  ",
    "| . \\| | | | | (_| | |  __/  ",
    "|_|\\_\\_|_| |_|\\__,_|_|\\___|  ",
    "",
    "        DASH                 ",
}

-- Calculate starting row to center vertically
local start_row = math.floor((state.max_rows - #banner) / 2)
banner_cfg.row = start_row

for i, line in ipairs(banner) do
    banner_cfg.row = start_row + i - 1
    banner_cfg.no_refresh = (i < #banner)  -- only refresh on last line
    FBInk.fbink_print(fbfd, line, banner_cfg)
end

-- Print timestamp at bottom
local time_cfg = ffi.new("FBInkConfig")
time_cfg.is_centered = true
time_cfg.row = -2  -- second to last row
time_cfg.fontname = 19
FBInk.fbink_print(fbfd, os.date("%Y-%m-%d %H:%M:%S"), time_cfg)

-- Wait for the refresh to complete
FBInk.fbink_wait_for_complete(fbfd, FBInk.fbink_get_last_marker())

print("Banner displayed successfully")

-- Cleanup
FBInk.fbink_close(fbfd)
