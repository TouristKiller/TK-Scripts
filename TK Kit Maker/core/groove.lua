-- Reads a groove out of a MIDI file.
--
-- A groove is not the notes: it is how far each note sits off the grid, and how
-- hard it hits. Feed it an MPC 60 pattern and what comes back is "step 2 lands
-- 11% of a step late at 78% velocity" -- sixteen of those, and that is the feel,
-- separated from whatever was actually played.
--
-- Offsets are stored as a FRACTION OF A STEP, never as ticks or milliseconds.
-- That is the whole reason a groove survives being applied to a different
-- tempo, a different step rate or a lane running at half speed: the feel is a
-- proportion, and only the engine turns it back into seconds. It also makes the
-- amount knob a plain multiply.
--
-- The parser handles what groove libraries actually ship -- format 0 and 1,
-- running status, sysex and meta events skipped -- and refuses anything it does
-- not understand rather than guessing, because a groove that is quietly wrong
-- is worse than one that failed to load: it just makes the kit feel off.

local M = {}

M.DEFAULT_STEPS = 16

-- Beyond this the note is closer to the next step than to this one, and calling
-- it a swing rather than a different note would be a lie. Groove files that
-- trip this are usually the wrong grid -- a 32nd-note groove read as 16ths --
-- which is worth reporting instead of silently halving the feel.
local MAX_OFFSET = 0.5

-- Byte reading -------------------------------------------------------------

local function u8(s, p) return s:byte(p), p + 1 end

local function u16(s, p)
  local a, b = s:byte(p, p + 1)
  return a * 256 + b, p + 2
end

local function u32(s, p)
  local a, b, c, d = s:byte(p, p + 3)
  return ((a * 256 + b) * 256 + c) * 256 + d, p + 4
end

-- MIDI's variable-length quantity: seven bits per byte, high bit means "more
-- follows". Delta times are stored this way, so getting it wrong desynchronises
-- everything after it rather than failing outright.
local function vlq(s, p)
  local value = 0
  for _ = 1, 4 do
    local b = s:byte(p)
    if not b then return nil end
    p = p + 1
    value = value * 128 + (b % 128)
    if b < 128 then return value, p end
  end
  return nil -- more than four bytes is malformed
end

-- Note collection ----------------------------------------------------------

