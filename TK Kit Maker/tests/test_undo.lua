-- The Builder's undo history.
--
-- The failure this guards against is the one that makes undo look broken while
-- appearing to work: a snapshot that shares its tables with the live state. The
-- entry is stored, the button lights up, you press it -- and nothing changes,
-- because the "old" slot table is the same table the edit wrote to.
--
-- The other half is the opposite mistake: restoring by replacing app.pools with
-- a new table. Everything else in the program is already holding a reference to
-- the old one, so the undo would appear to do nothing there either.

local KIT = assert(TEST_DIR, "run these through tests/run_all.py") .. "/../"
package.path = KIT .. "?.lua;" .. package.path

reaper = {}

local Undo = require("core.undo")

local fail = 0
local function check(label, ok, got)
  if not ok then fail = fail + 1 print("FAIL: " .. label .. "  (got " .. tostring(got) .. ")") end
end

local function fresh_app()
  return {
    pools = {
      pool_1 = { id = "pool_1", alias = "Kicks", folders = { "D:/Kicks" },
                 files = { "D:/Kicks/a.wav", "D:/Kicks/b.wav" } },
      pool_2 = { id = "pool_2", alias = "Snares", folders = { "D:/Snares" }, files = {} },
    },
    builder = { pool_order = { "pool_1", "pool_2" }, next_pool_n = 3 },
    kitdef = { slots = {
      { number = 1, pool_id = "pool_1", type_label = "Kick" },
      { number = 2, pool_id = "pool_2", type_label = "Snare" },
    } },
  }
end

-- 1. Deleting a pool, which is the case Sebastian named.
print("deleting a pool")
local app = fresh_app()
local h = Undo.new()
Undo.push(h, app, "delete pool")
app.pools.pool_2 = nil
table.remove(app.builder.pool_order, 2)
check("it is gone", app.pools.pool_2 == nil)

local label = Undo.pop(h, app)
check("undo reports what it undid", label == "delete pool", label)
check("the pool is back", app.pools.pool_2 ~= nil)
check("with its alias", app.pools.pool_2 and app.pools.pool_2.alias == "Snares",
  app.pools.pool_2 and app.pools.pool_2.alias)
check("and its place in the order", app.builder.pool_order[2] == "pool_2",
  app.builder.pool_order[2])
check("nothing left to undo", Undo.pop(h, app) == nil)

