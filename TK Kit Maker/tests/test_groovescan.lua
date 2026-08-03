-- Finding groove files in the grooves folder.
--
-- The failure this exists for already happened: the scanner listed ".midi"
-- files and the loader could not open them, because it rebuilt the path by
-- putting ".mid" back on the end of the name. The file sat there in the menu,
-- did nothing every time it was picked, and said nothing about why. Keeping the
-- path each file was found at is what fixes that -- and it is the same thing
-- that makes subfolders possible at all.
--
-- The other one is quieter still: two packs each shipping a "Swing 62.mid".
-- With bare names one wins, the other vanishes from the list, and nothing says
-- a groove went missing.

local KIT = assert(TEST_DIR, "run these through tests/run_all.py") .. "/../"
package.path = KIT .. "?.lua;" .. package.path

reaper = {}

local Groove = require("core.groove")

local fail = 0
local function check(label, ok, got)
  if not ok then fail = fail + 1 print("FAIL: " .. label .. "  (got " .. tostring(got) .. ")") end
end

-- A folder tree made up on the spot. Keys are paths, values are the file names
-- in them; `sub` lists the folders.
local function fake_tree(tree)
  local function files(dir)
    return (tree[dir] and tree[dir].files) or {}
  end
  local function dirs(dir)
    return (tree[dir] and tree[dir].dirs) or {}
  end
  return files, dirs
end

local function joined(list)
  return table.concat(list or {}, ", ")
end

