-- Minimal test voor icon-font
local r = reaper
local script_path = debug.getinfo(1, "S").source:match("@?(.*[/\\])")
local ctx = r.ImGui_CreateContext('IconFontTest')
local IconFont = r.ImGui_CreateFont(script_path .. 'Icons-Regular.otf', 12)
r.ImGui_Attach(ctx, IconFont)

function Main()
    local visible = r.ImGui_Begin(ctx, "Test", true)
    if visible then
        r.ImGui_PushFont(ctx, IconFont, 12)
        r.ImGui_Text(ctx, "Instellingen-icoon: \u{0047}")
        r.ImGui_Button(ctx, "\u{0047}", 40, 40)
        r.ImGui_PopFont(ctx)
        r.ImGui_End(ctx)
    end
    if visible then r.defer(Main) end
end

Main()