local categorizer = {}

local CATEGORY_KEYWORDS = {
    kick = {
        "kick", "kck", "kik", "kk", "bd", "bassdrum", "bass_drum", "bass drum",
        "808", "909kick", "909bd", "909 kick"
    },
    snare = {
        "snare", "snr", "sn", "sd", "rimshot", "rim shot", "rim_shot",
        "909snare", "909snr", "909 snare", "clap snare"
    },
    clap = {
        "clap", "clp", "handclap", "hand_clap", "hand clap"
    },
    hihat = {
        "hihat", "hi hat", "hi_hat", "hh", "hat", "closedhat", "openhat",
        "closed hat", "open hat", "closed_hat", "open_hat", "ch_", "oh_",
        "pedal hat", "pedalhat"
    },
    cymbal = {
        "cymbal", "cym", "cyms", "crash", "ride", "splash", "china"
    },
    tom = {
        "tom", "toms", "floor tom", "rack tom", "hi tom", "lo tom",
        "mid tom", "high tom", "low tom"
    },
    percussion = {
        "perc", "percussion", "shaker", "tambourine", "tamb", "conga",
        "bongo", "cowbell", "triangle", "woodblock", "cabasa", "guiro",
        "maracas", "timbale", "clave", "agogo", "djembe", "cajon",
        "snap", "fingersnap", "finger snap"
    },
    bass = {
        "bass", "sub", "808bass", "subbass", "sub_bass", "sub bass",
        "reese", "bass synth", "bassline", "bass_line"
    },
    synth = {
        "synth", "synth lead", "synthlead", "lead", "arp", "arpeggio",
        "pluck", "stab", "chord", "chords", "saw", "square", "sine",
        "supersaw", "hoover"
    },
    pad = {
        "pad", "pads", "ambient", "atmosphere", "atmo", "drone",
        "texture", "evolving", "soundscape"
    },
    keys = {
        "piano", "keys", "keyboard", "organ", "rhodes", "wurlitzer",
        "electric piano", "epiano", "e_piano", "clav", "clavinet",
        "marimba", "vibraphone", "xylophone", "glockenspiel", "celesta",
        "harp", "harpsichord", "mallet"
    },
    guitar = {
        "guitar", "gtr", "guit", "acoustic guitar", "electric guitar",
        "clean guitar", "distorted guitar", "overdrive guitar",
        "strat", "tele", "les paul", "nylon", "steel string", "ukulele"
    },
    strings = {
        "strings", "string", "violin", "viola", "cello", "contrabass",
        "orchestral", "ensemble", "chamber", "pizzicato", "legato strings"
    },
    brass = {
        "brass", "trumpet", "trombone", "horn", "french horn", "tuba",
        "flugelhorn", "cornet"
    },
    vocal = {
        "vocal", "vox", "voice", "choir", "acapella", "a capella",
        "singing", "spoken", "speech", "adlib", "chant"
    },
    fx = {
        "fx", "sfx", "effect", "riser", "impact", "downlifter",
        "uplifter", "whoosh", "sweep", "noise", "glitch", "stutter",
        "transition", "reverse", "buildup", "build up", "build_up",
        "drop", "explosion", "boom", "siren", "alarm", "foley",
        "cinematic", "hit", "one shot"
    },
    loop = {
        "loop", "break", "breakbeat", "drum loop", "drumloop",
        "drum_loop", "top loop", "toploop", "top_loop", "groove",
        "pattern", "beat", "full loop", "construction"
    }
}

local CATEGORY_COLORS = {
    kick =       0xCC2222FF,
    snare =      0xF57C00FF,
    clap =       0xFF8A65FF,
    hihat =      0xFFCA28FF,
    cymbal =     0xFFEE58FF,
    tom =        0xE64A19FF,
    percussion = 0xFFA726FF,
    bass =       0x4A148CFF,
    synth =      0x7B1FA2FF,
    pad =        0xBA68C8FF,
    keys =       0x00695CFF,
    guitar =     0x00897BFF,
    strings =    0x4DB6ACFF,
    brass =      0xFFB300FF,
    vocal =      0x1976D2FF,
    fx =         0x37474FFF,
    loop =       0x546E7AFF,
    other =      0x78909CFF
}

local CATEGORY_ORDER = {
    "kick", "snare", "clap", "hihat", "cymbal", "tom", "percussion",
    "bass", "synth", "pad", "keys", "guitar", "strings", "brass",
    "vocal", "fx", "loop"
}

-- Keywords that hint at a category without naming one, scored below a real
-- instrument name so that anything explicit wins the tie.
--
-- A drum machine qualifies a sample, it does not identify it: an 808 has claps
-- and hats on it as readily as kicks, so ESWTR808 Clap 01 is a clap. Scored the
-- same as a kick it drew level with the word "clap" and won on the ordering
-- above, which put every 808 pack's whole contents under kick.
--
-- The two-letter abbreviations have the same trouble for a different reason:
-- matching is on substrings, so "sn" is inside "snap" and drags a percussion
-- sample into snare on the same tie.
local WEAK_KEYWORDS = {
    ["808"] = true,
    ["kk"] = true, ["bd"] = true, ["sn"] = true, ["sd"] = true,
}

