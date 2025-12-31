-- @description TK_UndoTree
-- @author TouristKiller
-- @version 0.1
-- @changelog
--   + Initial proof of concept

local r = reaper
local ctx = r.ImGui_CreateContext('TK Undo Tree')

local COLORS = {
    bg = 0x1E1E2EFF,
    node_active = 0x7AA2F7FF,
    node_inactive = 0x565F89FF,
    branch_active = 0xA6E3A1FF,
    branch_inactive = 0x6C7086FF,
    text = 0xCDD6F4FF,
    text_dim = 0x6C7086FF,
    selected = 0xF5C2E7FF,
}

local undo_tree = {
    nodes = {},
    current_id = 0,
    root_id = 0,
    last_undo_state = nil,
    selected_node = nil,
}

local view = {
    zoom = 1.0,
    pan_x = 0,
    pan_y = 0,
    dragging = false,
}

local search_filter = ""
local filtered_nodes = {}

local function GenerateID()
    undo_tree.current_id = undo_tree.current_id + 1
    return undo_tree.current_id
end

local function CreateNode(description, parent_id)
    local node = {
        id = GenerateID(),
        description = description,
        parent_id = parent_id,
        children = {},
        timestamp = r.time_precise(),
        is_snapshot = false,
        snapshot_name = nil,
    }
    undo_tree.nodes[node.id] = node
    
    if parent_id and undo_tree.nodes[parent_id] then
        table.insert(undo_tree.nodes[parent_id].children, node.id)
    end
    
    return node
end

local function GetCurrentUndoState()
    local proj = 0
    local undo_desc = r.Undo_CanUndo2(proj)
    local redo_desc = r.Undo_CanRedo2(proj)
    return undo_desc, redo_desc
end

local function MonitorUndoChanges()
    local undo_desc, redo_desc = GetCurrentUndoState()
    local current_state = (undo_desc or "") .. "|" .. (redo_desc or "")
    
    if current_state ~= undo_tree.last_undo_state then
        if undo_desc and undo_desc ~= "" then
            local existing = nil
            for id, node in pairs(undo_tree.nodes) do
                if node.description == undo_desc then
                    existing = node
                    break
                end
            end
            
            if not existing then
                local parent_id = undo_tree.selected_node or undo_tree.root_id
                local new_node = CreateNode(undo_desc, parent_id)
                undo_tree.selected_node = new_node.id
            else
                undo_tree.selected_node = existing.id
            end
        end
        undo_tree.last_undo_state = current_state
    end
end

local function InitializeTree()
    if undo_tree.root_id == 0 then
        local root = CreateNode("Project Start", nil)
        undo_tree.root_id = root.id
        undo_tree.selected_node = root.id
    end
end

local function FilterNodes()
    filtered_nodes = {}
    local filter_lower = search_filter:lower()
    
    for id, node in pairs(undo_tree.nodes) do
        if search_filter == "" or node.description:lower():find(filter_lower, 1, true) then
            table.insert(filtered_nodes, node)
        end
    end
    
    table.sort(filtered_nodes, function(a, b) return a.timestamp < b.timestamp end)
end

local function GetNodeDepth(node_id, depth)
    depth = depth or 0
    local node = undo_tree.nodes[node_id]
    if not node or not node.parent_id then return depth end
    return GetNodeDepth(node.parent_id, depth + 1)
end

local function IsNodeInActiveBranch(node_id)
    if not undo_tree.selected_node then return false end
    
    local current = undo_tree.selected_node
    while current do
        if current == node_id then return true end
        local node = undo_tree.nodes[current]
        if not node then break end
        current = node.parent_id
    end
    return false
end

local function CountDescendants(node)
    if not node or #node.children == 0 then return 1 end
    local count = 0
    for _, child_id in ipairs(node.children) do
        count = count + CountDescendants(undo_tree.nodes[child_id])
    end
    return math.max(1, count)
end

local function DrawNode(draw_list, node, x, y, node_spacing_x, node_spacing_y)
    local is_active = IsNodeInActiveBranch(node.id)
    local is_selected = undo_tree.selected_node == node.id
    
    local node_color = is_active and COLORS.node_active or COLORS.node_inactive
    if is_selected then node_color = COLORS.selected end
    
    local radius = 8 * view.zoom
    
    r.ImGui_DrawList_AddCircleFilled(draw_list, x, y, radius, node_color)
    
    if node.is_snapshot then
        r.ImGui_DrawList_AddCircle(draw_list, x, y, radius + 3, COLORS.selected, 0, 2)
    end
    
    local total_height = CountDescendants(node) * node_spacing_y
    local current_y = y - total_height / 2 + node_spacing_y / 2
    
    for _, child_id in ipairs(node.children) do
        local child = undo_tree.nodes[child_id]
        if child then
            local child_height = CountDescendants(child) * node_spacing_y
            local child_x = x + node_spacing_x
            local child_y = current_y + child_height / 2 - node_spacing_y / 2
            
            local line_color = IsNodeInActiveBranch(child_id) and COLORS.branch_active or COLORS.branch_inactive
            local line_thickness = IsNodeInActiveBranch(child_id) and 3 or 1.5
            r.ImGui_DrawList_AddLine(draw_list, x + radius, y, child_x - radius, child_y, line_color, line_thickness * view.zoom)
            
            DrawNode(draw_list, child, child_x, child_y, node_spacing_x, node_spacing_y)
            
            current_y = current_y + child_height
        end
    end
    
    local mx, my = r.ImGui_GetMousePos(ctx)
    local dist = math.sqrt((mx - x)^2 + (my - y)^2)
    if dist < radius + 5 then
        r.ImGui_BeginTooltip(ctx)
        r.ImGui_Text(ctx, node.description)
        if node.is_snapshot then
            r.ImGui_Text(ctx, "Snapshot: " .. (node.snapshot_name or ""))
        end
        r.ImGui_EndTooltip(ctx)
        
        if r.ImGui_IsMouseClicked(ctx, 0) then
            undo_tree.selected_node = node.id
        end
        if r.ImGui_IsMouseDoubleClicked(ctx, 0) then
            r.ShowConsoleMsg("TODO: Navigate to undo point: " .. node.description .. "\n")
        end
    end
