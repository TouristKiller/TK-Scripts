local here = debug.getinfo(1, "S").source:match("@?(.*[\\/])")
dofile(here .. "bridge.lua")("stop_all")