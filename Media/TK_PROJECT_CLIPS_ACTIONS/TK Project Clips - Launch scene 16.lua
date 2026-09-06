local here = debug.getinfo(1, "S").source:match("@?(.*[\\/])")
dofile(here .. "bridge.lua")("launch_scene_16")