-- Skyrim-style HUD widget for conky (Cairo)
require 'cairo'
local ok_xlib = pcall(require, 'cairo_xlib')

local W = 380                      -- canvas width (matches minimum_width)

-- palette
local BONE  = {0.91, 0.87, 0.78}
local DIM   = {0.62, 0.58, 0.50}
local GOLD  = {0.78, 0.66, 0.42}
local SHADE = {0, 0, 0}
local BARS = {
  magicka = {{0.16, 0.33, 0.66}, {0.40, 0.62, 0.95}},
  health  = {{0.55, 0.10, 0.10}, {0.88, 0.26, 0.22}},
  stamina = {{0.20, 0.42, 0.18}, {0.45, 0.72, 0.36}},
}

local DAYS   = {'Sundas','Morndas','Tirdas','Middas','Turdas','Fredas','Loredas'}
local MONTHS = {'Morning Star',"Sun's Dawn",'First Seed',"Rain's Hand",'Second Seed','Midyear',
                "Sun's Height",'Last Seed','Hearthfire','Frostfall',"Sun's Dusk",'Evening Star'}

local function ordinal(n)
  local s = 'th'
  if n % 100 < 11 or n % 100 > 13 then
    s = ({[1]='st',[2]='nd',[3]='rd'})[n % 10] or 'th'
  end
  return n .. s
end

local function rgba(cr, c, a) cairo_set_source_rgba(cr, c[1], c[2], c[3], a or 1) end

