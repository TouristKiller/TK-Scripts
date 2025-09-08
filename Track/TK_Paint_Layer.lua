-- @description TK Paint Layer
-- @author TouristKiller
-- @version 0.0.1
-- @changelog 
--[[
+ Initial release
]]--

-- inspired by an idea from FerroPop
----------------------------------------------------------------------------------
local r                             = reaper
local SCRIPT_DIR                    = debug.getinfo(1, 'S').source:match('^@?(.*[\\/])') or ''
package.path                        = SCRIPT_DIR .. '?.lua;' .. package.path
local ok_json, json                 = pcall(require, 'paint_json')
if not ok_json or type(json) ~= 'table' then return end
package.path                        = r.ImGui_GetBuiltinPath() .. '/?.lua;' .. package.path
local im                            = require 'imgui' '0.9.3'

local ctx                           = r.ImGui_CreateContext('TK Paint Layer')
local font                          = r.ImGui_CreateFont('Arial', 14)
r.ImGui_Attach(ctx, font)

local SECTION                       = 'TK_PAINT_LAYER'
local KEY_AREAS                     = 'areas'
local paint_areas                   = {}
local group_names                   = {}
local needs_save                    = false
local last_track_count              = -1
local guid_cache                    = {}
local group_counter                 = 0
local main_hwnd                     = r.GetMainHwnd()
local arrange_hwnd                  = r.JS_Window_FindChildByID(main_hwnd, 0x3E8)
local LEFT, TOP, RIGHT, BOTTOM      = 0, 0, 0, 0
local scroll_size                   = 15
local screen_scale                  = 1
local merged_mode                   = false
local outline_mode                  = false
local draw_mode                     = false   
local is_drawing                    = false
local drag_start_x, drag_start_y    = 0,0
local drag_cur_x, drag_cur_y        = 0,0
local groups_sort_by_id             = false   
local master_opacity_factor         = 1.0     
local manager_x1, manager_y1        = 0,0
local manager_x2, manager_y2        = -1,-1

---------------------------------------------------------------------------


local function Col(r8,g8,b8,a8)
	a8 = a8 or 255
	return (r8<<24)|(g8<<16)|(b8<<8)|a8
end

local function GenID()
	return tostring(os.time()) .. '_' .. tostring(math.random(1, 10 ^ 9))
end

local function RandomPastel()
	local rC = math.random(80, 200)
	local gC = math.random(80, 200)
	local bC = math.random(80, 200)
	local a = 120
	return (a << 24) | (rC << 16) | (gC << 8) | bC
end

local function TrackColorARGB(track)
	local native = r.GetTrackColor(track)
	if native == 0 then return RandomPastel() end
	local rC, gC, bC = r.ColorFromNative(native)
	local a = 120
	return (a << 24) | (rC << 16) | (gC << 8) | bC
end

local function ARGB_to_U32(argb)
	local a  = (argb >> 24) & 0xFF
	local rC = (argb >> 16) & 0xFF
	local gC = (argb >> 8)  & 0xFF
	local bC = (argb)       & 0xFF
	return r.ImGui_ColorConvertDouble4ToU32(rC / 255, gC / 255, bC / 255, a / 255)
end

local function GetTrackByGUID(guid)
	local cnt = r.CountTracks(0)
	for i = 0, cnt - 1 do
		local tr = r.GetTrack(0, i)
		if r.GetTrackGUID(tr) == guid then return tr end
	end
end

local function RebuildTrackGUIDCache()
	guid_cache = {}
	local cnt = r.CountTracks(0)
	for i = 0, cnt - 1 do
		local tr = r.GetTrack(0, i)
		guid_cache[r.GetTrackGUID(tr)] = true
	end
end

local function UpdateMissingFlags()
	RebuildTrackGUIDCache()
	for _, a in ipairs(paint_areas) do
		if guid_cache[a.track_guid] then
			if a.missing then a.missing = nil end
		else
			a.missing = true
		end
	end
end

local function PurgeOrphans()
	RebuildTrackGUIDCache()
	local removed = false
	for i = #paint_areas, 1, -1 do
		if not guid_cache[paint_areas[i].track_guid] then
			table.remove(paint_areas, i)
			removed = true
		end
	end
	if removed then needs_save = true end
end

