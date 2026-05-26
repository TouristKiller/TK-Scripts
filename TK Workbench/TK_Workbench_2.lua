-- @description TK Workbench 2
-- @author TouristKiller
-- @version 1.0
-- @changelog:
--   + Secondary launcher using separate config_2.json

local script_path = debug.getinfo(1, "S").source:match("@?(.*[\\/])") or ""

_G.TK_WORKBENCH_SCRIPT_NAME = "TK Workbench 2"
_G.TK_WORKBENCH_CONFIG_NAME = "config_2.json"
dofile(script_path .. "TK_Workbench.lua")
_G.TK_WORKBENCH_SCRIPT_NAME = nil
_G.TK_WORKBENCH_CONFIG_NAME = nil