-- 2. The slot table replaced wholesale, which is what "From pattern" and Quick
-- layout both do.
print("replacing the slots")
app = fresh_app()
h = Undo.new()
Undo.push(h, app, "from pattern")
app.kitdef.slots = { { number = 1, pool_id = nil, type_label = "Clap" } }
Undo.pop(h, app)
check("both slots are back", #app.kitdef.slots == 2, #app.kitdef.slots)
check("with their pools", app.kitdef.slots[2].pool_id == "pool_2", app.kitdef.slots[2].pool_id)

-- 3. The trap. Slots are edited in place, so a shared table would mean undo
-- restoring the very tables the edit had already changed.
print("edits in place")
app = fresh_app()
h = Undo.new()
Undo.push(h, app, "link slot")
app.kitdef.slots[1].pool_id = "pool_2"
app.kitdef.slots[1].type_label = "Wrong"
Undo.pop(h, app)
check("the slot is as it was", app.kitdef.slots[1].pool_id == "pool_1",
  app.kitdef.slots[1].pool_id)
check("including its label", app.kitdef.slots[1].type_label == "Kick",
  app.kitdef.slots[1].type_label)

-- Folders are edited in place too -- added, removed and reordered.
app = fresh_app()
h = Undo.new()
Undo.push(h, app, "add folder")
table.insert(app.pools.pool_1.folders, "D:/More")
Undo.pop(h, app)
check("the folder list is as it was", #app.pools.pool_1.folders == 1,
  #app.pools.pool_1.folders)

-- 4. The other trap. Everything else holds a reference to app.pools and to
-- kitdef.slots, so restoring must refill them rather than swap them.
print("references survive")
app = fresh_app()
local held_pools = app.pools
local held_slots = app.kitdef.slots
h = Undo.new()
Undo.push(h, app, "delete pool")
app.pools.pool_1 = nil
app.kitdef.slots[1] = nil
Undo.pop(h, app)
check("app.pools is the same table", rawequal(app.pools, held_pools))
check("and the held one sees the restore", held_pools.pool_1 ~= nil)
check("kitdef.slots is the same table", rawequal(app.kitdef.slots, held_slots))
check("and it sees the restore", held_slots[1] ~= nil and held_slots[1].number == 1,
  held_slots[1] and held_slots[1].number)

-- 5. File lists are shared on purpose: a pool can hold thousands of paths and
-- nothing edits one in place. This is the reasoning written down as a test, so
-- that if anything ever does start editing them, this says where to look.
print("file lists are shared")
app = fresh_app()
h = Undo.new()
local files_before = app.pools.pool_1.files
Undo.push(h, app, "x")
Undo.pop(h, app)
check("the same array comes back", rawequal(app.pools.pool_1.files, files_before))
check("with its contents", #app.pools.pool_1.files == 2, #app.pools.pool_1.files)

-- 6. Depth, and what happens past it.
print("depth")
app = fresh_app()
h = Undo.new()
for i = 1, Undo.MAX + 4 do
  Undo.push(h, app, "step " .. i)
  app.kitdef.slots[1].number = i
end
check("the history is capped", Undo.depth(h) == Undo.MAX, Undo.depth(h))
check("the newest is on top", Undo.label(h) == "step " .. (Undo.MAX + 4), Undo.label(h))
print(string.format("  %d pushes kept %d, newest first: %s",
  Undo.MAX + 4, Undo.depth(h), Undo.label(h)))

local n = 0
while Undo.pop(h, app) do n = n + 1 end
check("it empties cleanly", n == Undo.MAX, n)
check("and stays empty", Undo.pop(h, app) == nil)

-- 7. A pool queued for deletion must not survive the undo, or the next frame
-- would delete what was just restored.
print("pending deletion")
app = fresh_app()
h = Undo.new()
Undo.push(h, app, "delete pool")
app.builder.pool_pending_delete = "pool_2"
app.pools.pool_2 = nil
Undo.pop(h, app)
check("the queued deletion is cleared", app.builder.pool_pending_delete == nil,
  app.builder.pool_pending_delete)
check("so the pool stays", app.pools.pool_2 ~= nil)

-- 8. Entries that undo themselves. Deleting a preset removes a file, and no
-- snapshot of the pools can bring it back -- so that action hands over a
-- function instead and lands in the same history.
--
-- The trap: such an entry carries no snapshot, so restoring the tables from it
-- would wipe the pools instead of leaving them alone.
print("self-undoing entries")
app = fresh_app()
h = Undo.new()
local called, file_back = 0, false
Undo.push_action(h, "delete preset", function()
  called = called + 1
  file_back = true
end)
check("it takes a label", Undo.label(h) == "delete preset", Undo.label(h))
local lab = Undo.pop(h, app)
check("undoing runs it", called == 1, called)
check("and reports the label", lab == "delete preset", lab)
check("the file came back", file_back)
check("the pools were left alone", app.pools.pool_1 ~= nil and app.pools.pool_2 ~= nil)
check("and so were the slots", #app.kitdef.slots == 2, #app.kitdef.slots)
check("nothing left", Undo.pop(h, app) == nil)

-- The two kinds share one history, in the order they happened.
app = fresh_app()
h = Undo.new()
Undo.push(h, app, "delete pool")
app.pools.pool_2 = nil
Undo.push_action(h, "delete preset", function() file_back = true end)
check("newest first", Undo.label(h) == "delete preset", Undo.label(h))
Undo.pop(h, app)
check("then the snapshot is next", Undo.label(h) == "delete pool", Undo.label(h))
Undo.pop(h, app)
check("and it still restores", app.pools.pool_2 ~= nil)

-- A push with no function must be refused rather than stored as an entry that
-- does nothing when pressed.
Undo.push_action(h, "broken", nil)
check("a missing restore is refused", Undo.depth(h) == 0, Undo.depth(h))

print()
print(fail == 0 and "ALL CHECKS PASSED" or (fail .. " CHECK(S) FAILED"))

TEST_FAILED = fail