local function LoadAreas()
	local legacy = r.GetExtState(SECTION, KEY_AREAS)
	if legacy ~= '' then
		r.SetProjExtState(0, SECTION, KEY_AREAS, legacy)
		r.DeleteExtState(SECTION, KEY_AREAS, true)
	end

	local rv, data = r.GetProjExtState(0, SECTION, KEY_AREAS)
	if rv == 1 and data ~= '' then
		local ok, decoded = pcall(json.decode, data)
		if ok and type(decoded) == 'table' then
			paint_areas = decoded
			for _, a in ipairs(paint_areas) do
				if a.group_id and a.group_id > group_counter then
					group_counter = a.group_id
				end
			end
		end
	end

	local rv2, gns = r.GetProjExtState(0, SECTION, 'groups')
	if rv2 == 1 and gns ~= '' then
		local ok2, decoded2 = pcall(json.decode, gns)
		if ok2 and type(decoded2) == 'table' then
			group_names = decoded2
		end
	end

	
	local _, mm = r.GetProjExtState(0, SECTION, 'merged_mode')
	merged_mode = (mm == '1')
	local _, om = r.GetProjExtState(0, SECTION, 'outline_mode')
	outline_mode = (om == '1')
	local _, gs = r.GetProjExtState(0, SECTION, 'groups_sort_by_id')
	groups_sort_by_id = (gs == '1')
	local _, mo = r.GetProjExtState(0, SECTION, 'master_opacity')
	if mo ~= '' then
		local mv = tonumber(mo)
		if mv and mv >= 0 and mv <= 1 then master_opacity_factor = mv end
	end
end

local function SaveAreas(force)
	if not (needs_save or force) then return end
	local ok, encoded = pcall(json.encode, paint_areas)
	if ok then
		r.SetProjExtState(0, SECTION, KEY_AREAS, encoded)
	end
	local ok2, encoded2 = pcall(json.encode, group_names)
	if ok2 then
		r.SetProjExtState(0, SECTION, 'groups', encoded2)
	end
	needs_save = false
end

local function GetArrangeRect()
	if not r.ValidatePtr(arrange_hwnd, 'HWND') then
		arrange_hwnd = r.JS_Window_FindChildByID(main_hwnd, 0x3E8)
	end
	if not arrange_hwnd then return end
	local _, l, t, rgt, btm = r.JS_Window_GetRect(arrange_hwnd)
	LEFT, TOP   = r.ImGui_PointConvertNative(ctx, l, t)
	RIGHT, BOTTOM = r.ImGui_PointConvertNative(ctx, rgt, btm)
end

local function GetVisibleTimeRange()
	local start_time, end_time = r.GetSet_ArrangeView2(0, false, 0, 0)
	return start_time, end_time
end

local function TimeToPixel(time, start_time, end_time)
	local w = (RIGHT - LEFT) - scroll_size
	if end_time == start_time then return LEFT end
	local rel = (time - start_time) / (end_time - start_time)
	return LEFT + (w * rel)
end

local function PixelToTime(px, start_time, end_time)
	local w = (RIGHT - LEFT) - scroll_size
	if w <= 0 then return start_time end
	local rel = (px - LEFT) / w
	if rel < 0 then rel = 0 elseif rel > 1 then rel = 1 end
	return start_time + rel * (end_time - start_time)
end

local function GetTrackYH(track)
	local y = r.GetMediaTrackInfo_Value(track, 'I_TCPY') / screen_scale
	local h = r.GetMediaTrackInfo_Value(track, 'I_TCPH') / screen_scale
	return y, h
end