-- Keywords that may only match at the start of a word. Matching is on plain
-- substrings, which is what lets Kick8 and modkick2 be read as kicks, but short
-- instrument names also live inside ordinary words: "tom" is inside custom and
-- automatic, which filed every CustomContact and Automatic sample under toms.
-- The same goes for hat in whatever, ride in override, arp and harp in sharp,
-- organ in organic, sub in subtle and keys in monkeys.
local WORD_START_ONLY = {
    ["tom"] = true, ["toms"] = true, ["hat"] = true, ["ride"] = true,
    ["arp"] = true, ["harp"] = true, ["organ"] = true, ["sub"] = true,
    ["keys"] = true, ["sine"] = true, ["stab"] = true,
}

-- Abbreviations get a gentler rule: either edge of a word will do, just not
-- buried inside one. Names glue words together, so a two letter abbreviation
-- turns up across the seam - "hh" sits inside SynthHorn, SynthHybrid and
-- TechHouse, which filed a whole pack of synths under hihat. Insisting on the
-- start of a word would have gone too far the other way, because OpenHH and
-- ClosedHH carry theirs at the end and there are two hundred of those.
local WORD_EDGE_ONLY = {
    ["hh"] = true, ["kk"] = true, ["bd"] = true, ["sn"] = true, ["sd"] = true,
    ["clp"] = true, ["snr"] = true, ["kck"] = true, ["kik"] = true,
}

-- "cym" has to be a word of its own, because Cymatics is a sample pack and not
-- a cymbal, and a thousand of its files carry the name. Every file that really
-- does write "Cym" also says Cymbal somewhere, so nothing is lost by it; "cyms"
-- is listed separately for the handful of finger cymbals that do not.
local WHOLE_WORD_ONLY = {
    ["cym"] = true, ["cyms"] = true,
}

-- Deliberately not on either list: pad, bass, lead and saw. They look like the
-- same risk but the library says otherwise - CaesarPad, DatBass, HMLead and
-- SoftSawz put them at the end of a glued word, hundreds of times over, and a
-- word rule would lose every one of them.
local function keyword_found(padded_text, kw)
    if WHOLE_WORD_ONLY[kw] then
        return padded_text:find(" " .. kw .. " ", 1, true) ~= nil
    end
    if WORD_START_ONLY[kw] then
        return padded_text:find(" " .. kw, 1, true) ~= nil
    end
    if WORD_EDGE_ONLY[kw] then
        local from = 1
        while true do
            local starts, ends = padded_text:find(kw, from, true)
            if not starts then return false end
            local before = padded_text:sub(starts - 1, starts - 1)
            local after = (ends < #padded_text) and padded_text:sub(ends + 1, ends + 1) or " "
            if not before:match("%a") or not after:match("%a") then return true end
            from = starts + 1
        end
    end
    return padded_text:find(kw, 1, true) ~= nil
end

function categorizer.classify(filename, folder_path)
    local name_lower = filename:lower():gsub("[_%-%.%(%)]", " ")
    local folder_lower = ""
    if folder_path then
        folder_lower = folder_path:lower():gsub("[_%-%.%(%)]", " ")
    end

    local padded_name = " " .. name_lower
    local padded_folder = " " .. folder_lower

    local scores = {}
    for cat, keywords in pairs(CATEGORY_KEYWORDS) do
        scores[cat] = 0
        for _, kw in ipairs(keywords) do
            local weight = WEAK_KEYWORDS[kw] and 1 or 2
            if keyword_found(padded_name, kw) then
                scores[cat] = scores[cat] + weight
            end
            if keyword_found(padded_folder, kw) then
                scores[cat] = scores[cat] + weight * 0.5
            end
        end
    end

    local best_cat = "other"
    local best_score = 0
    for _, cat in ipairs(CATEGORY_ORDER) do
        if scores[cat] and scores[cat] > best_score then
            best_score = scores[cat]
            best_cat = cat
        end
    end

    return best_cat, best_score > 0
end

function categorizer.classify_files(file_list)
    local results = {}
    local counts = {}
    for _, cat in ipairs(CATEGORY_ORDER) do counts[cat] = 0 end
    counts["other"] = 0

    for _, file_entry in ipairs(file_list) do
        local filename = file_entry.name or ""
        local folder = file_entry.full_path and file_entry.full_path:match("(.+)[/\\]") or ""
        local cat, matched = categorizer.classify(filename, folder)
        results[file_entry.full_path or filename] = cat
        counts[cat] = (counts[cat] or 0) + 1
    end

    return results, counts
end

function categorizer.get_category_color(category)
    return CATEGORY_COLORS[category] or CATEGORY_COLORS["other"]
end

function categorizer.get_category_order()
    return CATEGORY_ORDER
end

function categorizer.get_all_colors()
    return CATEGORY_COLORS
end

return categorizer
