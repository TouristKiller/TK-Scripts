-- TK Theme Bit - the MIX view key (see TK_Theme_Bit_View.lua)
local dir = ({reaper.get_action_context()})[2]:match("^(.*)[\\/]")
dofile(dir .. "/TK_Theme_Bit_View.lua").run(1)
