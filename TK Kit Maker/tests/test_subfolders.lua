-- Adding a folder's subfolders as collections in one go.
--
-- The point of this is what it does NOT try to do. Working out by itself which
-- folder in a tree is "a pack" is not possible: one library keeps them two
-- deep, the next buries the audio under WAV/Kicks, and a rule that fits one is
-- wrong for the next. So the user picks the folder whose children are the
-- packs, and this only asks "is there audio under here".
--
-- The failures worth guarding against are both quiet. A pack whose samples sit
-- one folder further down looks empty and gets skipped, so it silently goes
-- missing from a list of twenty. And the Documentation and MIDI folders that
-- ship beside the samples come in as empty collections you then delete by hand,
-- every single time.

local KIT = assert(TEST_DIR, "run these through tests/run_all.py") .. "/../"
package.path = KIT .. "?.lua;" .. package.path

reaper = {}

local Scanner = require("core.scanner")

local fail = 0
local function check(label, ok, got)
  if not ok then fail = fail + 1 print("FAIL: " .. label .. "  (got " .. tostring(got) .. ")") end
end

local function fake_tree(tree)
  local function files(dir) return (tree[dir] and tree[dir].files) or {} end
  local function dirs(dir) return (tree[dir] and tree[dir].dirs) or {} end
  return files, dirs
end

local function names(list)
  local out = {}
  for i, e in ipairs(list) do out[i] = e.name end
  return table.concat(out, ", ")
end

-- --------------------------------------------------------------------------
-- 1. The ordinary case: a category folder with packs in it.
-- --------------------------------------------------------------------------
print("packs one level down")
local files, dirs = fake_tree({
  ["D/Drum Machines"] = { dirs = { "909 From Mars", "808 From Mars", "LinnDrum" } },
  ["D/Drum Machines/909 From Mars"] = { files = { "kick.wav", "snare.wav" } },
  ["D/Drum Machines/808 From Mars"] = { files = { "kick.wav" } },
  ["D/Drum Machines/LinnDrum"] = { files = { "a.wav", "b.wav", "c.wav" } },
})
local got = Scanner.subfolder_packs("D/Drum Machines", files, dirs)
check("all three", #got == 3, #got)
check("sorted by name", names(got) == "808 From Mars, 909 From Mars, LinnDrum", names(got))
check("with their paths", got[1].path == "D/Drum Machines/808 From Mars", got[1].path)
check("and a sample count", got[3].count == 3, got[3].count)
print("  " .. names(got))

-- --------------------------------------------------------------------------
-- 2. A pack that keeps its audio further down. Counting only the top folder
--    would call this empty and skip it -- one pack quietly missing out of
--    twenty, which you would not notice until you went looking for it.
-- --------------------------------------------------------------------------
print("audio buried deeper")
files, dirs = fake_tree({
  ["D"] = { dirs = { "Deep Pack" } },
  ["D/Deep Pack"] = { dirs = { "WAV" } },
  ["D/Deep Pack/WAV"] = { dirs = { "24bit" } },
  ["D/Deep Pack/WAV/24bit"] = { dirs = { "Kicks" } },
  ["D/Deep Pack/WAV/24bit/Kicks"] = { files = { "k1.wav", "k2.wav" } },
})
got = Scanner.subfolder_packs("D", files, dirs)
check("the pack is found", #got == 1, #got)
check("named after the folder that was picked, not the one with the audio",
  got[1] and got[1].name == "Deep Pack", got[1] and got[1].name)
check("counting through the whole subtree", got[1] and got[1].count == 2,
  got[1] and got[1].count)
print("  " .. names(got) .. " (" .. (got[1] and got[1].count or 0) .. " samples, four levels down)")

-- --------------------------------------------------------------------------
-- 3. What ships beside the samples. Packs routinely carry a Documentation or
--    MIDI folder, and those are subfolders too.
-- --------------------------------------------------------------------------
print("what is not a pack")
files, dirs = fake_tree({
  ["D"] = { dirs = { "Real Pack", "Documentation", "MIDI Loops", "Empty" } },
  ["D/Real Pack"] = { files = { "a.wav" } },
  ["D/Documentation"] = { files = { "readme.pdf", "licence.txt" } },
  ["D/MIDI Loops"] = { files = { "groove.mid" } },
  ["D/Empty"] = {},
})
got = Scanner.subfolder_packs("D", files, dirs)
check("only the one with audio in it", names(got) == "Real Pack", names(got))

-- Loose files in the picked folder itself are not a subfolder and so are not a
-- collection -- the folder you picked is the parent, not one of the packs.
files, dirs = fake_tree({
  ["D"] = { files = { "stray.wav" }, dirs = { "Pack" } },
  ["D/Pack"] = { files = { "a.wav" } },
})
check("loose files in the parent are ignored",
  names(Scanner.subfolder_packs("D", files, dirs)) == "Pack",
  names(Scanner.subfolder_packs("D", files, dirs)))

-- --------------------------------------------------------------------------
-- 4. Doing it twice. The second run must offer only what is new, or every
--    collection you already had comes back as a duplicate.
-- --------------------------------------------------------------------------
print("running it again")
files, dirs = fake_tree({
  ["D"] = { dirs = { "A", "B", "C" } },
  ["D/A"] = { files = { "a.wav" } },
  ["D/B"] = { files = { "b.wav" } },
  ["D/C"] = { files = { "c.wav" } },
})
got = Scanner.subfolder_packs("D", files, dirs, { skip = { ["d/a"] = true, ["d/c"] = true } })
check("the ones already added are left out", names(got) == "B", names(got))
check("and nothing is offered when they all are",
  #Scanner.subfolder_packs("D", files, dirs,
    { skip = { ["d/a"] = true, ["d/b"] = true, ["d/c"] = true } }) == 0)

-- --------------------------------------------------------------------------
-- 5. Nothing there.
-- --------------------------------------------------------------------------
print("nothing to add")
files, dirs = fake_tree({})
check("an unknown folder gives nothing", #Scanner.subfolder_packs("D", files, dirs) == 0)
files, dirs = fake_tree({ ["D"] = { files = { "only.wav" } } })
check("a folder with no subfolders gives nothing",
  #Scanner.subfolder_packs("D", files, dirs) == 0)

-- Backslashes and a trailing slash must not produce a doubled separator in the
-- paths that get stored.
files, dirs = fake_tree({
  ["D/Packs"] = { dirs = { "One" } },
  ["D/Packs/One"] = { files = { "a.wav" } },
})
got = Scanner.subfolder_packs("D\\Packs\\", files, dirs)
check("the root is normalised first", got[1] and got[1].path == "D/Packs/One",
  got[1] and got[1].path)

print()
print(fail == 0 and "ALL CHECKS PASSED" or (fail .. " CHECK(S) FAILED"))

TEST_FAILED = fail