end

local function DrawTreeCanvas()
    local avail_w, avail_h = r.ImGui_GetContentRegionAvail(ctx)
    local canvas_width = avail_w * 0.7
    
    if r.ImGui_BeginChild(ctx, "TreeCanvas", canvas_width, avail_h, r.ImGui_ChildFlags_Border()) then
        local draw_list = r.ImGui_GetWindowDrawList(ctx)
        local canvas_x, canvas_y = r.ImGui_GetCursorScreenPos(ctx)
        
        if r.ImGui_IsWindowHovered(ctx) then
            local wheel = r.ImGui_GetMouseWheel(ctx)
            if wheel ~= 0 then
                view.zoom = math.max(0.3, math.min(3.0, view.zoom + wheel * 0.1))
            end
            
            if r.ImGui_IsMouseDragging(ctx, 2) then
                local dx, dy = r.ImGui_GetMouseDelta(ctx)
                view.pan_x = view.pan_x + dx
                view.pan_y = view.pan_y + dy
            end
        end
        
        local node_spacing_x = 80 * view.zoom
        local node_spacing_y = 50 * view.zoom
        
        local root = undo_tree.nodes[undo_tree.root_id]
        if root then
            local start_x = canvas_x + 50 + view.pan_x
            local start_y = canvas_y + avail_h / 2 + view.pan_y
            DrawNode(draw_list, root, start_x, start_y, node_spacing_x, node_spacing_y)
        end
        
        r.ImGui_EndChild(ctx)
    end
end

local function DrawSidebar()
    local avail_w, avail_h = r.ImGui_GetContentRegionAvail(ctx)
    
    r.ImGui_SameLine(ctx)
    
    if r.ImGui_BeginChild(ctx, "Sidebar", avail_w, avail_h, r.ImGui_ChildFlags_Border()) then
        r.ImGui_Text(ctx, "Search:")
        r.ImGui_SameLine(ctx)
        local changed
        changed, search_filter = r.ImGui_InputText(ctx, "##search", search_filter)
        if changed then FilterNodes() end
        
        r.ImGui_Separator(ctx)
        
        if r.ImGui_Button(ctx, "Create Snapshot", -1, 0) then
            if undo_tree.selected_node then
                local node = undo_tree.nodes[undo_tree.selected_node]
                if node then
                    node.is_snapshot = true
                    node.snapshot_name = "Snapshot " .. os.date("%H:%M:%S")
                end
            end
        end
        
        if r.ImGui_Button(ctx, "Reset View", -1, 0) then
            view.zoom = 1.0
            view.pan_x = 0
            view.pan_y = 0
        end
        
        r.ImGui_Separator(ctx)
        r.ImGui_Text(ctx, "Active Branch:")
        
        if r.ImGui_BeginChild(ctx, "HistoryList", -1, -1, 0) then
            local current = undo_tree.selected_node
            local branch_nodes = {}
            
            while current do
                table.insert(branch_nodes, 1, undo_tree.nodes[current])
                local node = undo_tree.nodes[current]
                if not node then break end
                current = node.parent_id
            end
            
            for i, node in ipairs(branch_nodes) do
                if node then
                    local label = node.description
                    if node.is_snapshot then
                        label = "★ " .. label
                    end
                    
                    local is_selected = undo_tree.selected_node == node.id
                    if r.ImGui_Selectable(ctx, label, is_selected) then
                        undo_tree.selected_node = node.id
                    end
                end
            end
            
            r.ImGui_EndChild(ctx)
        end
        
        r.ImGui_EndChild(ctx)
    end
end

local function Main()
    MonitorUndoChanges()
    
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), COLORS.bg)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), COLORS.text)
    
    local visible, open = r.ImGui_Begin(ctx, 'TK Undo Tree v0.1', true, r.ImGui_WindowFlags_None())
    
    if visible then
        r.ImGui_Text(ctx, "Zoom: " .. string.format("%.1f", view.zoom) .. "x | Right-drag to pan | Scroll to zoom")
        r.ImGui_Text(ctx, "Nodes: " .. undo_tree.current_id .. " | Selected: " .. (undo_tree.selected_node or "none"))
        r.ImGui_Separator(ctx)
        
        DrawTreeCanvas()
        DrawSidebar()
        
        r.ImGui_End(ctx)
    end
    
    r.ImGui_PopStyleColor(ctx, 2)
    
    if open then
        r.defer(Main)
    end
end

InitializeTree()
FilterNodes()
Main()
