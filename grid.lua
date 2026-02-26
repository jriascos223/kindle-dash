--[[
Grid layout and rendering module for Kindle-Dash
2x3 grid of tiles with header clock bar
--]]

local ffi = require("ffi")

local Grid = {}

-- Layout constants
Grid.COLS = 2
Grid.ROWS = 3
Grid.MARGIN = 20      -- pixels between tiles and screen edges
Grid.BORDER = 2       -- tile border thickness in pixels
Grid.HEADER_H = 80    -- header bar height in pixels

-- Compute pixel bounds {x, y, w, h} for a tile at (col, row), 0-indexed
function Grid.tile_rect(screen_w, screen_h, col, row)
    local usable_w = screen_w - Grid.MARGIN * (Grid.COLS + 1)
    local usable_h = screen_h - Grid.HEADER_H - Grid.MARGIN * (Grid.ROWS + 1)
    local tile_w = math.floor(usable_w / Grid.COLS)
    local tile_h = math.floor(usable_h / Grid.ROWS)
    local x = Grid.MARGIN + col * (tile_w + Grid.MARGIN)
    local y = Grid.HEADER_H + Grid.MARGIN + row * (tile_h + Grid.MARGIN)
    return { x = x, y = y, w = tile_w, h = tile_h }
end

-- Map tap coordinates to (col, row) or nil if outside tiles
function Grid.hit_test(screen_w, screen_h, tx, ty)
    for c = 0, Grid.COLS - 1 do
        for r = 0, Grid.ROWS - 1 do
            local rect = Grid.tile_rect(screen_w, screen_h, c, r)
            if tx >= rect.x and tx < rect.x + rect.w and
               ty >= rect.y and ty < rect.y + rect.h then
                return c, r
            end
        end
    end
    return nil
end

-- Draw a rectangle outline using 4 filled strips
local function draw_rect_border(fbfd, FBInk, cfg, x, y, w, h, thickness, gray)
    local strips = {
        { x = x, y = y, w = w, h = thickness },                                 -- top
        { x = x, y = y + h - thickness, w = w, h = thickness },                 -- bottom
        { x = x, y = y + thickness, w = thickness, h = h - 2 * thickness },     -- left
        { x = x + w - thickness, y = y + thickness, w = thickness, h = h - 2 * thickness }, -- right
    }
    for _, s in ipairs(strips) do
        local rect = ffi.new("FBInkRect")
        rect.left = s.x
        rect.top = s.y
        rect.width = s.w
        rect.height = s.h
        FBInk.fbink_fill_rect_gray(fbfd, cfg, rect, false, gray)
    end
end

-- Draw the clock in the header bar
function Grid.draw_clock(fbfd, FBInk, state)
    local cfg = ffi.new("FBInkConfig")
    cfg.is_centered = true
    cfg.no_refresh = true
    cfg.fontmult = 3
    cfg.fontname = 19  -- TERMINUS

    -- Clear the header area first
    local header_rect = ffi.new("FBInkRect")
    header_rect.left = 0
    header_rect.top = 0
    header_rect.width = state.screen_width
    header_rect.height = Grid.HEADER_H
    FBInk.fbink_cls(fbfd, cfg, header_rect, false)

    -- Reinit with fontmult=3 to get correct font metrics for row positioning
    FBInk.fbink_init(fbfd, cfg)
    local clock_state = ffi.new("FBInkState")
    FBInk.fbink_get_state(cfg, clock_state)

    -- Position clock text vertically centered in header
    local font_h = clock_state.font_h
    if font_h > 0 then
        cfg.row = math.floor((Grid.HEADER_H / 2 - font_h / 2) / font_h)
    else
        cfg.row = 0
    end

    FBInk.fbink_print(fbfd, os.date("%H:%M"), cfg)
end

-- Draw a single tile (border + content)
function Grid.draw_tile(fbfd, FBInk, state, col, row, tile)
    local rect = Grid.tile_rect(state.screen_width, state.screen_height, col, row)
    local cfg = ffi.new("FBInkConfig")
    cfg.no_refresh = true

    -- Draw border (black)
    draw_rect_border(fbfd, FBInk, cfg, rect.x, rect.y, rect.w, rect.h, Grid.BORDER, 0x00)

    -- Clear tile interior
    local inner = ffi.new("FBInkRect")
    inner.left = rect.x + Grid.BORDER
    inner.top = rect.y + Grid.BORDER
    inner.width = rect.w - 2 * Grid.BORDER
    inner.height = rect.h - 2 * Grid.BORDER
    FBInk.fbink_cls(fbfd, cfg, inner, false)

    -- Draw "+" placeholder centered in tile
    local print_cfg = ffi.new("FBInkConfig")
    print_cfg.no_refresh = true
    print_cfg.is_centered = true
    print_cfg.fontmult = 4
    print_cfg.fontname = 19  -- TERMINUS

    -- Get font metrics at this size
    FBInk.fbink_init(fbfd, print_cfg)
    local tile_state = ffi.new("FBInkState")
    FBInk.fbink_get_state(print_cfg, tile_state)

    local font_h = tile_state.font_h
    if font_h > 0 then
        local tile_center_y = rect.y + math.floor(rect.h / 2)
        print_cfg.row = math.floor((tile_center_y - font_h / 2) / font_h)
    end

    local label = "+"
    if tile and tile.label then
        label = tile.label
    end
    FBInk.fbink_print(fbfd, label, print_cfg)
end

-- Full render: clear screen, draw header clock, draw all tiles
function Grid.draw_all(fbfd, FBInk, state, tiles)
    -- Clear entire screen (no refresh)
    local cfg = ffi.new("FBInkConfig")
    cfg.no_refresh = true
    FBInk.fbink_cls(fbfd, cfg, nil, false)

    -- Draw clock
    Grid.draw_clock(fbfd, FBInk, state)

    -- Draw all tiles
    for c = 0, Grid.COLS - 1 do
        for r = 0, Grid.ROWS - 1 do
            local tile = tiles[c] and tiles[c][r] or { type = "empty" }
            Grid.draw_tile(fbfd, FBInk, state, c, r, tile)
        end
    end
end

-- Refresh just the header region
function Grid.refresh_header(fbfd, FBInk, state)
    local cfg = ffi.new("FBInkConfig")
    cfg.wfm_mode = 1  -- WFM_DU
    FBInk.fbink_refresh(fbfd, 0, 0, state.screen_width, Grid.HEADER_H, cfg)
end

-- Refresh a single tile region
function Grid.refresh_tile(fbfd, FBInk, state, col, row)
    local rect = Grid.tile_rect(state.screen_width, state.screen_height, col, row)
    local cfg = ffi.new("FBInkConfig")
    cfg.wfm_mode = 1  -- WFM_DU
    FBInk.fbink_refresh(fbfd, rect.y, rect.x, rect.w, rect.h, cfg)
end

return Grid