-- Every note-on in the file, in ticks, merged across tracks. A groove file is
-- usually one track, but format 1 puts the tempo map in track 0 and the notes
-- in track 1, and some exporters split by drum voice.
local function read_notes(data)
  if #data < 14 or data:sub(1, 4) ~= "MThd" then
    return nil, "not a MIDI file"
  end

  local p = 5
  local header_len; header_len, p = u32(data, p)
  if header_len < 6 then return nil, "bad MIDI header" end

  local format; format, p = u16(data, p)
  local ntracks; ntracks, p = u16(data, p)
  local division; division, p = u16(data, p)

  if format > 1 then
    return nil, "MIDI format " .. format .. " is not supported"
  end
  if division >= 0x8000 then
    -- SMPTE timing: ticks are wall-clock, not musical, so there is no grid to
    -- measure against without also knowing the tempo map.
    return nil, "SMPTE-timed MIDI is not supported"
  end
  if division == 0 then return nil, "MIDI file has no time division" end

  p = 5 + 4 + header_len -- skip any header the spec grew since

  local notes = {}
  for _ = 1, ntracks do
    if p + 8 > #data + 1 then break end
    local chunk = data:sub(p, p + 3)
    local length; length, p = u32(data, p + 4)
    local track_end = p + length

    if chunk == "MTrk" then
      local tick = 0
      local status = nil
      while p < track_end do
        local delta; delta, p = vlq(data, p)
        if not delta then return nil, "malformed delta time" end
        tick = tick + delta

        local b = data:byte(p)
        if not b then return nil, "truncated track" end
        if b >= 0x80 then
          status = b
          p = p + 1
        elseif not status then
          return nil, "running status without a preceding event"
        end

        if status == 0xFF then
          local _; _, p = u8(data, p)
          local len; len, p = vlq(data, p)
          if not len then return nil, "malformed meta event" end
          p = p + len
        elseif status == 0xF0 or status == 0xF7 then
          local len; len, p = vlq(data, p)
          if not len then return nil, "malformed sysex" end
          p = p + len
        else
          local kind = status - (status % 16)
          if kind == 0x90 then
            local note; note, p = u8(data, p)
            local vel; vel, p = u8(data, p)
            -- A note-on at velocity 0 is a note-off, and counting it would add
            -- a phantom hit at the end of every sustained note.
            if vel > 0 then
              notes[#notes + 1] = { tick = tick, note = note, vel = vel }
            end
          elseif kind == 0x80 or kind == 0xA0 or kind == 0xB0 or kind == 0xE0 then
            p = p + 2
          elseif kind == 0xC0 or kind == 0xD0 then
            p = p + 1
          else
            return nil, string.format("unexpected status byte 0x%02X", status)
          end
        end
      end
    end
    p = track_end
  end

  if #notes == 0 then return nil, "no notes in the file" end
  table.sort(notes, function(a, b) return a.tick < b.tick end)
  return notes, division
end

-- Groove extraction --------------------------------------------------------

-- steps: how many steps one bar of the groove is measured in. 16 matches the
-- sequencer; an 8th-note groove read at 16 simply leaves every other step
-- empty, which is correct rather than a problem.
--
-- Returns { steps, offset[1..steps], velocity[1..steps], filled, name } where
-- offset is a fraction of one step (positive = behind the beat) and velocity is
-- 0..1, or nil for a step the groove says nothing about.
function M.from_midi(data, steps, name)
  steps = math.floor(tonumber(steps) or M.DEFAULT_STEPS)
  if steps < 2 or steps > 64 then return nil, "step count out of range" end

  local notes, division_or_err = read_notes(data)
  if not notes then return nil, division_or_err end
  local division = division_or_err

  -- 4/4 is assumed, as every drum groove library ships it. A bar is four
  -- quarter notes, and a step is that divided by the grid.
  local ticks_per_step = (division * 4) / steps
  if ticks_per_step <= 0 then return nil, "cannot derive a grid" end

  -- Which bar to read. Groove files are often two or four bars of the same
  -- feel; taking the first bar keeps one pattern rather than averaging a fill
  -- into the groove that made it interesting.
  local bar_ticks = ticks_per_step * steps

  local sum, count, peak = {}, {}, 0
  local skipped = 0
  for _, n in ipairs(notes) do
    if n.tick < bar_ticks then
      local pos = n.tick / ticks_per_step
      local step = math.floor(pos + 0.5)
      local deviation = pos - step
      -- The last step wraps to the first: a note dragged behind the final step
      -- belongs at the top of the next bar, not at step 17.
      step = (step % steps) + 1
      if math.abs(deviation) <= MAX_OFFSET then
        sum[step] = (sum[step] or 0) + deviation
        count[step] = (count[step] or 0) + 1
        if n.vel > peak then peak = n.vel end
        sum["v" .. step] = (sum["v" .. step] or 0) + n.vel
      else
        skipped = skipped + 1
      end
    end
  end

  local offset, velocity, filled = {}, {}, 0
  for i = 1, steps do
    if count[i] then
      -- Averaged, because a bar can hold several drums on the same step and
      -- their feel is the same feel.
      offset[i] = sum[i] / count[i]
      velocity[i] = peak > 0 and ((sum["v" .. i] / count[i]) / peak) or nil
      filled = filled + 1
    end
  end

  if filled == 0 then return nil, "no notes inside the first bar" end

  return {
    name = name,
    steps = steps,
    offset = offset,
    velocity = velocity,
    filled = filled,
    skipped = skipped,
  }
end

-- Built-in grooves ---------------------------------------------------------
--
-- Without these the feature looks broken on a fresh install: an empty folder,
-- an empty list, and nothing to hear. These give it something to do on day one
-- and, more usefully, something to compare an imported groove against.
--
-- They are timing only, deliberately. Velocity is what separates a sampled
-- groove -- an MPC pattern someone actually played -- from a mathematical one,
-- and pretending to supply it here would blur that line. A built-in shifts
-- when notes land; a real groove file also brings how hard they were hit.

-- The MPC swing model, and the reason these numbers are not eyeballed.
--
-- Swing is stated as a percentage from 50 to 75. Two 16ths make one 8th; at
-- 50% the second sits halfway, dead on the grid. At S% it sits S/100 of the way
-- through the pair, so its delay in steps is (S/100)*2 - 1. That puts 66% at
-- 0.33 of a step, which is a triplet -- exactly what "MPC swing" has always
-- meant -- and 75% at the dotted feel.
local function swing_offset(percent)
  return (percent / 100) * 2 - 1
end

-- every: 2 swings the 16ths (every other step), 4 swings the 8ths (the "and"
-- of each beat, leaving the 16ths straight).
local function swing_groove(percent, every)
  local offset = {}
  local delay = swing_offset(percent)
  for i = 1, M.DEFAULT_STEPS do
    offset[i] = ((i - 1) % every == (every / 2)) and delay or 0
  end
  return offset
end

local function flat_groove(shift)
  local offset = {}
  for i = 1, M.DEFAULT_STEPS do offset[i] = shift end
  return offset
end

-- The label carries the shift as well as the percentage, because the percentage
-- alone is ambiguous across programs. Akai, Cubase, Logic and FL run swing from
-- 50 to 75, where 50 is straight; Ableton and Reason run it from 0 to 100,
-- where 0 is straight. "Swing 66" therefore means two different amounts
-- depending on where the reader has come from, while "+33% of a step" means
-- exactly one thing anywhere.
--
-- It is computed from the offset rather than typed alongside it, so the name
-- cannot end up describing something the groove does not do.
local function label_for(base, offset)
  local peak = 0
  for i = 1, #offset do
    if math.abs(offset[i]) > math.abs(peak) then peak = offset[i] end
  end
  return string.format("%s (%+.0f%%)", base, peak * 100)
end

local BUILTIN = {}
do
  local defs = {
    { base = "Swing 54",     offset = swing_groove(54, 2), note = "16ths, barely there" },
    { base = "Swing 58",     offset = swing_groove(58, 2), note = "16ths, the usual amount" },
    { base = "Swing 62",     offset = swing_groove(62, 2), note = "16ths, heavy" },
    { base = "Swing 66",     offset = swing_groove(66, 2), note = "16ths, a full triplet" },
    { base = "Shuffle 8ths", offset = swing_groove(66, 4), note = "off-beats only, the 16ths stay straight" },
    { base = "Laid back",    offset = flat_groove(0.06),   note = "the whole bar a shade behind" },
    { base = "Pushed",       offset = flat_groove(-0.06),  note = "the whole bar a shade ahead" },
  }
  for i, d in ipairs(defs) do
    BUILTIN[i] = { name = label_for(d.base, d.offset), offset = d.offset, note = d.note }
  end
end

-- Walks a grooves folder and works out what to offer.
--
-- The two enumerators are passed in, so this knows nothing about REAPER and can
-- be run against a folder tree made up on the spot. That matters: the version
-- of this that lived in the sequencer listed ".midi" files it could not open,
-- because the loader put ".mid" back on the end of the name -- a file sitting
-- in the list, failing every time it was picked, with nothing to say why.
--
-- Subfolders count, with their path in the name: "MPC60 / Swing 62". Groove
-- packs arrive sorted into a folder per machine, and flattening them by hand
-- both loses where a groove came from and collides -- swing 62 on an MPC60 is
-- not swing 62 on an SP1200.
--
--   files(dir) -> array of filenames in dir
--   dirs(dir)  -> array of subfolder names in dir
--
-- Returns:
--   names  what to show as a flat list, in order
--   paths  name -> the file it was found at
--   tree   the same files as folders and leaves, for a menu
--
-- The flat name stays the identity -- it is what a lane stores and what a saved
-- pattern names a groove by -- so the tree carries both: the short name to draw
-- and the full one to store. Building a menu out of the flat names instead
-- would mean splitting them on " / " again, and a groove with a slash in its
-- own filename would come apart.
local function sort_ci(list, key)
  table.sort(list, function(a, b)
    local x, y = key(a), key(b)
    local lx, ly = x:lower(), y:lower()
    if lx ~= ly then return lx < ly end
    return x < y
  end)
end

function M.scan(root, files, dirs, opts)
  opts = opts or {}
  -- A folder per machine, sometimes wrapped in one per vendor. Past that it is
  -- somebody's backup tree, and this runs from a draw call.
  local max_depth = opts.max_depth or 3
  local found, paths = {}, {}
  local tree = { name = "", folders = {}, files = {} }

  local function walk(dir, prefix, depth, node)
    for _, fn in ipairs(files(dir) or {}) do
      local stem = tostring(fn):match("^(.*)%.[Mm][Ii][Dd][Ii]?$")
      if stem and stem ~= "" then
        local label = prefix ~= "" and (prefix .. " / " .. stem) or stem
        -- First one wins, so a rescan cannot make the list depend on the order
        -- the filesystem happened to hand things back.
        if not paths[label] then
          paths[label] = dir .. "/" .. fn
          found[#found + 1] = label
          node.files[#node.files + 1] = { name = stem, label = label }
        end
      end
    end
    if depth >= max_depth then return end
    for _, dn in ipairs(dirs(dir) or {}) do
      local child = { name = dn, folders = {}, files = {} }
      walk(dir .. "/" .. dn, prefix ~= "" and (prefix .. " / " .. dn) or dn, depth + 1, child)
      -- A folder with nothing in it anywhere below is not offered: an empty
      -- submenu is a promise of something that is not there.
      if #child.files > 0 or #child.folders > 0 then
        node.folders[#node.folders + 1] = child
      end
    end
    sort_ci(node.folders, function(f) return f.name end)
    sort_ci(node.files, function(f) return f.name end)
  end

  walk(root, "", 1, tree)
  table.sort(found, function(a, b)
    local la, lb = a:lower(), b:lower()
    if la ~= lb then return la < lb end
    return a < b
  end)

  -- Built-ins first and in their own order -- 54, 58, 62, 66 is a scale of
  -- increasing swing, and sorting it alphabetically would scatter it. Your own
  -- files follow, sorted. A file with a built-in's name wins, because a groove
  -- you put there yourself should beat one that shipped with the script.
  local names = {}
  for _, n in ipairs(opts.builtins or {}) do
    if not paths[n] then names[#names + 1] = n end
  end
  for _, n in ipairs(found) do names[#names + 1] = n end

  return { names = names, paths = paths, tree = tree }
end

function M.builtin_names()
  local out = {}
  for i, g in ipairs(BUILTIN) do out[i] = g.name end
  return out
end

function M.builtin(name)
  for _, g in ipairs(BUILTIN) do
    if g.name == name then
      local offset = {}
      for i = 1, M.DEFAULT_STEPS do offset[i] = g.offset[i] end
      return {
        name = g.name,
        steps = M.DEFAULT_STEPS,
        offset = offset,
        velocity = {},          -- timing only, on purpose
        filled = M.DEFAULT_STEPS,
        skipped = 0,
        built_in = true,
        note = g.note,
      }
    end
  end
  return nil
end

function M.load(path, steps)
  local f = io.open(path, "rb")
  if not f then return nil, "cannot open " .. tostring(path) end
  local data = f:read("*a")
  f:close()
  local leaf = tostring(path):match("([^/\\]+)%.[%w]+$") or tostring(path)
  return M.from_midi(data, steps, leaf)
end

-- What the engine needs, per step: a fraction of a step, already scaled by the
-- amount. Kept here rather than in the UI so that the meaning of "50%" is
-- decided in one place.
function M.step_offset(groove, step, amount)
  if not groove then return 0 end
  amount = tonumber(amount) or 0
  if amount <= 0 then return 0 end
  local n = groove.steps
  -- A 16-step groove drives a 32-step lane by repeating, which is what every
  -- groove box does and what makes an 8th-note groove usable on 16ths.
  local idx = ((math.floor(step) - 1) % n) + 1
  return (groove.offset[idx] or 0) * amount
end

function M.step_velocity(groove, step, amount)
  if not groove then return 1 end
  amount = tonumber(amount) or 0
  if amount <= 0 then return 1 end
  local n = groove.steps
  local idx = ((math.floor(step) - 1) % n) + 1
  local v = groove.velocity[idx]
  if not v then return 1 end
  -- Interpolated from "as played" towards the groove's own dynamics, so the
  -- amount knob moves velocity and timing together, as one feel.
  return 1 + (v - 1) * amount
end

-- How far ahead the engine has to look, in fractions of a step, for this groove
-- at this amount. Notes pushed EARLIER have to be scheduled before their grid
-- time arrives, and the engine cannot schedule what it has not seen yet.
function M.max_lead(groove, amount)
  if not groove then return 0 end
  amount = tonumber(amount) or 0
  if amount <= 0 then return 0 end
  local lead = 0
  for i = 1, groove.steps do
    local o = -(groove.offset[i] or 0)
    if o > lead then lead = o end
  end
  return lead * amount
end

-- Which steps this groove actually moves, as one row of marks.
--
-- Worth showing rather than describing, because the commonest surprise with
-- swing is that it does nothing at all: it moves the off-beats, so a lane
-- playing on the beat -- a kick on 1, 5, 9, 13 -- comes out identical however
-- far the amount is turned up. Seeing the gaps line up under the steps that are
-- not moving explains that in a glance.
function M.shape(groove)
  if not groove then return "" end
  local out = {}
  for i = 1, math.min(groove.steps, 32) do
    local o = groove.offset[i] or 0
    out[i] = (o > 0.001 and ">") or (o < -0.001 and "<") or "."
    -- Grouped in fours, so a mark can be read against a beat.
    if i % 4 == 0 and i < groove.steps then out[i] = out[i] .. " " end
  end
  return table.concat(out)
end

-- A one-line description for the UI: which way it leans and how far.
function M.summary(groove)
  if not groove then return "none" end
  if groove.built_in then return groove.note or "built in" end
  local late, early, worst = 0, 0, 0
  for i = 1, groove.steps do
    local o = groove.offset[i] or 0
    if o > 0 then late = late + 1 elseif o < 0 then early = early + 1 end
    if math.abs(o) > math.abs(worst) then worst = o end
  end
  return string.format("%d/%d steps, up to %+.0f%% of a step",
    groove.filled, groove.steps, worst * 100)
end

return M
