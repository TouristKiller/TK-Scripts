-- TK Notes shared store
--
-- One note format shared by TK Notes and the TK Workbench Notes module. Both
-- scripts ship their own copy of this file; they agree on the *format*, not on
-- a single installed file, so updating one script can never leave the other
-- running against a store module it was not built for.
--
-- The unit both apps genuinely have in common is a block of text with a title:
-- a TK Notes tab is a Workbench block. Everything neither app shares lives in a
-- per-app bag that the other app carries through untouched, so correcting a
-- typo in Workbench can never delete a drawing made in TK Notes.
--
-- Format version 1:
--   { version = 1, rev = <n>, owner = <string>, updated_at = <epoch>,
--     blocks = { { id, title, body, created_at, updated_at,
--                  font_size, font_family, text_color, line_colors, images,
--                  app = { tk = {...}, wb = {...} } }, ... } }

local Store = { FORMAT_VERSION = 1 }

-- Bumped whenever the importers below learn to rescue something they used to
-- miss. A context that was adopted by an older importer is re-examined once, and
-- anything not already present is appended -- never replaced, never reordered.
Store.MIGRATION_VERSION = 2

-- Where the shared notes live. Deliberately its own namespace: the two legacy
-- namespaces stay exactly as they are so an older install of either script, or
-- a downgrade, still finds its notes where it left them.
Store.NAMESPACE = "TK_NOTES_SHARED"
Store.TRACK_PEXT_KEY = "TK_NOTES_SHARED"

Store.LEGACY_TK_NAMESPACE = "TK_NOTES"
Store.LEGACY_WB_NAMESPACE = "TK_WORKBENCH_NOTES"
Store.LEGACY_WB_TRACK_PEXT_KEY = "TK_WB_NOTE"

local r = rawget(_G, "reaper")

-- Lets the test harness stand in for REAPER.
function Store.set_reaper(mock)
  r = mock
end

-- ---------------------------------------------------------------------------
-- JSON. Resolved from whichever copy the host script ships: the Workbench has
-- it on the module path, TK Notes gets a copy next to this file.
-- ---------------------------------------------------------------------------
local json
do
  local ok, mod = pcall(require, "core.json")
  if ok and type(mod) == "table" and mod.encode then json = mod end
  if not json then
    local here = debug.getinfo(1, "S").source:match("@(.+[\\/])")
    if here then
      local ok2, mod2 = pcall(dofile, here .. "json.lua")
      if ok2 and type(mod2) == "table" and mod2.encode then json = mod2 end
    end
  end
end

function Store.has_json()
  return json ~= nil
end

-- ---------------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------------
local function now_epoch()
  return os.time()
end

local function is_array(value)
  if type(value) ~= "table" then return false end
  return #value > 0 or next(value) == nil
end