local function GetVisibleEnvelopeLanes(track)
	local lanes = {}
	local env_cnt = r.CountTrackEnvelopes(track)
	for i = 0, env_cnt - 1 do
		local env = r.GetTrackEnvelope(track, i)
		if env then
			local vis = r.GetEnvelopeInfo_Value(env, 'I_TCPVISIBLE') or 0
			if vis > 0 then
				local y = r.GetEnvelopeInfo_Value(env, 'I_TCPY') or -1
				local h = r.GetEnvelopeInfo_Value(env, 'I_TCPH') or -1
				if y >= 0 and h > 0 then
					lanes[#lanes + 1] = { y = y / screen_scale, h = h / screen_scale }
				end
			end
		end
	end
	return lanes
end

local function CaptureRazorEdits()
	local added = 0
	local cnt = r.CountTracks(0)
	local time_groups = {}
	local existing_keys = {}

	for _, a in ipairs(paint_areas) do
		local key = string.format('%.6f_%.6f', a.start, a.stop)
		if a.group_id and not time_groups[key] then
			time_groups[key] = a.group_id
			if a.group_id > group_counter then group_counter = a.group_id end
		end
		local tkey = table.concat({ a.track_guid, string.format('%.6f', a.start), string.format('%.6f', a.stop) }, '|')
		existing_keys[tkey] = true
	end

	local collected = {}
	for i = 0, cnt - 1 do
		local tr = r.GetTrack(0, i)
		local ok, str = r.GetSetMediaTrackInfo_String(tr, 'P_RAZOREDITS', '', false)
		if ok and str ~= '' then
			for start_s, end_s in str:gmatch('([%d%.]+)%s+([%d%.]+)%s+([^%s]+)') do
				local st = tonumber(start_s)
				local en = tonumber(end_s)
				if st and en and en > st then
					table.insert(collected, { track = tr, start = st, stop = en })
				end
			end
		end
	end

	table.sort(collected, function(a, b)
		if a.start == b.start then return a.stop < b.stop end
		return a.start < b.start
	end)

	for _, c in ipairs(collected) do
		local key = string.format('%.6f_%.6f', c.start, c.stop)
		local gid = time_groups[key]
		if not gid then
			group_counter = group_counter + 1
			gid = group_counter
			time_groups[key] = gid
		end
		local track_guid = r.GetTrackGUID(c.track)
		local tkey = table.concat({ track_guid, string.format('%.6f', c.start), string.format('%.6f', c.stop) }, '|')
		if not existing_keys[tkey] then
			paint_areas[#paint_areas + 1] = {
				id = GenID(),
				track_guid = track_guid,
				start = c.start,
				stop = c.stop,
				color = TrackColorARGB(c.track),
				label = '',
				mode = 'time',
				group_id = gid
			}
			existing_keys[tkey] = true
			added = added + 1
		end
	end

	if added > 0 then
		needs_save = true
		r.UpdateArrange()
	end
	return added
end

local function RemoveArea(id)
	for i = #paint_areas, 1, -1 do
		if paint_areas[i].id == id then
			table.remove(paint_areas, i)
			needs_save = true
			return true
		end
	end
end

local function ClearAll()
	if #paint_areas == 0 then return end
	paint_areas = {}
	needs_save = true
end

local ui_visible = true

local function DrawManager()
	r.ImGui_SetNextWindowSize(ctx, 400, 360, r.ImGui_Cond_FirstUseEver())
	r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowRounding(), 6)
	r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(),        Col(55,55,55,255))
	r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), Col(75,75,75,255))
	r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(),  Col(40,40,40,255))
	r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(),       Col(50,50,50,255))     
	r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(),Col(70,70,70,255))
	r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(), Col(90,90,90,255))
	r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrab(),    Col(130,130,130,255))
	r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrabActive(), Col(160,160,160,255))
	local visible, open = r.ImGui_Begin(ctx, 'Paint Areas##tkpaint', true, r.ImGui_WindowFlags_NoCollapse() | r.ImGui_WindowFlags_TopMost())
	if visible then
		local wx, wy = r.ImGui_GetWindowPos(ctx)
		local ww, wh = r.ImGui_GetWindowSize(ctx)
		manager_x1, manager_y1 = wx, wy
		manager_x2, manager_y2 = wx + ww, wy + wh
		if r.ImGui_Button(ctx, 'Add from Razor Edits') then
			local n = CaptureRazorEdits()
			if n == 0 then r.ShowMessageBox('No Razor Edits found.', 'Info', 0) end
		end
		r.ImGui_SameLine(ctx)
		if r.ImGui_Button(ctx, 'Save') then SaveAreas(true) end
		r.ImGui_SameLine(ctx)
		if r.ImGui_Button(ctx, 'Reload') then LoadAreas() end
		r.ImGui_SameLine(ctx)
		if r.ImGui_Button(ctx, 'Clear All') then
			if r.MB('Clear everything?', 'Confirm', 4) == 6 then
				ClearAll()
			end
		end
		r.ImGui_SameLine(ctx)
		if r.ImGui_Button(ctx, 'Refresh Orphans') then PurgeOrphans() end
		r.ImGui_SameLine(ctx)
		if r.ImGui_Button(ctx, 'Help') then
			r.ImGui_OpenPopup(ctx, 'Help##tkpaint')
		end

		-- Help popup
		if r.ImGui_BeginPopupModal(ctx, 'Help##tkpaint', nil, r.ImGui_WindowFlags_AlwaysAutoResize()) then
			r.ImGui_TextWrapped(ctx, 'TK Paint Layer - Quick Help')
			r.ImGui_Separator(ctx)
			r.ImGui_TextWrapped(ctx, 'Purpose: Visually mark time spans per track (and envelope lanes) grouped across tracks. Data is stored in the project and restored on reload.')
			r.ImGui_Separator(ctx)
			r.ImGui_Text(ctx, 'Top Buttons:')
			r.ImGui_BulletText(ctx, 'Add from Razor Edits: import current razor edits; identical time ranges share a group.')
			r.ImGui_BulletText(ctx, 'Save: force write to project ext-state (auto-saves periodically).')
			r.ImGui_BulletText(ctx, 'Reload: re-read saved areas from project.')
			r.ImGui_BulletText(ctx, 'Clear All: remove every area (confirmation asked).')
			r.ImGui_BulletText(ctx, 'Refresh Orphans: delete areas whose tracks no longer exist.')
			r.ImGui_Separator(ctx)
			r.ImGui_Text(ctx, 'Toggles / Slider:')
			r.ImGui_BulletText(ctx, 'Merged group blocks: draw one vertical block spanning all tracks (incl. visible envelopes) in each group.')
			r.ImGui_BulletText(ctx, 'Outline only: draw borders without fill.')
			r.ImGui_BulletText(ctx, 'Draw mode: drag in the arrange (outside this window) to create a new grouped span across intersected tracks.')
			r.ImGui_BulletText(ctx, 'Sort by group ID: list groups numerically instead of by time.')
			r.ImGui_BulletText(ctx, 'Master Opacity: global multiplier applied at draw time (non‑destructive).')
			r.ImGui_Separator(ctx)
			r.ImGui_Text(ctx, 'Group Row:')
			r.ImGui_BulletText(ctx, 'Tree header shows group id and time range.')
			r.ImGui_BulletText(ctx, 'Color square: change color for all areas in the group (alpha preserved).')
			r.ImGui_BulletText(ctx, 'Name field: assign a custom group label.')
			r.ImGui_BulletText(ctx, 'Group alpha slider: adjusts alpha for every area in the group.')
			r.ImGui_Separator(ctx)
			r.ImGui_Text(ctx, 'Area Table Columns:')
			r.ImGui_BulletText(ctx, 'Track / Time: target track (track # + name) and time span.')
			r.ImGui_BulletText(ctx, 'Label: per-area note (optional).')
			r.ImGui_BulletText(ctx, 'Opacity: per-area alpha (overridden by group + master factors multiplicatively).')
			r.ImGui_BulletText(ctx, 'Del: remove that area.')
			r.ImGui_Separator(ctx)
			r.ImGui_Text(ctx, 'Notes:')
			r.ImGui_BulletText(ctx, 'Tracks temporarily missing are flagged until deleted or restored.')
			r.ImGui_BulletText(ctx, 'Envelope lanes (visible only) also get painted rectangles.')
			r.ImGui_BulletText(ctx, 'All settings & areas are saved inside the project (ext-state).')
			r.ImGui_BulletText(ctx, 'You can mix draw-created areas with imported razor edit areas freely.')
			r.ImGui_Separator(ctx)
			if r.ImGui_Button(ctx, 'Close##helpclose') then
				r.ImGui_CloseCurrentPopup(ctx)
			end
			r.ImGui_EndPopup(ctx)
		end

		local changedMerge, newMerge = r.ImGui_Checkbox(ctx, 'Merged group blocks', merged_mode)
		if changedMerge then
			merged_mode = newMerge
			r.SetProjExtState(0, SECTION, 'merged_mode', merged_mode and '1' or '0')
		end
		r.ImGui_SameLine(ctx)
		local changedOutline, newOutline = r.ImGui_Checkbox(ctx, 'Outline only', outline_mode)
		if changedOutline then
			outline_mode = newOutline
			r.SetProjExtState(0, SECTION, 'outline_mode', outline_mode and '1' or '0')
		end
		r.ImGui_SameLine(ctx)
		local changedDraw, newDraw = r.ImGui_Checkbox(ctx, 'Draw mode', draw_mode)
		if changedDraw then
			draw_mode = newDraw
			if not draw_mode and is_drawing then is_drawing = false end
		end
		r.ImGui_SameLine(ctx)
		local changedSort, newSort = r.ImGui_Checkbox(ctx, 'Sort by group ID', groups_sort_by_id)
		if changedSort then
			groups_sort_by_id = newSort
			r.SetProjExtState(0, SECTION, 'groups_sort_by_id', groups_sort_by_id and '1' or '0')
		end

		local master_pct = math.floor(master_opacity_factor * 100 + 0.5)
		local mp_changed, mp_new = r.ImGui_SliderInt(ctx, 'Master Opacity', master_pct, 0, 100)
		if mp_changed then
			master_opacity_factor = math.max(0, math.min(1, mp_new / 100))
			r.SetProjExtState(0, SECTION, 'master_opacity', string.format('%.4f', master_opacity_factor))
		end

		r.ImGui_Separator(ctx)
		r.ImGui_BeginChild(ctx, 'list', -1, -1)

		local groups = {}
		local order = {}
		for idx, a in ipairs(paint_areas) do
			if not a.group_id then
				group_counter = group_counter + 1
				a.group_id = group_counter
			end
			local g = groups[a.group_id]
			if not g then
				g = { id = a.group_id, start = a.start, stop = a.stop, areas = {} }
				groups[a.group_id] = g
				table.insert(order, g)
			end
			table.insert(g.areas, idx)
		end

		if groups_sort_by_id then
			table.sort(order, function(a,b) return a.id < b.id end)
		else
			table.sort(order, function(a, b)
				if a.start == b.start then return a.stop < b.stop end
				return a.start < b.start
			end)
		end

		for _, g in ipairs(order) do
			local gname = group_names[g.id] or ''
			local base_header = string.format('Group %d (%.2f - %.2f)##grp%d', g.id, g.start, g.stop, g.id)
			local open_node = r.ImGui_TreeNode(ctx, base_header)
			r.ImGui_SameLine(ctx)
			if gname ~= '' then r.ImGui_Text(ctx, '[' .. gname .. ']') else r.ImGui_Text(ctx, '') end

			if open_node then
				table.sort(g.areas, function(aIdx, bIdx)
					local a = paint_areas[aIdx]
					local b = paint_areas[bIdx]
					if not a or not b then return false end
					local trA = GetTrackByGUID(a.track_guid)
					local trB = GetTrackByGUID(b.track_guid)
					local tnA = trA and (math.floor(r.GetMediaTrackInfo_Value(trA, 'IP_TRACKNUMBER') or 0)) or 99999
					local tnB = trB and (math.floor(r.GetMediaTrackInfo_Value(trB, 'IP_TRACKNUMBER') or 0)) or 99999
					if tnA == tnB then
						if a.start == b.start then return a.stop < b.stop end
						return a.start < b.start
					end
					return tnA < tnB
				end)
				local first_area = paint_areas[g.areas[1]]
				local col = first_area and first_area.color or 0x80FFFFFF
				local aA = (col >> 24) & 0xFF
				local rR = (col >> 16) & 0xFF
				local gG = (col >> 8) & 0xFF
				local bB = col & 0xFF
				local u32 = r.ImGui_ColorConvertDouble4ToU32(rR / 255, gG / 255, bB / 255, 1)

				r.ImGui_SameLine(ctx)
				if r.ImGui_ColorButton(ctx, '##grpclr' .. g.id, u32) then
					r.ImGui_OpenPopup(ctx, 'GrpClr' .. g.id)
				end
				if r.ImGui_BeginPopup(ctx, 'GrpClr' .. g.id) then
					local changedColor, new_u32 = r.ImGui_ColorPicker4(ctx, '##gpc' .. g.id, u32)
					if changedColor then
						local rF, gF, bF = r.ImGui_ColorConvertU32ToDouble4(new_u32)
						local r8 = math.floor(rF * 255 + 0.5)
						local g8 = math.floor(gF * 255 + 0.5)
						local b8 = math.floor(bF * 255 + 0.5)
						for _, ai in ipairs(g.areas) do
							local ar = paint_areas[ai]
							local alpha = (ar.color >> 24) & 0xFF
							ar.color = (alpha << 24) | (r8 << 16) | (g8 << 8) | b8
						end
						needs_save = true
					end
					if r.ImGui_Button(ctx, 'Close##gpc' .. g.id) then
						r.ImGui_CloseCurrentPopup(ctx)
					end
					r.ImGui_EndPopup(ctx)
				end

				r.ImGui_SameLine(ctx)
				local avg_alpha = aA
				r.ImGui_PushItemWidth(ctx, 140)
				local changedName, newName = r.ImGui_InputText(ctx, '##gn' .. g.id, gname)
				r.ImGui_PopItemWidth(ctx)
				if changedName then
					group_names[g.id] = newName
					needs_save = true
				end
				r.ImGui_SameLine(ctx)
				r.ImGui_PushItemWidth(ctx, 100)
				local al_changed, newA = r.ImGui_SliderInt(ctx, '##ga' .. g.id, avg_alpha, 10, 255)
				r.ImGui_PopItemWidth(ctx)
				if al_changed then
					for _, ai in ipairs(g.areas) do
						local ar = paint_areas[ai]
						local rC = (ar.color >> 16) & 0xFF
						local gC = (ar.color >> 8) & 0xFF
						local bC = ar.color & 0xFF
						ar.color = (newA << 24) | (rC << 16) | (gC << 8) | bC
					end
					needs_save = true
				end

				r.ImGui_Separator(ctx)
				local tbl_flags = r.ImGui_TableFlags_SizingFixedFit() | r.ImGui_TableFlags_NoSavedSettings() | r.ImGui_TableFlags_BordersInnerV()
				if r.ImGui_BeginTable(ctx, 'areas_tbl' .. g.id, 4, tbl_flags) then
					r.ImGui_TableSetupColumn(ctx, 'Track / Time', r.ImGui_TableColumnFlags_WidthStretch())
					r.ImGui_TableSetupColumn(ctx, 'Label', r.ImGui_TableColumnFlags_WidthFixed(), 140)
					r.ImGui_TableSetupColumn(ctx, 'Opacity', r.ImGui_TableColumnFlags_WidthFixed(), 80)
					r.ImGui_TableSetupColumn(ctx, 'Del', r.ImGui_TableColumnFlags_WidthFixed(), 32)
					for _, ai in ipairs(g.areas) do
						local area = paint_areas[ai]
						r.ImGui_PushID(ctx, area.id)
						local tr = GetTrackByGUID(area.track_guid)
						local name = 'Track removed'
						if tr then
							local _, tn = r.GetTrackName(tr)
							local tnum = math.floor(r.GetMediaTrackInfo_Value(tr, 'IP_TRACKNUMBER') or 0)
							name = string.format('%02d %s', tnum, tn)
							if area.missing then area.missing = nil end
						elseif area.missing then
							name = name .. ' (orphan)'
						end

						r.ImGui_TableNextRow(ctx)
						r.ImGui_TableSetColumnIndex(ctx, 0)
						r.ImGui_Text(ctx, string.format('%s  (%.2f - %.2f)', name, area.start, area.stop))

						r.ImGui_TableSetColumnIndex(ctx, 1)
						r.ImGui_PushItemWidth(ctx, -1)
						local changedLabel, newLabel = r.ImGui_InputText(ctx, '##lbl', area.label or '')
						r.ImGui_PopItemWidth(ctx)
						if changedLabel then
							area.label = newLabel
							needs_save = true
						end

						r.ImGui_TableSetColumnIndex(ctx, 2)
						local aI = (area.color >> 24) & 0xFF
						r.ImGui_PushItemWidth(ctx, -1)
						local ia_changed, ia_new = r.ImGui_SliderInt(ctx, '##A', aI, 0, 255)
						r.ImGui_PopItemWidth(ctx)
						if ia_changed then
							local rC = (area.color >> 16) & 0xFF
							local gC = (area.color >> 8) & 0xFF
							local bC = area.color & 0xFF
							area.color = (ia_new << 24) | (rC << 16) | (gC << 8) | bC
							needs_save = true
						end

						r.ImGui_TableSetColumnIndex(ctx, 3)
						if r.ImGui_Button(ctx, 'X') then
							RemoveArea(area.id)
							r.ImGui_PopID(ctx)
							break
						end
						r.ImGui_PopID(ctx)
					end
					r.ImGui_EndTable(ctx)
				end
				r.ImGui_TreePop(ctx)
			end
			r.ImGui_Separator(ctx)
		end

		r.ImGui_EndChild(ctx)
	end
	r.ImGui_End(ctx)
	r.ImGui_PopStyleColor(ctx, 8)
	r.ImGui_PopStyleVar(ctx)
	ui_visible = open
