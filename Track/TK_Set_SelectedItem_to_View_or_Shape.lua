-- @description TK_Set_SelectedItem_to_View_or_Shape
-- @author TouristKiller
-- @version 0.1.0
-- @changelog 
--[[
+ Initial release on ReaPack
]]--

local r = reaper
local ctx = r.ImGui_CreateContext('Note Shape Selector')
local font = r.ImGui_CreateFont('Arial', 12)
r.ImGui_Attach(ctx, font)

local selected_shape = 0
local selected_view = 0
local shapes = {
    {name = "Normal", cmd = 40449},
    {name = "Diamond", cmd = 40450},
    {name = "Triangle", cmd = 40448}
}
local views = {
    {name = "Named Notes", cmd = 40043},
    {name = "Piano Roll", cmd = 40042},
    {name = "Notation", cmd = 40954}
}

local function SaveTrackView(track, cmd)
    local guid = r.GetTrackGUID(track)
    local key = "TrackView_" .. guid
    r.SetProjExtState(0, "ViewSettings", key, tostring(cmd))
end

local function ProcessItems(cmd, isView)
    local num_items = r.CountSelectedMediaItems(0)
    local selected_items = {}
    
    for i = 0, num_items-1 do
        selected_items[i] = r.GetSelectedMediaItem(0, i)
        local track = r.GetMediaItem_Track(selected_items[i])
        
        if isView then
            r.GetSetMediaTrackInfo_String(track, "P_EXT:TKVIEW", tostring(cmd), true)
        else
            r.GetSetMediaTrackInfo_String(track, "P_EXT:TKSHAPE", tostring(cmd), true)
        end
    end
    
    for i = 0, num_items-1 do
        r.SelectAllMediaItems(0, false)
        r.SetMediaItemSelected(selected_items[i], true)
        r.Main_OnCommand(40153, 0)
        r.MIDIEditor_LastFocused_OnCommand(cmd, 0)
    end
    
    r.SelectAllMediaItems(0, false)
    for i = 0, num_items-1 do
        r.SetMediaItemSelected(selected_items[i], true)
    end
    
    r.SetExtState("TKMonitor", "LastTrackGUID", "", false)
end

local function loop()
    r.ImGui_PushFont(ctx, font)
    local visible, open = r.ImGui_Begin(ctx, 'Note Shape Selector', true, r.ImGui_WindowFlags_AlwaysAutoResize() | r.ImGui_WindowFlags_NoTitleBar())
    if visible then
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 5.0)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), 0x000000FF)
        
        r.ImGui_Text(ctx, 'Select shape:')
        for i, shape in ipairs(shapes) do
            if r.ImGui_RadioButton(ctx, shape.name, selected_shape == i-1) then
                selected_shape = i-1
            end
        end
        r.ImGui_Text(ctx, '\nSelect view:')
        for i, view in ipairs(views) do
            if r.ImGui_RadioButton(ctx, view.name, selected_view == i-1) then
                selected_view = i-1
            end
        end
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x0000FFFF)
        if r.ImGui_Button(ctx, 'Apply Shape') then
            ProcessItems(shapes[selected_shape + 1].cmd, false)
        end
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, 'Apply View') then
            ProcessItems(views[selected_view + 1].cmd, true)
        end
        r.ImGui_PopStyleColor(ctx)
        r.ImGui_SameLine(ctx)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0xFF0000FF)
        if r.ImGui_Button(ctx, 'X') then
            open = false
        end
        r.ImGui_PopStyleColor(ctx)
        r.ImGui_PopStyleVar(ctx)
        r.ImGui_PopStyleColor(ctx)
        r.ImGui_End(ctx)
    end
    r.ImGui_PopFont(ctx)
    if open then
        r.defer(loop)
    end
end
r.defer(loop)
