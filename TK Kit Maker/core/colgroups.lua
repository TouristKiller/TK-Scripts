-- Grouping for the collections panel.
--
-- The panel is a flat list, and a library of any size outgrows it: a dozen
-- packs from one vendor sit scattered between everything else. A group is a
-- name written on the collection itself -- no nesting, no tree, no second list
-- to keep in step with the first. A collection with no group is exactly what it
-- was before, so a library that never uses this looks and behaves unchanged.
--
-- UI-independent: this decides order and membership, and the panel draws it.

local M = {}

local function trim(s)
  return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end
M.trim = trim

-- Group names match case-insensitively.
--
-- Typing the name a second time is how you file a pack into an existing group,
-- and "Samples from Mars" next to "Samples From Mars" would give two headers
-- that look identical, each holding half of what you were looking for -- with
-- nothing to tell you they are different. The first spelling seen wins, so the
-- name stays whatever you called it the first time.
local function key_of(name)
  return trim(name):lower()
end
M.key_of = key_of

-- The parent folder's name, offered as the group name when you file a pack.
--
-- Sample libraries are already laid out this way -- a vendor folder with the
-- packs inside it -- so for most collections the name you want is one click
-- rather than something to be typed and mistyped.
function M.suggest(path)
  local p = tostring(path or ""):gsub("\\", "/"):gsub("/+$", "")
  local parent = p:match("^(.*)/[^/]+$")
  if not parent or parent == "" then return "" end
  local leaf = parent:match("([^/]+)$")
  if not leaf or leaf:match("^%a:$") then return "" end   -- a drive root is not a group
  return leaf
end

-- Every group name in use, in natural order, spelled as first written.
function M.names(collections)
  local seen, out = {}, {}
  for _, c in ipairs(collections or {}) do
    local name = trim(c.group)
    local k = key_of(name)
    if name ~= "" and not seen[k] then
      seen[k] = true
      out[#out + 1] = name
    end
  end
  table.sort(out, function(a, b) return a:lower() < b:lower() end)
  return out
end

-- What the panel draws, top to bottom.
--
-- Pinned collections stay at the very top, as they always have. Pinning is
-- about reach -- "keep this where I can get at it" -- so it cannot depend on
-- scrolling to a group and unfolding it, which is what putting a pinned pack
-- only inside its group would come to.
--
-- A pinned collection that belongs to a group is listed in BOTH places: pinning
-- is a shortcut, not a move, and a group that quietly stopped counting the pack
-- you filed under it would be lying about what is in it. A pinned collection
-- with no group is listed once, at the top -- there is no second place for it
-- to be, and repeating it in the loose run below would be a duplicate that says
-- nothing.
--
-- Groups come next, then everything ungrouped. Order inside a group is the
-- order the collections are already in, so Move Up and Move Down keep meaning
-- what they meant.
-- `flat` puts the headings away and gives back the plain list. The groups are
-- not forgotten, only ignored -- filing survives being switched off, or turning
-- it back on would mean doing the work again. A pinned pack is then listed once,
-- at the top, because with no group drawn there is no second place for it to be.
function M.build(collections, collapsed, flat)
  collapsed = collapsed or {}
  local out = { pinned = {}, groups = {}, ungrouped = {} }
  local by_key = {}

  for _, c in ipairs(collections or {}) do
    local name = flat and "" or trim(c.group)
    if c.pinned == true then
      out.pinned[#out.pinned + 1] = c
    end

    if name == "" then
      if c.pinned ~= true then
        out.ungrouped[#out.ungrouped + 1] = c
      end
    else
      local k = key_of(name)
      local g = by_key[k]
      if not g then
        g = { name = name, key = k, items = {}, collapsed = collapsed[k] == true }
        by_key[k] = g
        out.groups[#out.groups + 1] = g
      end
      g.items[#g.items + 1] = c
    end
  end

  table.sort(out.groups, function(a, b)
    if a.key ~= b.key then return a.key < b.key end
    return a.name < b.name
  end)
  return out
end

-- Moves a collection one place within the list it is drawn in.
--
-- The buttons act on what you can see, not on the underlying array. Group
-- members are not necessarily next to each other in storage, so swapping with
-- the raw neighbour would move a collection past something in another group and
-- change nothing on screen -- a button that visibly does nothing, on a list you
-- are trying to put in order.
--
-- Returns true when something moved.
function M.move(collections, id, delta)
  collections = collections or {}
  if delta ~= 1 and delta ~= -1 then return false end

  local from
  for i, c in ipairs(collections) do
    if c.id == id then from = i break end
  end
  if not from then return false end

  local me = collections[from]
  -- Pinned collections are drawn as one run of their own, so they move among
  -- themselves; the rest move among their own group.
  local function same_list(other)
    if (me.pinned == true) ~= (other.pinned == true) then return false end
    if me.pinned == true then return true end
    return key_of(me.group) == key_of(other.group)
  end

  local i = from + delta
  while i >= 1 and i <= #collections do
    if same_list(collections[i]) then
      -- Lifted out and put back next to its new neighbour, rather than swapped
      -- with it. A swap exchanges two positions, and everything between them
      -- keeps its slot but changes who its neighbours are -- so reordering the
      -- pinned shelf, whose members are scattered through storage, would
      -- silently reshuffle the groups those members belong to.
      table.remove(collections, from)
      table.insert(collections, i, me)
      return true
    end
    i = i + delta
  end
  return false
end

-- Whether Move Up / Move Down can do anything, so the menu can grey them out
-- rather than offer a button that quietly does nothing.
function M.can_move(collections, id, delta)
  local copy = {}
  for i, c in ipairs(collections or {}) do copy[i] = c end
  return M.move(copy, id, delta)
end

-- Renames a group, or clears it when `to` is empty. Returns how many moved.
function M.rename(collections, from, to)
  local k = key_of(from)
  local target = trim(to)
  local n = 0
  for _, c in ipairs(collections or {}) do
    if key_of(c.group) == k and k ~= "" then
      c.group = target ~= "" and target or nil
      n = n + 1
    end
  end
  return n
end

function M.remove(collections, group)
  local key = key_of(group)
  local removed = {}
  if key == "" then return removed end
  for i = #(collections or {}), 1, -1 do
    if key_of(collections[i].group) == key then
      table.insert(removed, 1, table.remove(collections, i))
    end
  end
  return removed
end

function M.select(collections, selected, anchor_id, clicked_id, ctrl, shift)
  local out = {}
  if ctrl then
    for id, value in pairs(selected or {}) do
      if value then out[id] = true end
    end
  end

  if shift then
    local first, last
    for i, collection in ipairs(collections or {}) do
      if collection.id == anchor_id then first = i end
      if collection.id == clicked_id then last = i end
    end
    if not first then first = last end
    if first and last then
      if first > last then first, last = last, first end
      for i = first, last do out[collections[i].id] = true end
    end
    return out, anchor_id or clicked_id, clicked_id
  end

  if ctrl then
    if out[clicked_id] then
      out[clicked_id] = nil
      local primary
      for _, collection in ipairs(collections or {}) do
        if out[collection.id] then primary = collection.id break end
      end
      if not primary then
        out[clicked_id] = true
        primary = clicked_id
      end
      return out, clicked_id, primary
    end
    out[clicked_id] = true
    return out, clicked_id, clicked_id
  end

  return { [clicked_id] = true }, clicked_id, clicked_id
end

return M
