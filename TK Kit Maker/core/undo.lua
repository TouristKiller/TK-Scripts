-- A short undo history for the Builder.
--
-- Deliberately small. Sebastian asked for "oops, I deleted a pool or made a
-- mistake in the slot section... just for the last action or so", and that is a
-- far easier thing to get right than undo across the whole program: the actions
-- worth catching all replace a whole table at once, so a snapshot taken just
-- before is enough. Nothing here tracks individual edits, and typing in a field
-- is not undoable -- that would need a different design and nobody asked for it.
--
-- WHAT IS COPIED, AND WHAT IS NOT
--
-- Pools are copied one level deep, keeping their file list by reference. That
-- is safe because nothing in the Builder edits a file list in place: scanning,
-- clearing and relinking all ASSIGN a new list (pool.files = ...), which leaves
-- the array the snapshot points at untouched. It also matters: a pool can hold
-- thousands of paths, and copying those for every step of the history would
-- cost more memory than the feature is worth.
--
-- Slots ARE copied properly, because they are edited in place -- linking a slot
-- to a pool writes to the slot table itself. Sharing them would mean an "undo"
-- that restored the same tables the edit had already changed, which looks like
-- undo doing nothing at all.

local M = {}

M.MAX = 8

local function copy_slot(slot)
  local out = {}
  for k, v in pairs(slot) do out[k] = v end
  return out
end

local function copy_pool(pool)
  local out = {}
  for k, v in pairs(pool) do out[k] = v end
  -- The folder list is edited in place (folders are added, removed and
  -- reordered), so it needs its own copy. The file list is not.
  if type(pool.folders) == "table" then
    local folders = {}
    for i, f in ipairs(pool.folders) do folders[i] = f end
    out.folders = folders
  end
  return out
end

function M.new()
  return { entries = {} }
end

-- An entry that undoes itself.
--
-- Not everything worth undoing lives in a table. Deleting a preset removes a
-- file, and no snapshot of the pools can bring that back -- so that action
-- hands over a function instead, and lands in the same history behind the same
-- button and the same Ctrl+Z. From the outside there is one undo, which is the
-- only thing a user should have to know.
function M.push_action(history, label, restore)
  if not history or type(restore) ~= "function" then return end
  history.entries[#history.entries + 1] = { label = label or "change", restore = restore }
  while #history.entries > M.MAX do
    table.remove(history.entries, 1)
  end
end

-- Called just before something destructive. `label` is what the button will
-- offer to undo, so it should name the action rather than the state.
function M.push(history, app, label)
  if not history or not app then return end
  local pools = {}
  for id, pool in pairs(app.pools or {}) do pools[id] = copy_pool(pool) end

  local order = {}
  for i, id in ipairs((app.builder or {}).pool_order or {}) do order[i] = id end

  local slots = {}
  for i, slot in ipairs((app.kitdef or {}).slots or {}) do slots[i] = copy_slot(slot) end

  history.entries[#history.entries + 1] = {
    label = label or "change",
    pools = pools,
    order = order,
    slots = slots,
    next_pool_n = (app.builder or {}).next_pool_n,
  }

  -- Oldest out first. A deeper history is not the point: this exists for the
  -- step you just regretted.
  while #history.entries > M.MAX do
    table.remove(history.entries, 1)
  end
end

function M.label(history)
  local e = history and history.entries[#history.entries]
  return e and e.label or nil
end

function M.depth(history)
  return history and #history.entries or 0
end

-- Puts the top snapshot back and returns its label, or nil when there is
-- nothing to undo.
--
-- The live tables are emptied and refilled rather than replaced, because other
-- parts of the program hold references to app.pools and app.kitdef.slots -- and
-- swapping the table would leave them pointing at the old one.
function M.pop(history, app)
  if not history or not app then return nil end
  local e = table.remove(history.entries)
  if not e then return nil end

  -- A self-undoing entry carries no snapshot, so restoring the tables from it
  -- would wipe the pools rather than leave them alone.
  if e.restore then
    e.restore()
    return e.label
  end

  if app.pools then
    for id in pairs(app.pools) do app.pools[id] = nil end
    for id, pool in pairs(e.pools) do app.pools[id] = copy_pool(pool) end
  end

  if app.builder then
    local order = app.builder.pool_order
    if order then
      for i = #order, 1, -1 do order[i] = nil end
      for i, id in ipairs(e.order) do order[i] = id end
    end
    if e.next_pool_n then app.builder.next_pool_n = e.next_pool_n end
    -- A pool that no longer exists must not stay queued for deletion, or the
    -- next frame would delete whatever the undo just brought back.
    app.builder.pool_pending_delete = nil
  end

  if app.kitdef then
    local slots = app.kitdef.slots
    if slots then
      for i = #slots, 1, -1 do slots[i] = nil end
      for i, slot in ipairs(e.slots) do slots[i] = copy_slot(slot) end
    end
  end

  return e.label
end

function M.clear(history)
  if history then history.entries = {} end
end

return M