-- --------------------------------------------------------------------------
-- 1. A flat folder, which is what everyone starts with.
-- --------------------------------------------------------------------------
print("a flat folder")
local files, dirs = fake_tree({
  ["G"] = { files = { "Swing 62.mid", "readme.txt", "Push.MID", "Laid back.midi" } },
})
local r1 = Groove.scan("G", files, dirs)
check("only MIDI files", #r1.names == 3, joined(r1.names))
check("sorted, case-insensitively", joined(r1.names) == "Laid back, Push, Swing 62",
  joined(r1.names))
print("  " .. joined(r1.names))

-- The bug this was written for: the extension is kept, not assumed.
check(".mid keeps its path", r1.paths["Swing 62"] == "G/Swing 62.mid", r1.paths["Swing 62"])
check(".midi keeps ITS path", r1.paths["Laid back"] == "G/Laid back.midi",
  r1.paths["Laid back"])
check("upper case too", r1.paths["Push"] == "G/Push.MID", r1.paths["Push"])
check("and nothing else got in", r1.paths["readme"] == nil, r1.paths["readme"])

-- --------------------------------------------------------------------------
-- 2. Subfolders, which is how groove packs actually arrive.
-- --------------------------------------------------------------------------
print("a folder per machine")
files, dirs = fake_tree({
  ["G"]        = { files = { "Mine.mid" }, dirs = { "MPC60", "SP1200" } },
  ["G/MPC60"]  = { files = { "Swing 62.mid", "Swing 66.mid" } },
  ["G/SP1200"] = { files = { "Swing 62.mid" } },
})
local r2 = Groove.scan("G", files, dirs)
check("everything is found", #r2.names == 4, joined(r2.names))
check("named after the folder they came from",
  joined(r2.names) == "Mine, MPC60 / Swing 62, MPC60 / Swing 66, SP1200 / Swing 62",
  joined(r2.names))
print("  " .. joined(r2.names))

-- The trap. Two packs with the same filename must both survive, or one goes
-- missing with nothing to say so.
check("the two Swing 62s are separate entries",
  r2.paths["MPC60 / Swing 62"] == "G/MPC60/Swing 62.mid" and
  r2.paths["SP1200 / Swing 62"] == "G/SP1200/Swing 62.mid",
  r2.paths["SP1200 / Swing 62"])

-- --------------------------------------------------------------------------
-- 2b. The same files as a menu.
--
--     A folder has to be a folder you open, not a name with a slash in it.
--     Reading the tree back out of the flat names would mean splitting on
--     " / " again -- and a groove whose own filename contains a slash would
--     come apart into folders that do not exist.
-- --------------------------------------------------------------------------
print("as a menu")
local t = r2.tree
check("the loose file sits at the top", #t.files == 1 and t.files[1].name == "Mine",
  #t.files)
check("and the two machines are folders", #t.folders == 2, #t.folders)
check("in order", t.folders[1].name == "MPC60" and t.folders[2].name == "SP1200",
  t.folders[1].name .. "," .. t.folders[2].name)
check("with their grooves inside", #t.folders[1].files == 2, #t.folders[1].files)
print("  root: " .. t.files[1].name .. "  |  " .. t.folders[1].name .. ": " ..
  t.folders[1].files[1].name .. ", " .. t.folders[1].files[2].name)

-- Each leaf carries both: the short name to draw in the menu and the full one
-- the lane stores. Losing the second would mean a groove that cannot be found
-- again after a restart.
check("a leaf draws short", t.folders[1].files[1].name == "Swing 62",
  t.folders[1].files[1].name)
check("and stores long", t.folders[1].files[1].label == "MPC60 / Swing 62",
  t.folders[1].files[1].label)
check("which is a key into paths",
  r2.paths[t.folders[1].files[1].label] == "G/MPC60/Swing 62.mid",
  r2.paths[t.folders[1].files[1].label])

-- A filename with a slash in it must survive as one groove, not become a
-- folder. This is what carrying the label rather than re-splitting protects.
local sl_files, sl_dirs = fake_tree({ ["G"] = { files = { "Hat 1/2 open.mid" } } })
local rs = Groove.scan("G", sl_files, sl_dirs)
check("a slash in a filename stays in the name",
  #rs.tree.files == 1 and rs.tree.files[1].name == "Hat 1/2 open",
  rs.tree.files[1] and rs.tree.files[1].name)
check("and makes no folder", #rs.tree.folders == 0, #rs.tree.folders)

-- An empty folder is not offered -- a submenu that opens on nothing is a
-- promise of something that is not there.
local ef, ed = fake_tree({
  ["G"] = { dirs = { "Empty", "Full" } },
  ["G/Empty"] = {},
  ["G/Full"] = { files = { "a.mid" } },
})
local re = Groove.scan("G", ef, ed)
check("an empty folder is left out",
  #re.tree.folders == 1 and re.tree.folders[1].name == "Full",
  #re.tree.folders)

-- A folder holding nothing but another folder with grooves in it must stay,
-- or the grooves below it become unreachable.
local nf, nd = fake_tree({
  ["G"] = { dirs = { "Vendor" } },
  ["G/Vendor"] = { dirs = { "MPC60" } },
  ["G/Vendor/MPC60"] = { files = { "a.mid" } },
})
local rn = Groove.scan("G", nf, nd)
check("a folder of folders survives",
  #rn.tree.folders == 1 and #rn.tree.folders[1].folders == 1,
  #rn.tree.folders)
check("with the groove at the bottom",
  rn.tree.folders[1].folders[1].files[1].label == "Vendor / MPC60 / a",
  rn.tree.folders[1].folders[1].files[1] and rn.tree.folders[1].folders[1].files[1].label)

-- --------------------------------------------------------------------------
-- 3. Depth. A vendor folder wrapping the machine folders is still worth
--    reading; somebody's backup tree is not, and this runs from a draw call.
-- --------------------------------------------------------------------------
print("depth")
files, dirs = fake_tree({
  ["G"]       = { dirs = { "a" } },
  ["G/a"]     = { files = { "one.mid" }, dirs = { "b" } },
  ["G/a/b"]   = { files = { "two.mid" }, dirs = { "c" } },
  ["G/a/b/c"] = { files = { "three.mid" }, dirs = { "d" } },
  ["G/a/b/c/d"] = { files = { "four.mid" } },
})
-- The default reads the root and two levels under it: a folder per machine, or
-- a folder per vendor with the machines inside it. That is as deep as a groove
-- pack goes.
local r3 = Groove.scan("G", files, dirs)
check("two levels below the root are read",
  joined(r3.names) == "a / b / two, a / one", joined(r3.names))
check("and the third is not", r3.paths["a / b / c / three"] == nil,
  r3.paths["a / b / c / three"])
print("  " .. joined(r3.names))

local shallow = Groove.scan("G", files, dirs, { max_depth = 1 })
check("the depth is adjustable", #shallow.names == 0, joined(shallow.names))

-- --------------------------------------------------------------------------
-- 4. Built-ins. They lead, in their own order, and a file of the same name
--    takes their place rather than sitting beside them.
-- --------------------------------------------------------------------------
print("built-ins")
files, dirs = fake_tree({ ["G"] = { files = { "Swing 58.mid", "Aaa.mid" } } })
local built = { "Swing 54", "Swing 58", "Swing 62", "Swing 66" }
local r4 = Groove.scan("G", files, dirs, { builtins = built })

-- Their order is a scale of increasing swing, so it must not be sorted.
check("built-ins keep their own order and lead",
  r4.names[1] == "Swing 54" and r4.names[2] == "Swing 62" and r4.names[3] == "Swing 66",
  joined(r4.names))
check("the shadowed one is not listed twice", #r4.names == 5, joined(r4.names))
check("your files follow", r4.names[4] == "Aaa" and r4.names[5] == "Swing 58",
  joined(r4.names))
print("  " .. joined(r4.names))

-- And the one that shadows a built-in resolves to the file, or dropping a
-- replacement in would appear to do nothing.
check("the file wins", r4.paths["Swing 58"] == "G/Swing 58.mid", r4.paths["Swing 58"])
check("an unshadowed built-in has no path", r4.paths["Swing 54"] == nil,
  r4.paths["Swing 54"])

-- --------------------------------------------------------------------------
-- 5. Nothing there, and nothing odd.
-- --------------------------------------------------------------------------
print("empty and odd")
files, dirs = fake_tree({})
local r5 = Groove.scan("G", files, dirs)
check("an empty folder is fine", #r5.names == 0, joined(r5.names))
check("with built-ins still offered",
  #Groove.scan("G", files, dirs, { builtins = built }).names == 4)

files, dirs = fake_tree({ ["G"] = { files = { ".mid", "no extension", "x.mid.bak" } } })
local r6 = Groove.scan("G", files, dirs)
check("a bare extension is not a groove", #r6.names == 0, joined(r6.names))

print()
print(fail == 0 and "ALL CHECKS PASSED" or (fail .. " CHECK(S) FAILED"))

TEST_FAILED = fail