local function copy_value(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for key, child in pairs(value) do out[key] = copy_value(child) end
  return out
end

-- A JSON encoder cannot represent a gap in a numeric key sequence: it reads
-- {[3]=true} as a sparse array and refuses the whole document, which would make
-- the save fail silently. Per-app bags hold whatever the other script puts in
-- them, so their tables are flattened to string keys unless they are real lists.
local function json_safe(value)
  if type(value) ~= "table" then return value end
  local count, max_key, list_like = 0, 0, true
  for key in pairs(value) do
    count = count + 1
    if type(key) == "number" and key == math.floor(key) and key >= 1 then
      if key > max_key then max_key = key end
    else
      list_like = false
    end
  end
  local out = {}
  if list_like and count == max_key then
    for index = 1, count do out[index] = json_safe(value[index]) end
  else
    for key, child in pairs(value) do out[tostring(key)] = json_safe(child) end
  end
  return out
end

-- The reverse for TK Notes, which looks its colours up by line *number*: string
-- keys read back out of JSON would simply never match.
local function numeric_line_colors(value)
  local out = {}
  if type(value) ~= "table" then return out end
  for line, colour in pairs(value) do
    local index, packed = tonumber(line), tonumber(colour)
    if index and packed then out[math.floor(index)] = math.floor(packed) end
  end
  return out
end

local id_counter = 0
local function new_id(seed)
  id_counter = id_counter + 1
  if r and r.genGuid then
    local guid = r.genGuid("")
    if guid and guid ~= "" then return "b" .. guid:gsub("[^%w]", ""):sub(1, 12):lower() end
  end
  return string.format("b%x%x%x", now_epoch(), id_counter, #tostring(seed or ""))
end

local function clean_text(value)
  if value == nil then return "" end
  return (tostring(value):gsub("\r\n", "\n"))
end

-- Used only to decide whether two notes are "the same note" during import. TK
-- Notes stores the loose text and the active tab separately and they drift by
-- trailing whitespace, so comparing them literally would import both.
local function same_note(a, b)
  a = clean_text(a):gsub("^%s+", ""):gsub("%s+$", "")
  b = clean_text(b):gsub("^%s+", ""):gsub("%s+$", "")
  return a == b
end

local function clean_number(value, fallback)
  local number = tonumber(value)
  if not number then return fallback end
  return number
end

-- line_colors is line index -> packed colour in both apps, but JSON object keys
-- are strings, so it is normalised to string keys on the way in.
local function clean_line_colors(value)
  local out = {}
  if type(value) ~= "table" then return out end
  for line, colour in pairs(value) do
    local index = tonumber(line)
    local packed = tonumber(colour)
    if index and packed then out[tostring(math.floor(index))] = math.floor(packed) end
  end
  return out
end

-- A stroke is a colour, a thickness and a run of points, in coordinates
-- relative to the top-left of the note body. Both apps draw them the same way.
local function clean_strokes(value)
  local out = {}
  if type(value) ~= "table" then return out end
  for _, stroke in ipairs(value) do
    if type(stroke) == "table" and type(stroke.points) == "table" and #stroke.points > 1 then
      local points = {}
      for _, point in ipairs(stroke.points) do
        if type(point) == "table" and tonumber(point.x) and tonumber(point.y) then
          points[#points + 1] = { x = tonumber(point.x), y = tonumber(point.y) }
        end
      end
      if #points > 1 then
        local colour = type(stroke.color) == "table" and stroke.color or {}
        out[#out + 1] = {
          color = { r = clean_number(colour.r, 1), g = clean_number(colour.g, 0),
                    b = clean_number(colour.b, 0), a = clean_number(colour.a, 1) },
          thickness = clean_number(stroke.thickness, 2),
          points = points
        }
      end
    end
  end
  return out
end

-- Workbench records width/height per image, TK Notes does not. Keeping the
-- superset means a round-trip through TK Notes does not shrink them.
local function clean_images(value)
  local out = {}
  if type(value) ~= "table" then return out end
  for _, image in ipairs(value) do
    if type(image) == "table" and image.path and image.path ~= "" then
      out[#out + 1] = {
        id = clean_number(image.id, #out + 1),
        path = tostring(image.path),
        width = clean_number(image.width, 150),
        height = clean_number(image.height, 100),
        pos_x = clean_number(image.pos_x, 10),
        pos_y = clean_number(image.pos_y, 10),
        scale = clean_number(image.scale, 100)
      }
    end
  end
  return out
end

-- ---------------------------------------------------------------------------
-- Blocks
-- ---------------------------------------------------------------------------
function Store.new_block(title, body, seed)
  local stamp = now_epoch()
  return {
    id = new_id(seed or title),
    title = tostring(title or "Notes"),
    body = clean_text(body),
    created_at = stamp,
    updated_at = stamp,
    font_size = 14,
    font_family = "sans-serif",
    text_color = 0xE6EDF3FF,
    align = "left",
    strokes = {},
    line_colors = {},
    images = {},
    app = { tk = {}, wb = {} }
  }
end

-- Anything not named here is dropped, so every field a block may carry has to
-- be listed; app bags are copied wholesale precisely because their contents are
-- none of this module's business.
function Store.normalize_block(value)
  if type(value) ~= "table" then return nil end
  local stamp = now_epoch()
  -- Alignment used to be TK Notes' alone and sat in its bag. Now that the
  -- Workbench aligns text too it belongs to the block; older notes keep it in
  -- the bag, so it is lifted out here.
  local bag_tk = (type(value.app) == "table" and type(value.app.tk) == "table") and value.app.tk or {}
  local align = value.align or bag_tk.align
  if align ~= "center" and align ~= "right" then align = "left" end
  -- Drawings were TK Notes' alone as well; same move, same fallback.
  local strokes = value.strokes or bag_tk.strokes
  local block = {
    id = (value.id and tostring(value.id) ~= "" ) and tostring(value.id) or new_id(value.title),
    title = tostring(value.title or "Notes"),
    body = clean_text(value.body),
    created_at = math.floor(clean_number(value.created_at, stamp)),
    updated_at = math.floor(clean_number(value.updated_at, stamp)),
    font_size = math.floor(clean_number(value.font_size, 14)),
    font_family = tostring(value.font_family or "sans-serif"),
    text_color = math.floor(clean_number(value.text_color, 0xE6EDF3FF)),
    align = align,
    strokes = clean_strokes(strokes),
    line_colors = clean_line_colors(value.line_colors),
    images = clean_images(value.images),
    app = { tk = {}, wb = {} }
  }
  if type(value.app) == "table" then
    if type(value.app.tk) == "table" then block.app.tk = json_safe(value.app.tk) end
    if type(value.app.wb) == "table" then block.app.wb = json_safe(value.app.wb) end
  end
  return block
end

function Store.new_document(owner)
  return {
    version = Store.FORMAT_VERSION,
    rev = 0,
    owner = tostring(owner or "unknown"),
    updated_at = now_epoch(),
    migration = Store.MIGRATION_VERSION,
    blocks = {}
  }
end

function Store.normalize_document(value, owner)
  if type(value) ~= "table" then return Store.new_document(owner) end
  local doc = {
    version = math.floor(clean_number(value.version, Store.FORMAT_VERSION)),
    rev = math.floor(clean_number(value.rev, 0)),
    owner = tostring(value.owner or owner or "unknown"),
    updated_at = math.floor(clean_number(value.updated_at, now_epoch())),
    migration = math.floor(clean_number(value.migration, 0)),
    blocks = {}
  }
  if type(value.blocks) == "table" then
    -- Last line of defence: every block must leave here with an id of its own.
    -- Two blocks sharing one id makes both apps push the same ImGui id twice,
    -- which shows up as a "conflicting ID" error over the note that got hit.
    local claimed = {}
    for _, raw in ipairs(value.blocks) do
      local block = Store.normalize_block(raw)
      if block then
        while claimed[block.id] do block.id = new_id(block.title) end
        claimed[block.id] = true
        doc.blocks[#doc.blocks + 1] = block
      end
    end
  end
  return doc
end

-- ---------------------------------------------------------------------------
-- Serialisation. Always a single line, which is what makes this safe to put in
-- reaper-extstate.ini as well as in the project file.
-- ---------------------------------------------------------------------------
function Store.encode(doc)
  if not json then return nil, "no json implementation available" end
  local ok, encoded = pcall(json.encode, doc)
  if not ok or type(encoded) ~= "string" then return nil, "encode failed" end
  return encoded
end

function Store.decode(raw, owner)
  if not json then return nil, "no json implementation available" end
  if type(raw) ~= "string" or raw == "" then return nil, "empty" end
  local first = raw:sub(1, 1)
  if first ~= "{" and first ~= "[" then return nil, "not json" end
  local ok, decoded = pcall(json.decode, raw)
  if not ok or type(decoded) ~= "table" then return nil, "decode failed" end
  return Store.normalize_document(decoded, owner)
end

-- ---------------------------------------------------------------------------
-- Conversion from what TK Notes has stored today.
--
-- legacy = { text, tabs_enabled, tabs = { {name, text, font_size, line_colors,
--            images, strokes}, ... }, images, strokes, align, font_size,
--            font_family, line_colors, bg_color, bg_brightness }
-- ---------------------------------------------------------------------------
local function tk_bag(source, doc_level)
  local bag = {}
  -- TK Notes paints its whole editor with the note colour, the Workbench paints
  -- a small card, so each keeps its own rather than one repainting the other.
  if tonumber(source.note_color) then bag.note_color = math.floor(tonumber(source.note_color)) end
  if source.use_context_color ~= nil then bag.use_context_color = source.use_context_color == true end
  if doc_level then
    if doc_level.bg_color then bag.bg_color = copy_value(doc_level.bg_color) end
    if doc_level.bg_brightness then bag.bg_brightness = clean_number(doc_level.bg_brightness, 1.0) end
  end
  return bag
end

function Store.from_tk_notes(legacy, owner)
  legacy = type(legacy) == "table" and legacy or {}
  local doc = Store.new_document(owner or "tk_notes")
  local base_font_size = math.floor(clean_number(legacy.font_size, 14))
  -- The legacy reader hands back "" for a key that was never written, and "" is
  -- truthy in Lua, so it has to be rejected explicitly or it wipes the default.
  local base_font_family = legacy.font_family
  if type(base_font_family) ~= "string" or base_font_family == "" then base_font_family = "sans-serif" end

  -- TK Notes keeps tabs stored even while tabs are switched off, so the tab list
  -- is imported whenever it holds anything: looking at tabs_enabled would silently
  -- drop every tab of anyone who had turned tabs off again.
  local tabs = type(legacy.tabs) == "table" and legacy.tabs or {}
  local text = clean_text(legacy.text)

  -- With tabs on, the loose text is a copy of the active tab, so it is only
  -- carried over when no tab already holds exactly that text.
  local text_is_duplicated = false
  for _, tab in ipairs(tabs) do
    if same_note(tab.text, text) then text_is_duplicated = true break end
  end

  -- The loose text may carry the id of a note that is also in the tab list; the
  -- id then belongs to that tab and reusing it here would put two blocks with
  -- one id into the document, which Dear ImGui reports as an ID conflict.
  local loose_id = (legacy.id and tostring(legacy.id) ~= "") and tostring(legacy.id) or nil
  if loose_id then
    for _, tab in ipairs(tabs) do
      if tab.id and tostring(tab.id) == loose_id then loose_id = nil break end
    end
  end

  if text ~= "" and not text_is_duplicated then
    local block = Store.new_block(legacy.title or "Notes", text, "tk0")
    -- Carrying the id back in is what keeps a save from orphaning the block and
    -- taking the other app's bag with it.
    if loose_id then block.id = loose_id end
    block.font_size = base_font_size
    block.font_family = base_font_family
    block.line_colors = clean_line_colors(legacy.line_colors)
    block.images = clean_images(legacy.images)
    -- The note without tabs needs the alignment just as much as a tab does;
    -- leaving it out here quietly reset every tabless note to left.
    if legacy.align == "center" or legacy.align == "right" then block.align = legacy.align end
    block.strokes = clean_strokes(legacy.strokes)
    block.app.tk = tk_bag(legacy, legacy)
    doc.blocks[#doc.blocks + 1] = block
  end

  for index, tab in ipairs(tabs) do
    local block = Store.new_block(tab.name or ("Tab " .. index), tab.text, "tk" .. index)
    if tab.id and tostring(tab.id) ~= "" then block.id = tostring(tab.id) end
    block.font_size = math.floor(clean_number(tab.font_size, base_font_size))
    -- A per-tab value handed straight back wins; the document-wide one is only
    -- used for a tab that never carried one, or when the caller says the user
    -- has just changed it (legacy.font_family_changed).
    if tab.font_family and tab.font_family ~= "" and not legacy.font_family_changed then
      block.font_family = tostring(tab.font_family)
    else
      block.font_family = base_font_family
    end
    if tonumber(tab.text_color) and not legacy.text_color_changed then
      block.text_color = math.floor(tonumber(tab.text_color))
    elseif tonumber(legacy.text_color) then
      block.text_color = math.floor(tonumber(legacy.text_color))
    end
    block.line_colors = clean_line_colors(tab.line_colors)
    block.images = clean_images(tab.images)
    local tab_align = tab.align or legacy.align
    if tab_align == "center" or tab_align == "right" then block.align = tab_align else block.align = "left" end
    block.strokes = clean_strokes(tab.strokes)
    block.app.tk = tk_bag(tab, index == 1 and legacy or nil)
    doc.blocks[#doc.blocks + 1] = block
  end

  if #doc.blocks == 0 then
    local block = Store.new_block("Notes", "", "tk0")
    block.font_size = base_font_size
    block.font_family = base_font_family
    block.app.tk = tk_bag(legacy, legacy)
    doc.blocks[#doc.blocks + 1] = block
  end
  return doc
end

-- ---------------------------------------------------------------------------
-- Conversion from what the Workbench Notes module has stored today.
-- ---------------------------------------------------------------------------
function Store.from_workbench(blocks, owner)
  local doc = Store.new_document(owner or "workbench")
  if type(blocks) ~= "table" then return doc end
  for index, raw in ipairs(blocks) do
    if type(raw) == "table" then
      local block = Store.new_block(raw.title, raw.body, "wb" .. index)
      if raw.id and tostring(raw.id) ~= "" then block.id = tostring(raw.id) end
      block.created_at = math.floor(clean_number(raw.created_at, block.created_at))
      block.updated_at = math.floor(clean_number(raw.updated_at, block.updated_at))
      block.font_size = math.floor(clean_number(raw.font_size, 14))
      block.font_family = tostring(raw.font_family or "sans-serif")
      block.text_color = math.floor(clean_number(raw.text_color, 0xE6EDF3FF))
      if raw.align == "center" or raw.align == "right" then block.align = raw.align else block.align = "left" end
      block.strokes = clean_strokes(raw.strokes)
      block.line_colors = clean_line_colors(raw.line_colors)
      block.images = clean_images(raw.images)
      block.app.wb = {
        collapsed = raw.collapsed == true,
        use_context_color = raw.use_context_color == true,
        note_color = math.floor(clean_number(raw.note_color, 0x2A303AFF)),
        list_mode = tostring(raw.list_mode or "none"),
        checkbox_lines = json_safe(raw.checkbox_lines) or {},
        height = math.floor(clean_number(raw.height, 120))
      }
      doc.blocks[#doc.blocks + 1] = block
    end
  end
  return doc
end

-- ---------------------------------------------------------------------------
-- Merge. Used once, when a context holds notes from both apps: neither wins,
-- the blocks are concatenated. Blocks sharing an id are folded together with
-- the newer text, and their app bags are unioned so nothing is dropped.
-- ---------------------------------------------------------------------------
function Store.merge(primary, secondary, owner)
  primary = Store.normalize_document(primary, owner)
  secondary = Store.normalize_document(secondary, owner)
  local doc = Store.new_document(owner or primary.owner)
  doc.rev = math.max(primary.rev or 0, secondary.rev or 0)

  local by_id, order = {}, {}
  local function absorb(block)
    local existing = by_id[block.id]
    if not existing then
      by_id[block.id] = block
      order[#order + 1] = block.id
      return
    end
    if (block.updated_at or 0) > (existing.updated_at or 0) then
      existing.title = block.title
      existing.body = block.body
      existing.updated_at = block.updated_at
      existing.font_size = block.font_size
      existing.font_family = block.font_family
      existing.text_color = block.text_color
      existing.line_colors = block.line_colors
      if #block.images > 0 then existing.images = block.images end
    end
    existing.created_at = math.min(existing.created_at or 0, block.created_at or 0)
    for key, value in pairs(block.app.tk) do
      if existing.app.tk[key] == nil then existing.app.tk[key] = value end
    end
    for key, value in pairs(block.app.wb) do
      if existing.app.wb[key] == nil then existing.app.wb[key] = value end
    end
  end

  for _, block in ipairs(primary.blocks) do absorb(block) end
  for _, block in ipairs(secondary.blocks) do absorb(block) end
  for _, id in ipairs(order) do doc.blocks[#doc.blocks + 1] = by_id[id] end
  return doc
end

-- What an app must use when saving. Unlike merge this is not a union: the
-- membership and order of `mine` win outright, so deleting a block in one app
-- really deletes it instead of being resurrected from the stored copy. The
-- stored copy is consulted only to carry forward the per-app bag and the
-- original creation time of blocks that still exist.
function Store.apply(mine, stored, owner, known_ids)
  mine = Store.normalize_document(mine, owner)
  if not stored then return mine end
  stored = Store.normalize_document(stored, owner)

  local stored_by_id = {}
  for _, block in ipairs(stored.blocks) do stored_by_id[block.id] = block end

  local mine_ids = {}
  for _, block in ipairs(mine.blocks) do mine_ids[block.id] = true end

  for _, block in ipairs(mine.blocks) do
    local old = stored_by_id[block.id]
    if old then
      block.created_at = math.min(block.created_at or 0, old.created_at or 0)
      for key, value in pairs(old.app.tk) do
        if block.app.tk[key] == nil then block.app.tk[key] = value end
      end
      for key, value in pairs(old.app.wb) do
        if block.app.wb[key] == nil then block.app.wb[key] = value end
      end
      -- A block the saving app cannot render must not lose its content either.
      if (block.body or "") == "" and (old.body or "") ~= "" and (block.updated_at or 0) <= (old.updated_at or 0) then
        block.body = old.body
      end
    end
  end
  -- Leaving a block out only counts as deleting it if this window had it on
  -- screen. A block the other app added since we last read was never ours to
  -- drop, so it is carried over instead of quietly disappearing.
  local carried = 0
  if known_ids then
    for _, block in ipairs(stored.blocks) do
      if not mine_ids[block.id] and not known_ids[block.id] then
        mine.blocks[#mine.blocks + 1] = block
        carried = carried + 1
      end
    end
  end

  mine.rev = math.max(mine.rev or 0, stored.rev or 0)
  -- The second value counts blocks that were carried over. A caller that gets a
  -- non-zero count has just saved a document containing notes it is not showing,
  -- so it should let its next refresh pull them in rather than consider itself
  -- up to date.
  return mine, carried
end

-- The set of ids a window is holding, handed back to Store.apply on its next
-- save so it can tell "the user deleted this" from "I never saw it".
function Store.block_ids(doc)
  local ids = {}
  if type(doc) == "table" and type(doc.blocks) == "table" then
    for _, block in ipairs(doc.blocks) do
      if block.id then ids[tostring(block.id)] = true end
    end
  end
  return ids
end

-- Drops empty blocks so an untouched context does not migrate as a stray note.
function Store.has_content(doc)
  if type(doc) ~= "table" or type(doc.blocks) ~= "table" then return false end
  for _, block in ipairs(doc.blocks) do
    if (block.body or "") ~= "" then return true end
    if type(block.images) == "table" and #block.images > 0 then return true end
    if type(block.app) == "table" and type(block.app.tk) == "table" and block.app.tk.strokes then return true end
  end
  return false
end

function Store.touch(doc, owner)
  doc.rev = math.floor(clean_number(doc.rev, 0)) + 1
  doc.owner = tostring(owner or doc.owner or "unknown")
  doc.updated_at = now_epoch()
  return doc
end

-- ---------------------------------------------------------------------------
-- Views back into each app's own shape.
-- ---------------------------------------------------------------------------
function Store.to_workbench(doc)
  doc = Store.normalize_document(doc)
  local blocks = {}
  for _, block in ipairs(doc.blocks) do
    local wb = block.app.wb or {}
    blocks[#blocks + 1] = {
      id = block.id,
      title = block.title,
      body = block.body,
      collapsed = wb.collapsed == true,
      use_context_color = wb.use_context_color == true,
      note_color = math.floor(clean_number(wb.note_color, 0x2A303AFF)),
      text_color = block.text_color,
      line_colors = clean_line_colors(block.line_colors),
      font_size = block.font_size,
      font_family = block.font_family,
      align = block.align,
      strokes = clean_strokes(block.strokes),
      list_mode = tostring(wb.list_mode or "none"),
      checkbox_lines = copy_value(wb.checkbox_lines) or {},
      images = clean_images(block.images),
      height = math.floor(clean_number(wb.height, 120)),
      created_at = block.created_at,
      updated_at = block.updated_at
    }
  end
  return blocks
end

-- More than one block always comes back as tabs: that is the only way TK Notes
-- can show every block, so a second block created in the Workbench turns tabs on.
function Store.to_tk_notes(doc)
  doc = Store.normalize_document(doc)
  local first = doc.blocks[1]
  local view = {
    id = first and first.id or nil,
    title = first and first.title or "Notes",
    tabs_enabled = #doc.blocks > 1,
    tabs = {},
    text = first and first.body or "",
    images = first and clean_images(first.images) or {},
    strokes = first and clean_strokes(first.strokes) or {},
    align = first and first.align or "left",
    font_size = first and first.font_size or 14,
    font_family = first and first.font_family or "sans-serif",
    line_colors = first and numeric_line_colors(first.line_colors) or {},
    bg_color = first and first.app.tk.bg_color or nil,
    bg_brightness = first and first.app.tk.bg_brightness or nil
  }
  for _, block in ipairs(doc.blocks) do
    view.tabs[#view.tabs + 1] = {
      id = block.id,
      name = block.title,
      text = block.body,
      font_size = block.font_size,
      -- Carried purely so they can be handed back: TK Notes has one font family
      -- and a black/white text mode for the whole note, so it cannot show these
      -- per block, and without carrying them its every save would flatten them.
      font_family = block.font_family,
      text_color = block.text_color,
      align = block.align,
      strokes = clean_strokes(block.strokes),
      note_color = block.app.tk.note_color,
      use_context_color = block.app.tk.use_context_color,
      line_colors = numeric_line_colors(block.line_colors),
      images = clean_images(block.images)
    }
  end
  return view
end

-- ---------------------------------------------------------------------------
-- Storage
--
-- A context is { kind = "global"|"project"|"track"|"item", project = <proj>,
-- guid = <track or item guid>, track = <MediaTrack> }.
--
-- Track notes go into P_EXT on the track itself rather than into the project,
-- so that copying a track to another project takes its notes along. That is how
-- the Workbench already stores them; TK Notes keyed them off the track GUID in
-- the project, where the note stayed behind.
-- ---------------------------------------------------------------------------
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local function base64_encode(s)
  if not s or s == "" then return "" end
  local out, acc, bits = {}, 0, 0
  for i = 1, #s do
    acc = acc * 256 + s:byte(i)
    bits = bits + 8
    while bits >= 6 do
      bits = bits - 6
      local idx = math.floor(acc / (2 ^ bits)) % 64
      out[#out + 1] = B64:sub(idx + 1, idx + 1)
      acc = acc % (2 ^ bits)
    end
  end
  if bits > 0 then
    local idx = math.floor((acc * (2 ^ (6 - bits))) % 64)
    out[#out + 1] = B64:sub(idx + 1, idx + 1)
  end
  while #out % 4 ~= 0 do out[#out + 1] = "=" end
  return table.concat(out)
end

local function base64_decode(s)
  if not s or s == "" then return "" end
  s = s:gsub("[^" .. B64 .. "=]", ""):gsub("=+$", "")
  local out, acc, bits = {}, 0, 0
  for i = 1, #s do
    local idx = B64:find(s:sub(i, i), 1, true)
    if idx then
      acc = acc * 64 + (idx - 1)
      bits = bits + 6
      if bits >= 8 then
        bits = bits - 8
        out[#out + 1] = string.char(math.floor(acc / (2 ^ bits)) % 256)
        acc = acc % (2 ^ bits)
      end
    end
  end
  return table.concat(out)
end

Store.base64_encode = base64_encode
Store.base64_decode = base64_decode

local function ext_get(namespace, key)
  if not r or not r.GetExtState then return "" end
  if r.HasExtState and not r.HasExtState(namespace, key) then return "" end
  return r.GetExtState(namespace, key) or ""
end

local function ext_set(namespace, key, value)
  if not r or not r.SetExtState then return false end
  r.SetExtState(namespace, key, value or "", true)
  return true
end

local function proj_get(project, namespace, key)
  if not r or not r.GetProjExtState then return "" end
  local _, value = r.GetProjExtState(project or 0, namespace, key)
  return value or ""
end

local function proj_set(project, namespace, key, value)
  if not r or not r.SetProjExtState then return false end
  r.SetProjExtState(project or 0, namespace, key, value or "")
  return true
end

local function pext_get(track, key)
  if not r or not track or not r.GetSetMediaTrackInfo_String then return "" end
  local ok, value = r.GetSetMediaTrackInfo_String(track, "P_EXT:" .. key, "", false)
  if not ok or not value or value == "" then return "" end
  local first = value:sub(1, 1)
  if first == "{" or first == "[" then return value end
  return base64_decode(value) or ""
end

local function pext_set(track, key, value)
  if not r or not track or not r.GetSetMediaTrackInfo_String then return false end
  local stored = (value and value ~= "") and base64_encode(value) or ""
  r.GetSetMediaTrackInfo_String(track, "P_EXT:" .. key, stored, true)
  return true
end

function Store.context_key(ctx, suffix)
  suffix = suffix or "blocks"
  local kind = ctx and ctx.kind or "project"
  if kind == "global" then return "GLOBAL::" .. suffix end
  if kind == "project" then return "PROJECT::" .. suffix end
  if kind == "item" then return "ITEM::" .. tostring(ctx.guid or "") .. "::" .. suffix end
  return tostring(ctx.guid or "") .. "::" .. suffix
end

function Store.load_raw(ctx)
  if not ctx then return "" end
  if ctx.kind == "global" then return ext_get(Store.NAMESPACE, Store.context_key(ctx)) end
  if ctx.kind == "track" then return pext_get(ctx.track, Store.TRACK_PEXT_KEY) end
  return proj_get(ctx.project, Store.NAMESPACE, Store.context_key(ctx))
end

function Store.save_raw(ctx, raw)
  if not ctx then return false end
  if ctx.kind == "global" then return ext_set(Store.NAMESPACE, Store.context_key(ctx), raw) end
  if ctx.kind == "track" then return pext_set(ctx.track, Store.TRACK_PEXT_KEY, raw) end
  return proj_set(ctx.project, Store.NAMESPACE, Store.context_key(ctx), raw)
end

function Store.load(ctx, owner)
  local raw = Store.load_raw(ctx)
  if raw == "" then return nil end
  local doc = Store.decode(raw, owner)
  return doc
end

-- A fingerprint of everything that counts as content, deliberately leaving out
-- the revision, the owner and the timestamps: those move on every save and would
-- make an untouched note look edited. Used to keep a window that changed nothing
-- from writing its view over someone else's fresher one -- TK Notes marks itself
-- dirty when its window is merely resized, which is not a change to the note.
-- `ignore_bag` is the other app's bag ("tk" or "wb"). Leaving it out is what
-- makes this answer the only question that matters at save time: did *we* change
-- anything? Merging always pulls the other app's fields in, so a signature over
-- the whole block would look changed after every foreign save, and the window
-- would then write its own -- possibly stale -- copy back over theirs.
-- Writes a value out with its keys in a fixed order. json.encode cannot be used
-- for a signature: it walks tables with pairs(), whose order Lua does not
-- guarantee, so identical content could serialise two different ways -- and an
-- untouched note would then read as edited and get written over the other
-- window's newer copy. Rare, but it is exactly the failure the signature exists
-- to prevent.
local function stable_serialize(value, out)
  local kind = type(value)
  if kind ~= "table" then
    out[#out + 1] = (kind == "number") and string.format("%.14g", value) or tostring(value)
    return
  end
  local keys = {}
  for key in pairs(value) do keys[#keys + 1] = key end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  out[#out + 1] = "{"
  for _, key in ipairs(keys) do
    out[#out + 1] = tostring(key)
    out[#out + 1] = "="
    stable_serialize(value[key], out)
    out[#out + 1] = ","
  end
  out[#out + 1] = "}"
end

function Store.content_signature(doc, ignore_bag)
  doc = Store.normalize_document(doc)
  local out = {}
  for _, block in ipairs(doc.blocks) do
    -- Every field the block itself carries has to be in here. A field that is
    -- stored but not signed reads as "nothing changed", and the save is then
    -- skipped -- so the edit is silently thrown away.
    out[#out + 1] = tostring(block.id) .. "\1" .. tostring(block.title) .. "\1" ..
      tostring(block.body) .. "\1" .. tostring(block.font_size) .. "\1" ..
      tostring(block.font_family) .. "\1" .. tostring(block.text_color) .. "\1" ..
      tostring(block.align) .. "\1"
    stable_serialize(block.strokes, out)
    out[#out + 1] = "\1"
    stable_serialize(block.line_colors, out)
    out[#out + 1] = "\1"
    stable_serialize(block.images, out)
    out[#out + 1] = "\1"
    stable_serialize(ignore_bag == "tk" and {} or block.app.tk, out)
    out[#out + 1] = "\1"
    stable_serialize(ignore_bag == "wb" and {} or block.app.wb, out)
    out[#out + 1] = "\2"
  end
  return table.concat(out)
end

-- The signature of just this window's own blocks. Store.apply appends blocks it
-- carried over from the other app, and counting those as local content would
-- make a foreign addition look like an unsaved edit here -- which would then
-- block the very refresh that is supposed to bring it in.
function Store.own_signature(doc, carried, ignore_bag)
  carried = tonumber(carried) or 0
  if carried <= 0 then return Store.content_signature(doc, ignore_bag) end
  local trimmed = { version = doc.version, rev = doc.rev, owner = doc.owner, blocks = {} }
  for index = 1, math.max(0, #doc.blocks - carried) do trimmed.blocks[index] = doc.blocks[index] end
  return Store.content_signature(trimmed, ignore_bag)
end

-- Cheap "has anyone else written?" probe for the live refresh: pulls the raw
-- string and picks the revision out of it without building the whole document,
-- so it is safe to call on a timer while both windows are open.
function Store.peek(ctx)
  local raw = Store.load_raw(ctx)
  if not raw or raw == "" then return 0, "" end
  local rev = tonumber(raw:match('"rev"%s*:%s*(%d+)')) or 0
  local owner = raw:match('"owner"%s*:%s*"([^"]*)"') or ""
  return rev, owner
end

function Store.save(ctx, doc, owner)
  if not doc then return false end
  Store.touch(doc, owner)
  local encoded, err = Store.encode(doc)
  if not encoded then return false, err end
  return Store.save_raw(ctx, encoded)
end

-- ---------------------------------------------------------------------------
-- Reading what is already stored by each app.
--
-- The TK Notes tab format escapes "|" and ":" on the way out but splits on
-- every "|" on the way in, so text containing those characters was already
-- truncated before it ever reached here. This reads it back exactly the way
-- TK Notes itself does: whatever the user can currently see is what migrates.
-- ---------------------------------------------------------------------------
-- TK Notes never used the real item GUID: it built an identifier out of the
-- track GUID plus the item's position and length. To find what it wrote, that
-- string has to be rebuilt here. (Because that identifier changes the moment the
-- item is nudged, the shared store keys items by the real GUID instead, which
-- also makes an item note survive being moved.)
local function tk_legacy_item_id(ctx)
  if ctx.legacy_tk_guid and ctx.legacy_tk_guid ~= "" then return ctx.legacy_tk_guid end
  local item = ctx.item
  if not item or not r or not r.GetMediaItem_Track or not r.GetMediaItemInfo_Value then return nil end
  local track = r.GetMediaItem_Track(item)
  local track_guid = (track and r.GetTrackGUID) and r.GetTrackGUID(track) or "no_track"
  local pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
  local length = r.GetMediaItemInfo_Value(item, "D_LENGTH")
  if not pos or not length then return nil end
  return string.format("%s::%.6f::%.6f", track_guid, pos, length)
end

local function tk_legacy_get(ctx, suffix)
  local key
  if ctx.kind == "global" then
    key = "GLOBAL::" .. suffix
    return ext_get(Store.LEGACY_TK_NAMESPACE, key)
  elseif ctx.kind == "project" then
    key = "PROJECT::" .. suffix
  elseif ctx.kind == "item" then
    local legacy_id = tk_legacy_item_id(ctx)
    if not legacy_id then return "" end
    key = "ITEM::" .. legacy_id .. "::" .. suffix
  else
    key = tostring(ctx.guid or "") .. "::" .. suffix
  end
  return proj_get(ctx.project, Store.LEGACY_TK_NAMESPACE, key)
end

local function tk_parse_line_colors(str)
  local out = {}
  if not str or str == "" then return out end
  for pair in str:gmatch("[^,]+") do
    local idx, hex = pair:match("^(%d+):(%x+)$")
    if idx and hex then out[tonumber(idx)] = tonumber(hex, 16) end
  end
  return out
end

local function tk_parse_images(str)
  local out = {}
  if not str or str == "" then return out end
  for entry in str:gmatch("[^|]+") do
    local id, rest = entry:match("^(%d+);(.+)$")
    if id and rest then
      local path, pos_x, pos_y, scale = rest:match("^(.-);([%-%d%.]+);([%-%d%.]+);(%d+)$")
      if path then
        out[#out + 1] = {
          id = tonumber(id), path = path:gsub("::", ":"),
          pos_x = tonumber(pos_x), pos_y = tonumber(pos_y), scale = tonumber(scale)
        }
      end
    end
  end
  return out
end

local function tk_parse_tabs(str)
  local tabs = {}
  if not str or str == "" then return tabs end
  local parts = {}
  for part in str:gmatch("[^|]+") do parts[#parts + 1] = part end
  if #parts < 2 then return tabs end
  for i = 3, #parts do
    local colon = parts[i]:find(":")
    if colon then
      tabs[#tabs + 1] = {
        name = parts[i]:sub(1, colon - 1):gsub("::", ":"):gsub("||", "|"),
        text = parts[i]:sub(colon + 1):gsub("::", ":"):gsub("||", "|")
      }
    end
  end
  return tabs
end

function Store.read_legacy_tk(ctx, owner)
  if not ctx then return nil end
  -- Item notes are the one context TK Notes cannot have for a track, and vice
  -- versa; the key builder above already accounts for that.
  local text = tk_legacy_get(ctx, "text")
  if ctx.kind == "track" then text = proj_get(ctx.project, Store.LEGACY_TK_NAMESPACE, tostring(ctx.guid or "")) end
  local tabs_enabled = tk_legacy_get(ctx, "tabs_enabled") == "true"
  local tabs = tk_parse_tabs(tk_legacy_get(ctx, "tabs_data"))
  for index, tab in ipairs(tabs) do
    tab.font_size = tonumber(tk_legacy_get(ctx, "tab" .. index .. "_font_size"))
    tab.line_colors = tk_parse_line_colors(tk_legacy_get(ctx, "tab" .. index .. "_line_colors"))
    tab.images = tk_parse_images(tk_legacy_get(ctx, "tab" .. index .. "_images"))
  end
  local legacy = {
    text = text,
    tabs_enabled = tabs_enabled,
    tabs = tabs,
    images = tk_parse_images(tk_legacy_get(ctx, "images")),
    align = tk_legacy_get(ctx, "align"),
    font_size = tonumber(tk_legacy_get(ctx, "font_size")),
    font_family = tk_legacy_get(ctx, "font_family"),
    line_colors = tk_parse_line_colors(tk_legacy_get(ctx, "line_colors"))
  }
  if (legacy.text or "") == "" and #tabs == 0 and #legacy.images == 0 then return nil end
  return Store.from_tk_notes(legacy, owner or "tk_notes")
end

function Store.read_legacy_wb(ctx, owner)
  if not ctx then return nil end
  local raw
  if ctx.kind == "global" then
    raw = ext_get(Store.LEGACY_WB_NAMESPACE, "GLOBAL::blocks")
  elseif ctx.kind == "track" then
    raw = pext_get(ctx.track, Store.LEGACY_WB_TRACK_PEXT_KEY)
    -- Older Workbench builds kept track notes in the project rather than on the
    -- track; the module still falls back to that, so the migration must too.
    if raw == "" then
      raw = proj_get(ctx.project, Store.LEGACY_WB_NAMESPACE, tostring(ctx.guid or "") .. "::blocks")
    end
  elseif ctx.kind == "item" then
    raw = proj_get(ctx.project, Store.LEGACY_WB_NAMESPACE, "ITEM::" .. tostring(ctx.guid or "") .. "::blocks")
  else
    raw = proj_get(ctx.project, Store.LEGACY_WB_NAMESPACE, "PROJECT::blocks")
  end
  if not raw or raw == "" or not json then return nil end
  local ok, decoded = pcall(json.decode, raw)
  if not ok or type(decoded) ~= "table" then return nil end
  return Store.from_workbench(decoded, owner or "workbench")
end

-- ---------------------------------------------------------------------------
-- One-time adoption of a context. Returns the shared document, creating it from
-- whatever the two apps had stored if it does not exist yet. The legacy keys are
-- read but never written or cleared: if this conversion turns out to be wrong,
-- the originals are still sitting there untouched.
-- ---------------------------------------------------------------------------
local function import_legacy(ctx, owner)
  local from_tk = Store.read_legacy_tk(ctx, owner)
  local from_wb = Store.read_legacy_wb(ctx, owner)
  if from_tk and from_wb then return Store.merge(from_tk, from_wb, owner) end
  return from_tk or from_wb
end

-- Appends anything the legacy stores still hold that the shared document does
-- not, matched on the text itself since the ids differ between the two worlds.
-- Only ever adds, so a note edited since the first migration is never rolled back.
local function rescue_missed_blocks(doc, ctx, owner)
  local legacy = import_legacy(ctx, owner)
  if not legacy then return false end
  local added = false
  for _, block in ipairs(legacy.blocks) do
    local body = block.body or ""
    if body ~= "" then
      local present = false
      for _, existing in ipairs(doc.blocks) do
        if same_note(existing.body, body) then present = true break end
      end
      if not present then
        doc.blocks[#doc.blocks + 1] = block
        added = true
      end
    end
  end
  return added
end

function Store.ensure(ctx, owner)
  local existing = Store.load(ctx, owner)
  if existing then
    if (existing.migration or 0) < Store.MIGRATION_VERSION then
      local added = rescue_missed_blocks(existing, ctx, owner)
      existing.migration = Store.MIGRATION_VERSION
      Store.save(ctx, existing, owner)
      return existing, added and "rescued" or "loaded"
    end
    return existing, "loaded"
  end

  local doc = import_legacy(ctx, owner)
  if not doc or not Store.has_content(doc) then
    return Store.new_document(owner), "empty"
  end
  doc.migration = Store.MIGRATION_VERSION
  Store.save(ctx, doc, owner)
  return doc, "migrated"
end

return Store