end

local overlay_base_flags =
	r.ImGui_WindowFlags_NoTitleBar() |
	r.ImGui_WindowFlags_NoResize() |
	r.ImGui_WindowFlags_NoNav() |
	r.ImGui_WindowFlags_NoScrollbar() |
	r.ImGui_WindowFlags_NoDecoration() |
	r.ImGui_WindowFlags_NoDocking() |
	r.ImGui_WindowFlags_NoBackground() |
	r.ImGui_WindowFlags_NoMove()

local function DrawOverlay()
	GetArrangeRect()
	r.ImGui_SetNextWindowPos(ctx, LEFT, TOP)
	r.ImGui_SetNextWindowSize(ctx, (RIGHT - LEFT) - scroll_size, (BOTTOM - TOP) - scroll_size)
	r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), 0x00000000)
	r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowBorderSize(), 0)
	r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowRounding(), 3)
	local flags = overlay_base_flags
	if not draw_mode then flags = flags | r.ImGui_WindowFlags_NoInputs() end
	local visible = r.ImGui_Begin(ctx, 'TK Paint Overlay', false, flags)
	if visible then
		local dl = r.ImGui_GetWindowDrawList(ctx)
		local start_time, end_time = GetVisibleTimeRange()
		if end_time > start_time then
			if draw_mode then
				local mx, my = r.ImGui_GetMousePos(ctx)
				if r.ImGui_IsMouseClicked(ctx, 0) then
					local over_manager = (mx >= manager_x1 and mx <= manager_x2 and my >= manager_y1 and my <= manager_y2)
					if (not over_manager) and mx >= LEFT and mx <= (RIGHT - scroll_size) and my >= TOP and my <= (BOTTOM - TOP) then
						is_drawing = true
						drag_start_x, drag_start_y = mx, my
						drag_cur_x, drag_cur_y = mx, my
					end
				end
				if is_drawing then
					drag_cur_x, drag_cur_y = mx, my
					local x1, y1 = drag_start_x, drag_start_y
					local x2, y2 = drag_cur_x, drag_cur_y
					if x1 > x2 then x1, x2 = x2, x1 end
					if y1 > y2 then y1, y2 = y2, y1 end
					if x1 < LEFT then x1 = LEFT end
					if x2 > (RIGHT - scroll_size) then x2 = RIGHT - scroll_size end
					if y1 < TOP then y1 = TOP end
					if y2 > (BOTTOM - scroll_size) then y2 = BOTTOM - scroll_size end
					local prev_fill = Col(80,140,230,60)
					local prev_border = Col(80,140,230,200)
					r.ImGui_DrawList_AddRectFilled(dl, x1, y1, x2, y2, prev_fill, 3)
					r.ImGui_DrawList_AddRect(dl, x1, y1, x2, y2, prev_border, 3, 0, 2)
					if r.ImGui_IsMouseReleased(ctx, 0) then
						local t1 = PixelToTime(x1, start_time, end_time)
						local t2 = PixelToTime(x2, start_time, end_time)
						if t2 < t1 then t1, t2 = t2, t1 end
						if (t2 - t1) > 1e-5 then
							group_counter = group_counter + 1
							local gid = group_counter
							local track_cnt = r.CountTracks(0)
							for i = 0, track_cnt - 1 do
								local tr = r.GetTrack(0, i)
								local ty, th = GetTrackYH(tr)
								if th > 0 then
									local y_tr1 = TOP + ty
									local y_tr2 = y_tr1 + th
									if y_tr2 >= y1 and y_tr1 <= y2 then
										paint_areas[#paint_areas+1] = {
											id = GenID(),
											track_guid = r.GetTrackGUID(tr),
											start = t1,
											stop = t2,
											color = TrackColorARGB(tr),
											label = '',
											mode = 'time',
											group_id = gid
										}
									end
								end
							end
							needs_save = true
							r.UpdateArrange()
						end
						is_drawing = false
					end
				end
			end
			if merged_mode then
				local groups = {}
				for _, area in ipairs(paint_areas) do
					if not area.missing then
						local gid = area.group_id or 0
						local g = groups[gid]
						if not g then
							g = { id = gid, start = area.start, stop = area.stop, color = area.color, list = {} }
							groups[gid] = g
						else
							if area.start < g.start then g.start = area.start end
							if area.stop  > g.stop  then g.stop  = area.stop  end
						end
						table.insert(g.list, area)
					end
				end
				local ordered = {}
				for _, g in pairs(groups) do ordered[#ordered+1] = g end
				if groups_sort_by_id then
					table.sort(ordered, function(a,b) return a.id < b.id end)
				else
					table.sort(ordered, function(a,b)
						if a.start == b.start then return a.stop < b.stop end
						return a.start < b.start
					end)
				end
				for _, g in ipairs(ordered) do
					local x1 = TimeToPixel(g.start, start_time, end_time)
					local x2 = TimeToPixel(g.stop,  start_time, end_time)
					local x_left_limit = LEFT
					local x_right_limit = RIGHT - scroll_size
					if x2 > x_left_limit and x1 < x_right_limit then
						local cx1 = math.max(x1, x_left_limit)
						local cx2 = math.min(x2, x_right_limit)
						local minY = math.huge
						local maxY = -math.huge
						for _, area in ipairs(g.list) do
							local tr = GetTrackByGUID(area.track_guid)
							if tr then
								local ty, th = GetTrackYH(tr)
								if th > 0 then
									local y1 = TOP + ty
									local y2 = y1 + th
									if y1 < minY then minY = y1 end
									if y2 > maxY then maxY = y2 end
									local lanes = GetVisibleEnvelopeLanes(tr)
									for _, lane in ipairs(lanes) do
										local ly1 = TOP + lane.y
										local ly2 = ly1 + lane.h
										if ly1 < minY then minY = ly1 end
										if ly2 > maxY then maxY = ly2 end
									end
								end
							end
						end
						if minY < math.huge and maxY > -math.huge then
							local a  = (g.color >> 24) & 0xFF
							local rC = (g.color >> 16) & 0xFF
							local gC = (g.color >> 8)  & 0xFF
							local bC = (g.color)       & 0xFF
							local sa = math.floor(a * master_opacity_factor + 0.5)
							local scaled_color = (sa << 24) | (rC << 16) | (gC << 8) | bC
							local fill_col = ARGB_to_U32(scaled_color)
							local dr = (rC * 0.55) // 1
							local dg = (gC * 0.55) // 1
							local db = (bC * 0.55) // 1
							local darker_argb = (sa << 24) | (dr << 16) | (dg << 8) | db
							local border_col = ARGB_to_U32(darker_argb)
							if not outline_mode then
								r.ImGui_DrawList_AddRectFilled(dl, cx1, minY, cx2, maxY, fill_col, 4)
							end
							r.ImGui_DrawList_AddRect(dl, cx1, minY, cx2, maxY, border_col, 4, 0, 2)
							local gname = group_names[g.id] or ''
							local txt
							if gname ~= '' then
								txt = string.format('Group %d %s (%d tracks)', g.id, gname, #g.list)
							else
								txt = string.format('Group %d (%d tracks)', g.id, #g.list)
							end
							r.ImGui_DrawList_AddText(dl, cx1 + 6, minY + 4, 0xFFFFFFFF, txt)
						end
					end
				end
			else
				for _, area in ipairs(paint_areas) do
					local tr = GetTrackByGUID(area.track_guid)
					if tr and not area.missing then
						local track_y, track_h = GetTrackYH(tr)
						if track_h > 0 then
							local x1 = TimeToPixel(area.start, start_time, end_time)
							local x2 = TimeToPixel(area.stop,  start_time, end_time)
							local x_left_limit = LEFT
							local x_right_limit = RIGHT - scroll_size
							if x2 > x_left_limit and x1 < x_right_limit then
								local cx1 = math.max(x1, x_left_limit)
								local cx2 = math.min(x2, x_right_limit)
								local y1 = TOP + track_y
								local y2 = y1 + track_h
								local a  = (area.color >> 24) & 0xFF
								local rC = (area.color >> 16) & 0xFF
								local gC = (area.color >> 8)  & 0xFF
								local bC = (area.color)       & 0xFF
								local sa = math.floor(a * master_opacity_factor + 0.5)
								local scaled_color = (sa << 24) | (rC << 16) | (gC << 8) | bC
								local fill_col = ARGB_to_U32(scaled_color)
								if not outline_mode then
									r.ImGui_DrawList_AddRectFilled(dl, cx1, y1, cx2, y2, fill_col, 4)
								end
								local dr = (rC * 0.55) // 1
								local dg = (gC * 0.55) // 1
								local db = (bC * 0.55) // 1
								local darker_argb = (sa << 24) | (dr << 16) | (dg << 8) | db
								local border_col = ARGB_to_U32(darker_argb)
								r.ImGui_DrawList_AddRect(dl, cx1, y1, cx2, y2, border_col, 4, 0, 2)

								local trnum = 0
								if tr then
									trnum = math.floor(r.GetMediaTrackInfo_Value(tr, 'IP_TRACKNUMBER') or 0)
								end
								local trname = ''
								if tr then
									local _, tn = r.GetTrackName(tr)
									trname = tn or ''
								else
									trname = 'Removed'
								end

								local text
								if area.label and area.label ~= '' then
									text = string.format('%02d %s  | %s', trnum, trname, area.label)
								else
									text = string.format('%02d %s', trnum, trname)
								end
								r.ImGui_DrawList_AddText(dl, cx1 + 6, y1 + 4, 0xFFFFFFFF, text)

								local lanes = GetVisibleEnvelopeLanes(tr)
								if #lanes > 0 then
									for _, lane in ipairs(lanes) do
										local ly1 = TOP + lane.y
										local ly2 = ly1 + lane.h
											if not outline_mode then
												r.ImGui_DrawList_AddRectFilled(dl, cx1, ly1, cx2, ly2, fill_col, 3)
											end
											r.ImGui_DrawList_AddRect(dl, cx1, ly1, cx2, ly2, border_col, 3, 0, 1.5)
									end
								end
							end
						end
					end
				end
			end
		end
	end
	r.ImGui_End(ctx)
	r.ImGui_PopStyleVar(ctx) 
	r.ImGui_PopStyleVar(ctx) 
	r.ImGui_PopStyleColor(ctx)
end

local function UpdateScale()
	local ds = r.ImGui_GetWindowDpiScale(ctx)
	screen_scale = (ds and ds > 0) and ds or 1
end

local function MainLoop()
	UpdateScale()
	local tc = r.CountTracks(0)
	if tc ~= last_track_count then
		last_track_count = tc
		UpdateMissingFlags()
	else
		UpdateMissingFlags()
	end
	if ui_visible then DrawManager() else manager_x2 = -1 end
	DrawOverlay()
	if needs_save then SaveAreas() end
	r.defer(MainLoop)
end

math.randomseed(os.time())
LoadAreas()
last_track_count = r.CountTracks(0)
RebuildTrackGUIDCache()
r.defer(MainLoop)
r.atexit(function() SaveAreas(true) end)