local function font(cr, face, size, bold)
  cairo_select_font_face(cr, face, CAIRO_FONT_SLANT_NORMAL,
    bold and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
  cairo_set_font_size(cr, size)
end

-- width of text with extra letter spacing
local function tracked_width(cr, text, track)
  local w = 0
  local ext = cairo_text_extents_t:create()
  for ch in text:gmatch('[%z\1-\127\194-\244][\128-\191]*') do
    cairo_text_extents(cr, ch, ext)
    w = w + ext.x_advance + track
  end
  return w - track
end

-- draw text centred on cx with letter spacing and a soft shadow
local function text_c(cr, text, cx, y, color, alpha, track)
  track = track or 0
  local w = tracked_width(cr, text, track)
  local function pass(ox, oy, c, a)
    local x = cx - w / 2 + ox
    local ext = cairo_text_extents_t:create()
    for ch in text:gmatch('[%z\1-\127\194-\244][\128-\191]*') do
      cairo_move_to(cr, x, y + oy)
      rgba(cr, c, a)
      cairo_show_text(cr, ch)
      cairo_text_extents(cr, ch, ext)
      x = x + ext.x_advance + track
    end
  end
  for _, o in ipairs({{0,2,0.35},{1,2,0.25},{-1,2,0.25},{0,3,0.18}}) do
    pass(o[1], o[2], SHADE, o[3])
  end
  pass(0, 0, color, alpha or 1)
end

-- ornamental divider:  ─────◇─────
local function divider(cr, cx, y, half)
  cairo_set_line_width(cr, 1)
  local pat = cairo_pattern_create_linear(cx - half, y, cx + half, y)
  cairo_pattern_add_color_stop_rgba(pat, 0,   GOLD[1], GOLD[2], GOLD[3], 0)
  cairo_pattern_add_color_stop_rgba(pat, 0.5, GOLD[1], GOLD[2], GOLD[3], 0.85)
  cairo_pattern_add_color_stop_rgba(pat, 1,   GOLD[1], GOLD[2], GOLD[3], 0)
  cairo_set_source(cr, pat)
  cairo_move_to(cr, cx - half, y + 0.5); cairo_line_to(cr, cx - 7, y + 0.5)
  cairo_move_to(cr, cx + 7, y + 0.5);    cairo_line_to(cr, cx + half, y + 0.5)
  cairo_stroke(cr)
  cairo_pattern_destroy(pat)
  -- diamond
  rgba(cr, GOLD, 0.9)
  cairo_move_to(cr, cx, y - 4); cairo_line_to(cr, cx + 4, y + 0.5)
  cairo_line_to(cr, cx, y + 5); cairo_line_to(cr, cx - 4, y + 0.5)
  cairo_close_path(cr); cairo_stroke(cr)
end

-- tapered (hexagonal) bar path
local function bar_path(cr, x, y, w, h)
  local t = h / 2
  cairo_move_to(cr, x, y + t)
  cairo_line_to(cr, x + t, y); cairo_line_to(cr, x + w - t, y)
  cairo_line_to(cr, x + w, y + t)
  cairo_line_to(cr, x + w - t, y + h); cairo_line_to(cr, x + t, y + h)
  cairo_close_path(cr)
end

-- anchor: 'left' | 'right' | 'center'
local function hud_bar(cr, x, y, w, h, pct, colors, anchor)
  pct = math.max(0, math.min(100, pct or 0)) / 100
  -- frame
  bar_path(cr, x - 3, y - 3, w + 6, h + 6)
  rgba(cr, {0.05, 0.05, 0.05}, 0.75); cairo_fill_preserve(cr)
  cairo_set_line_width(cr, 1); rgba(cr, GOLD, 0.55); cairo_stroke(cr)
  -- end caps (small gold ticks)
  rgba(cr, GOLD, 0.8)
  for _, ex in ipairs({x - 3, x + w + 3}) do
    cairo_arc(cr, ex, y + h / 2, 1.6, 0, 2 * math.pi); cairo_fill(cr)
  end
  if pct <= 0 then return end
  -- fill
  local fw = w * pct
  local fx = (anchor == 'right' and x + w - fw) or (anchor == 'center' and x + (w - fw) / 2) or x
  cairo_save(cr)
  bar_path(cr, x, y, w, h); cairo_clip(cr)
  local pat = cairo_pattern_create_linear(0, y, 0, y + h)
  local lo, hi = colors[1], colors[2]
  cairo_pattern_add_color_stop_rgba(pat, 0,   hi[1], hi[2], hi[3], 1)
  cairo_pattern_add_color_stop_rgba(pat, 0.55, lo[1], lo[2], lo[3], 1)
  cairo_pattern_add_color_stop_rgba(pat, 1,   lo[1] * 0.7, lo[2] * 0.7, lo[3] * 0.7, 1)
  cairo_set_source(cr, pat)
  cairo_rectangle(cr, fx, y, fw, h); cairo_fill(cr)
  cairo_pattern_destroy(pat)
  -- top sheen
  rgba(cr, {1, 1, 1}, 0.18)
  cairo_rectangle(cr, fx, y + 1, fw, 1); cairo_fill(cr)
  cairo_restore(cr)
end

local function num(s) return tonumber((s or ''):match('[%d%.]+')) or 0 end

function conky_skyrim_hud()
  if conky_window == nil then return end
  local cs = cairo_xlib_surface_create(conky_window.display, conky_window.drawable,
    conky_window.visual, conky_window.width, conky_window.height)
  local cr = cairo_create(cs)
  cairo_set_antialias(cr, CAIRO_ANTIALIAS_BEST)

  local cx = W / 2
  local now = os.date('*t')

  -- time
  font(cr, 'Cinzel', 62, false)
  text_c(cr, os.date('%H:%M'), cx, 66, BONE, 1, 4)

  divider(cr, cx, 84, 150)

  -- Tamriel date
  font(cr, 'Cinzel', 16, true)
  text_c(cr, string.format('%s, %s of %s', DAYS[now.wday], ordinal(now.day), MONTHS[now.month]),
         cx, 112, BONE, 1, 1)
  font(cr, 'Jost', 11, false)
  text_c(cr, string.upper(string.format('4th Era, %d   ·   %s',
         now.year - 1825, os.date('%A %d %B'))), cx, 132, DIM, 1, 2.2)

  -- HUD bars
  local cpu  = num(conky_parse('${cpu cpu0}'))
  local ram  = num(conky_parse('${memperc}'))
  local disk = num(conky_parse('${fs_used_perc /}'))

  local by, bh, bw, gap = 166, 9, 104, 22
  local x1 = cx - bw * 1.5 - gap
  local x2 = cx - bw / 2
  local x3 = cx + bw / 2 + gap
  hud_bar(cr, x1, by, bw, bh, disk, BARS.magicka, 'left')
  hud_bar(cr, x2, by, bw, bh, cpu,  BARS.health,  'center')
  hud_bar(cr, x3, by, bw, bh, ram,  BARS.stamina, 'right')

  font(cr, 'Jost', 10, false)
  text_c(cr, string.format('DISK  %d%%', disk), x1 + bw / 2, by + bh + 20, DIM, 1, 1.6)
  text_c(cr, string.format('CPU  %d%%',  cpu),  x2 + bw / 2, by + bh + 20, DIM, 1, 1.6)
  text_c(cr, string.format('RAM  %d%%',  ram),  x3 + bw / 2, by + bh + 20, DIM, 1, 1.6)

  cairo_destroy(cr)
  cairo_surface_destroy(cs)
end
