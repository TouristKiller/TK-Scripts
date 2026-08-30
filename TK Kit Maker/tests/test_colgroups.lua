-- Grouping the collections panel.
--
-- The failures worth guarding against here are all of the quiet kind.
--
-- Two headers spelled almost the same, each holding half the packs you were
-- looking for. A pinned pack that sank into a collapsed group, so pinning it
-- hid it. And Move Up on a collection whose neighbour in storage is in another
-- group -- the array changes, the screen does not, and the button looks broken.

local KIT = assert(TEST_DIR, "run these through tests/run_all.py") .. "/../"
package.path = KIT .. "?.lua;" .. package.path

reaper = {}

local G = require("core.colgroups")

local fail = 0
local function check(label, ok, got)
  if not ok then fail = fail + 1 print("FAIL: " .. label .. "  (got " .. tostring(got) .. ")") end
end

local function col(id, group, pinned)
  return { id = id, name = id, path = "D:/Samples/" .. id, group = group, pinned = pinned }
end

local function ids(list)
  local out = {}
  for i, c in ipairs(list or {}) do out[i] = c.id end
  return table.concat(out, ",")
end

-- --------------------------------------------------------------------------
-- 1. Sebastian's case: several packs from one vendor, filed together.
-- --------------------------------------------------------------------------
print("a vendor's packs under one header")
local lib = {
  col("909", "Samples From Mars"),
  col("Vinyl Breaks"),
  col("808", "Samples From Mars"),
  col("Old Kicks"),
  col("SP1200", "Samples From Mars"),
}
local built = G.build(lib)
check("one group", #built.groups == 1, #built.groups)
check("with all three in it", ids(built.groups[1].items) == "909,808,SP1200",
  ids(built.groups[1].items))
check("named as written", built.groups[1].name == "Samples From Mars", built.groups[1].name)
check("the rest stay loose", ids(built.ungrouped) == "Vinyl Breaks,Old Kicks",
  ids(built.ungrouped))
print("  " .. built.groups[1].name .. " (" .. #built.groups[1].items .. "), loose: " ..
  ids(built.ungrouped))

-- Order inside a group follows the stored order, so Move Up and Move Down keep
-- meaning what they meant.
check("stored order is kept inside the group", built.groups[1].items[1].id == "909")

-- --------------------------------------------------------------------------
-- 2. The trap: the same group typed twice, differently.
-- --------------------------------------------------------------------------
print("one group, however you spell it")
local sloppy = {
  col("a", "Samples From Mars"),
  col("b", "samples from mars"),
  col("c", "  Samples From Mars  "),
}
local b2 = G.build(sloppy)
check("still one group", #b2.groups == 1, #b2.groups)
check("holding all three", #b2.groups[1].items == 3, #b2.groups[1].items)
check("under the first spelling", b2.groups[1].name == "Samples From Mars", b2.groups[1].name)
check("and offered once", #G.names(sloppy) == 1, #G.names(sloppy))

-- --------------------------------------------------------------------------
-- 3. Pinned. Pinning is about reach, so it cannot end up inside something
--    collapsible -- but it is a shortcut, not a move, so a pinned pack must
--    still be counted by the group it was filed under.
-- --------------------------------------------------------------------------
print("pinned stays on top")
local pinned_lib = {
  col("909", "Samples From Mars"),
  col("Favourite", "Samples From Mars", true),
  col("Loose"),
  col("AlsoPinned", nil, true),
}
local b3 = G.build(pinned_lib)
check("both pinned are at the top", ids(b3.pinned) == "Favourite,AlsoPinned", ids(b3.pinned))

-- The trap: a group that stops counting the pack you filed under it. You put
-- three in, the header says two, and nothing says where the third went.
check("a pinned pack stays in its group too", ids(b3.groups[1].items) == "909,Favourite",
  ids(b3.groups[1].items))
print("  pinned: " .. ids(b3.pinned) .. "  |  " .. b3.groups[1].name ..
  ": " .. ids(b3.groups[1].items))

-- The other half of the rule: a pinned pack with no group has no second place
-- to be, so it is not repeated in the loose run.
check("an ungrouped pinned pack is listed once", ids(b3.ungrouped) == "Loose", ids(b3.ungrouped))

-- A group made up entirely of pinned packs must still appear, or filing them
-- would look like it did nothing.
local all_pinned = { col("a", "Mars", true), col("b", "Mars", true) }
local b3b = G.build(all_pinned)
check("a group of only pinned packs still shows", #b3b.groups == 1, #b3b.groups)
check("with both in it", ids(b3b.groups[1].items) == "a,b", ids(b3b.groups[1].items))

-- --------------------------------------------------------------------------
-- 4. A library with no groups must look exactly like it did before.
-- --------------------------------------------------------------------------
print("nothing changes for a library without groups")
local plain = { col("a"), col("b"), col("c") }
local b4 = G.build(plain)
check("no headers", #b4.groups == 0, #b4.groups)
check("everything in order", ids(b4.ungrouped) == "a,b,c", ids(b4.ungrouped))
check("no group names offered", #G.names(plain) == 0, #G.names(plain))

-- --------------------------------------------------------------------------
-- 4b. Switching the headings off.
--
--     The trap is losing the filing. Turning grouping off must ignore the
--     groups, not erase them -- otherwise switching back means doing the work
--     over, and nothing warned you that looking was destructive.
-- --------------------------------------------------------------------------
print("grouping switched off")
local flat = G.build(lib, nil, true)
check("no headings", #flat.groups == 0, #flat.groups)
check("everything in one run, in stored order",
  ids(flat.ungrouped) == "909,Vinyl Breaks,808,Old Kicks,SP1200", ids(flat.ungrouped))
print("  " .. ids(flat.ungrouped))

-- The filing itself is untouched, so switching back restores the headings.
local back = G.build(lib)
check("the groups are still there afterwards", #back.groups == 1, #back.groups)
check("with their members", ids(back.groups[1].items) == "909,808,SP1200",
  ids(back.groups[1].items))
check("and the names are still on the collections", #G.names(lib) == 1, #G.names(lib))

-- Pinned still comes first, and with no group drawn there is no second place
-- for a pinned pack to be -- so it must not appear twice.
local flat_pinned = G.build(pinned_lib, nil, true)
check("pinned still on top", ids(flat_pinned.pinned) == "Favourite,AlsoPinned",
  ids(flat_pinned.pinned))
check("and listed once", ids(flat_pinned.ungrouped) == "909,Loose",
  ids(flat_pinned.ungrouped))

-- --------------------------------------------------------------------------
-- 5. Move Up / Move Down act on what is on screen.
--
--    This is the one that reads as a broken button: "909" and "SP1200" are in
--    the same group but have another pack between them in storage.
-- --------------------------------------------------------------------------
print("moving within what you see")
local moving = {
  col("909", "Mars"),
  col("Unrelated"),
  col("SP1200", "Mars"),
}
check("it reports the move", G.move(moving, "SP1200", -1))
local b5 = G.build(moving)
check("SP1200 came first in its group", ids(b5.groups[1].items) == "SP1200,909",
  ids(b5.groups[1].items))
check("and the loose one did not move into it", ids(b5.ungrouped) == "Unrelated",
  ids(b5.ungrouped))
print("  order in the group: " .. ids(b5.groups[1].items))

-- The ends refuse rather than wrapping or silently doing nothing surprising.
check("the first cannot go up", not G.move(moving, "SP1200", -1))
check("the last cannot go down", not G.move(moving, "909", 1))
check("and the menu can tell beforehand",
  G.can_move(moving, "909", -1) == true and G.can_move(moving, "909", 1) == false)

-- can_move must not actually move anything. If it did, opening the menu would
-- reorder the list behind you.
local before = ids(moving)
G.can_move(moving, "909", -1)
G.can_move(moving, "SP1200", 1)
check("asking does not move", ids(moving) == before, ids(moving))

-- Pinned collections move among themselves, not into the groups below.
local pmix = { col("p1", "Mars", true), col("g1", "Mars"), col("p2", nil, true) }
check("a pinned one moves past a grouped one", G.move(pmix, "p2", -1))
check("straight to the other pinned", ids(G.build(pmix).pinned) == "p2,p1",
  ids(G.build(pmix).pinned))

-- The trap behind that move. The pinned shelf's members are scattered through
-- storage, so reordering the shelf steps over collections drawn elsewhere. A
-- swap would exchange two slots and quietly reshuffle the group in between;
-- moving keeps everyone else where they were.
local shelf = {
  col("mars_a", "Mars", true),
  col("mars_b", "Mars"),
  col("mars_c", "Mars"),
  col("other", "Other", true),
}
local mars_before = ids(G.build(shelf).groups[1].items)
check("the shelf reorders", G.move(shelf, "other", -1))
check("and the group it stepped over is untouched",
  ids(G.build(shelf).groups[1].items) == mars_before,
  ids(G.build(shelf).groups[1].items) .. " was " .. mars_before)
print("  " .. mars_before .. " survived a shelf reorder")

-- An unknown id is a refusal, not an error.
check("an unknown id does nothing", not G.move(moving, "nope", 1))
check("and so does a nonsense step", not G.move(moving, "909", 3))

-- --------------------------------------------------------------------------
-- 6. Suggesting a name from the folder, which is what makes filing one click.
-- --------------------------------------------------------------------------
print("suggested names")
check("the parent folder", G.suggest("D:/Samples/Samples From Mars/909 From Mars") ==
  "Samples From Mars", G.suggest("D:/Samples/Samples From Mars/909 From Mars"))
check("backslashes too", G.suggest("D:\\Audio\\Vendor\\Pack") == "Vendor",
  G.suggest("D:\\Audio\\Vendor\\Pack"))
check("a trailing slash does not shift it", G.suggest("D:/Audio/Vendor/Pack/") == "Vendor",
  G.suggest("D:/Audio/Vendor/Pack/"))
-- A pack sitting at the root of a drive has no vendor folder to borrow, and
-- "D:" is not a group name anybody wants.
check("a drive root suggests nothing", G.suggest("D:/Pack") == "", G.suggest("D:/Pack"))
check("and so does an empty path", G.suggest("") == "", G.suggest(""))

-- --------------------------------------------------------------------------
-- 7. Renaming and ungrouping
-- --------------------------------------------------------------------------
print("renaming a group")
local ren = { col("a", "Mars"), col("b", "mars"), col("c", "Other") }
check("it reports how many moved", G.rename(ren, "MARS", "Red Planet") == 2,
  G.rename({ col("a", "Mars") }, "MARS", "Red Planet"))
local b7 = G.build(ren)
check("both were renamed", #b7.groups == 2, #b7.groups)
check("under the new name", G.names(ren)[2] == "Red Planet", G.names(ren)[2])

check("clearing it ungroups them", G.rename(ren, "Red Planet", "") == 2)
local b8 = G.build(ren)
check("and they fall back to loose", ids(b8.ungrouped) == "a,b", ids(b8.ungrouped))
check("leaving the other group alone", #b8.groups == 1, #b8.groups)

-- Renaming nothing must not sweep every ungrouped collection into a group.
local safe = { col("a"), col("b", "Keep") }
check("renaming the empty group moves nothing", G.rename(safe, "", "Oops") == 0)
check("so the loose one stays loose", ids(G.build(safe).ungrouped) == "a",
  ids(G.build(safe).ungrouped))

local removable = { col("kit1", "Imported"), col("keep", "Other"), col("kit2", "imported") }
local removed = G.remove(removable, "IMPORTED")
check("removing a group returns all of its kits", ids(removed) == "kit1,kit2", ids(removed))
check("removing a group leaves other kits alone", ids(removable) == "keep", ids(removable))
check("removing an empty group does nothing", #G.remove(removable, "") == 0, ids(removable))

-- --------------------------------------------------------------------------
-- 8. Collapsed state comes in by key, so it survives a differently spelled name.
-- --------------------------------------------------------------------------
print("collapsed state")
local b9 = G.build(lib, { ["samples from mars"] = true })
check("the group reads as collapsed", b9.groups[1].collapsed == true, b9.groups[1].collapsed)
check("an empty library is fine", #G.build({}).groups == 0)
check("and no library at all", #G.build(nil).ungrouped == 0)

print("multiple selection")
local selectable = { col("a"), col("b"), col("c"), col("d") }
local selection, anchor, primary = G.select(selectable, nil, nil, "b", false, false)
check("plain click selects one", selection.b and not selection.a and primary == "b", primary)
selection, anchor, primary = G.select(selectable, selection, anchor, "d", true, false)
check("control click adds one", selection.b and selection.d and primary == "d", primary)
selection, anchor, primary = G.select(selectable, selection, anchor, "b", true, false)
check("control click removes one", not selection.b and selection.d and primary == "d", primary)
selection, anchor, primary = G.select(selectable, selection, "b", "d", false, true)
check("shift click selects a range", selection.b and selection.c and selection.d and not selection.a, primary)
selection, anchor, primary = G.select(selectable, selection, anchor, "c", true, false)
selection, anchor, primary = G.select(selectable, selection, anchor, "c", true, false)
check("the last selected kit stays selected", selection.c and primary == "c", primary)

print()
print(fail == 0 and "ALL CHECKS PASSED" or (fail .. " CHECK(S) FAILED"))

TEST_FAILED = fail
