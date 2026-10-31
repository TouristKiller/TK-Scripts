local r = reaper
local Theme = require("core.theme")
local UIScale = require("core.ui_scale")
local Text = require("core.text")

local M = {}

local tooltip_app = nil
local original_set_tooltip = nil

local function tooltip_settings(app)
	local settings = app and app.settings or {}
	local enabled = settings.tooltips_enabled ~= false
	local delay = tonumber(settings.tooltip_delay)
	if not delay then delay = 1.0 end
	delay = math.max(0, math.min(3, delay))
	return enabled, delay
end

local function tooltip_item_key(ctx, text)
	if r.ImGui_GetItemID then
		local ok, id = pcall(r.ImGui_GetItemID, ctx)
		if ok and id then return "id:" .. tostring(id) .. "|" .. tostring(text or "") end
	end
	if r.ImGui_GetItemRectMin and r.ImGui_GetItemRectMax then
		local ok_min, x1, y1 = pcall(r.ImGui_GetItemRectMin, ctx)
		local ok_max, x2, y2 = pcall(r.ImGui_GetItemRectMax, ctx)
		if ok_min and ok_max and x1 and y1 and x2 and y2 then
			return string.format("rect:%.0f:%.0f:%.0f:%.0f|%s", x1, y1, x2, y2, tostring(text or ""))
		end
	end
	return tostring(text or "")
end

function M.begin_tooltip_frame(app)
	tooltip_app = app
	app.cache.tooltip = app.cache.tooltip or {}
	app.cache.tooltip.requested = false
	app.cache.info_line_index = 0
end

function M.end_tooltip_frame(app)
	local tooltip = app.cache.tooltip
	if tooltip and not tooltip.requested then
		tooltip.key = nil
		tooltip.started = nil
	end
end

function M.tooltip_ready(ctx, app, text)
	if not app then return true end
	local enabled, delay = tooltip_settings(app)
	if not enabled then return false end
	if delay <= 0 then return true end
	app.cache.tooltip = app.cache.tooltip or {}
	local tooltip = app.cache.tooltip
	tooltip.requested = true
	local key = tooltip_item_key(ctx, text)
	local now = r.time_precise and r.time_precise() or os.clock()
	if tooltip.key ~= key then
		tooltip.key = key
		tooltip.started = now
		return false
	end
	return now - (tooltip.started or now) >= delay
end

function M.configure_tooltips(app)
	tooltip_app = app
	if original_set_tooltip or not r.ImGui_SetTooltip then return end
	original_set_tooltip = r.ImGui_SetTooltip
	r.ImGui_SetTooltip = function(ctx, text, ...)
		if M.tooltip_ready(ctx, tooltip_app, text) then return original_set_tooltip(ctx, text, ...) end
	end
end

function M.tooltip_when(app, hovered, text)
	if hovered and r.ImGui_SetTooltip then r.ImGui_SetTooltip(app.ctx, text) end
end

local function info_line_enabled()
	return not (tooltip_app and tooltip_app.settings and tooltip_app.settings.show_status == false)
end

local function text_width(ctx, value)
	if r.ImGui_CalcTextSize then
		local width = r.ImGui_CalcTextSize(ctx, tostring(value or ""))
		return tonumber(width) or 0
	end
	return #(tostring(value or "")) * 7
end

local function fit_text(ctx, value, max_width)
	value = tostring(value or "")
	if max_width <= 0 then return "" end
	if text_width(ctx, value) <= max_width then return value end
	local ellipsis = "..."
	local text = value
	-- A whole character at a time: dropping single bytes cuts a Cyrillic or
	-- accented letter in half and the remnant is drawn as a placeholder box.
	while #text > 1 and text_width(ctx, text .. ellipsis) > max_width do
		text = text:sub(1, Text.char_start(text, #text) - 1)
	end
	if #text <= 1 and text_width(ctx, ellipsis) > max_width then return "" end
	return text .. ellipsis
end

local function actual_info_line_height(ctx)
	if not info_line_enabled() then return 0 end
	return r.ImGui_GetTextLineHeight(ctx) + UIScale.round(12)
end

function M.info_line_height(ctx, force)
	if not force and tooltip_app and tooltip_app.cache and tooltip_app.cache.info_line_capture then return 0 end
	return actual_info_line_height(ctx)
end

function M.begin_info_line_capture(app)
	app.cache.info_line_capture = true
	app.cache.captured_info_line = nil
end

function M.end_info_line_capture(app)
	app.cache.info_line_capture = false
end

function M.get_captured_info_line(app)
	return app and app.cache and app.cache.captured_info_line or nil
end

function M.draw_info_line(ctx, text, options)
	if not info_line_enabled() then return end
	options = options or {}
	if not options.force and tooltip_app and tooltip_app.cache and tooltip_app.cache.info_line_capture then
		tooltip_app.cache.captured_info_line = { text = text, options = options }
		return
	end
	local full_text = tostring(text or "Ready")
	local details = tostring(options.details or "")
	local height = actual_info_line_height(ctx)
	local width = r.ImGui_GetContentRegionAvail(ctx)
	if not width or width <= 1 then return end
	local x, y = r.ImGui_GetCursorScreenPos(ctx)
	local draw_list = r.ImGui_GetWindowDrawList(ctx)
	local is_error = options.severity == "error"
	local is_warning = options.severity == "warning"
	local bg = options.bg or Theme.colors.frame_bg or 0x242424FF
	local border = options.border or Theme.colors.border or 0x444444FF
	local color = Theme.text_for_background(bg, options.text_color or Theme.colors.text_dim or 0xA0A0A0FF, Theme.colors.text or 0xF0F0F0FF, 4.5)
	local dot = is_error and (Theme.colors.danger or 0xBF616AFF) or (is_warning and (Theme.colors.warning or 0xEBCB8BFF) or (Theme.colors.accent or 0xD8DEE9FF))
	local text_h = r.ImGui_GetTextLineHeight(ctx)
	local top_pad = UIScale.round(2)
	local text_pad = UIScale.round(18)
	local right_pad = UIScale.round(6)
	local dot_x = UIScale.round(9)
	local dot_radius = UIScale.px(2.4)
	local text_y = y + math.max(0, (height - text_h) * 0.5)
	local text_x = x + text_pad
	local display = fit_text(ctx, full_text, math.max(0, width - text_pad - right_pad))
	r.ImGui_DrawList_AddRectFilled(draw_list, x, y + top_pad, x + width, y + height, bg, UIScale.px(4))
	r.ImGui_DrawList_AddLine(draw_list, x, y + top_pad, x + width, y + top_pad, border, UIScale.px(1))
	r.ImGui_DrawList_AddCircleFilled(draw_list, x + dot_x, y + height * 0.5 + UIScale.px(1), dot_radius, dot, 12)
	r.ImGui_DrawList_PushClipRect(draw_list, text_x, y + top_pad, x + width - right_pad, y + height, true)
	r.ImGui_DrawList_AddText(draw_list, text_x, text_y + 1, color, display)
	r.ImGui_DrawList_PopClipRect(draw_list)
	local app = tooltip_app
	local id = app and app.cache and app.cache.info_line_index or 0
	if app and app.cache then app.cache.info_line_index = id + 1 end
	r.ImGui_PushID(ctx, "tk_info_line_" .. tostring(id))
	r.ImGui_InvisibleButton(ctx, "##hit", width, height)
	local hovered = r.ImGui_IsItemHovered(ctx)
	r.ImGui_PopID(ctx)
	if hovered and (display ~= full_text or details ~= "") and r.ImGui_SetTooltip then
		r.ImGui_SetTooltip(ctx, details ~= "" and (full_text .. "\n\n" .. details) or full_text)
	end
end

-- Typing straight into a module opened from the keyboard. An open action asks
-- for it for one module; the first search field that module draws within half
-- a second takes it, and Workbench gives its window the real keyboard focus.
-- Bound to a module rather than "the next search field": with split view two
-- modules draw, and the other pane's field must not take it. A module without
-- a search field simply lets the request run out.
function M.request_search_focus(app, module_id)
	local now = r.time_precise and r.time_precise() or os.clock()
	app.cache.search_focus = { module = module_id, until_time = now + 1.0 }
end

-- Hands the keyboard back to REAPER after typing that started from an open
-- action, for a module that ends it some other way than Esc (Plugin Browser
-- inserting a plugin with Enter).
function M.end_search_session(app)
	if not (app and app.cache and app.cache.search_session) then return end
	app.cache.search_session = nil
	if app.release_keyboard then app.release_keyboard() end
end

-- Asked again every frame until the field really is active, not once. The
-- first request can be dropped: switching to this module from one without a
-- search field changes the window's focus in ImGui and in Windows in the same
-- frame, and the field then stayed inactive - the keyboard was Workbench's,
-- the typing went nowhere. Returns the request this field is serving, so the
-- caller can close it once the field is active.
local function take_search_focus(ctx, id)
	local app = tooltip_app
	local pending = app and app.cache and app.cache.search_focus
	if not pending then return nil end
	local now = r.time_precise and r.time_precise() or os.clock()
	if now > pending.until_time then
		app.cache.search_focus = nil
		return nil
	end
	if pending.module ~= nil and pending.module ~= app.drawing_module then return nil end
	-- The first field the module draws is the one: a second search field in
	-- the same module must not pull the focus over every other frame.
	if pending.field and pending.field ~= id then return nil end
	-- Keyboard focus on an InputText selects what is in it, so typing replaces
	-- the previous search.
	if r.ImGui_SetKeyboardFocusHere then r.ImGui_SetKeyboardFocusHere(ctx) end
	if not pending.field then
		pending.field = id
		app.cache.search_session = true
		if app.request_keyboard then app.request_keyboard() end
		app.status = "Type to search - Esc clears it and gives the keyboard back to REAPER"
	end
	return pending
end

function M.search_input(ctx, id, hint, value, width)
	value = tostring(value or "")
	local has_value = value ~= ""
	local spacing = has_value and UIScale.round(3) or 0
	local clear_w = has_value and UIScale.round(16) or 0
	local total_w = tonumber(width)
	if not total_w or total_w <= 0 then total_w = r.ImGui_GetContentRegionAvail(ctx) or UIScale.round(200) end
	local input_w = math.max(UIScale.round(40), total_w - clear_w - spacing)
	local serving = take_search_focus(ctx, id)
	r.ImGui_SetNextItemWidth(ctx, input_w)
	local changed, new_value = r.ImGui_InputTextWithHint(ctx, id, hint, value)
	if changed then value = new_value end
	local active = r.ImGui_IsItemActive(ctx)
	-- Done once the field has the focus; until then it keeps asking.
	if serving and active and tooltip_app and tooltip_app.cache.search_focus == serving then
		tooltip_app.cache.search_focus = nil
	end
	if r.ImGui_IsItemHovered(ctx) and not active and r.ImGui_SetTooltip then
		r.ImGui_SetTooltip(ctx, "Type to search.\nEsc: clear the search and give the keyboard back to REAPER,\nso its shortcuts work again without clicking out of Workbench.")
	end
	-- Esc ends the search: it empties the field and gives the keyboard back to
	-- REAPER. ImGui's own Esc only leaves the field (and reverts what was typed),
	-- which kept the keys in Workbench. Checked for the frame the field lets go
	-- too, since that is the frame Esc arrives in.
	if (active or (r.ImGui_IsItemDeactivated and r.ImGui_IsItemDeactivated(ctx)))
		and r.ImGui_Key_Escape and r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Escape(), false) then
		local app = tooltip_app
		if app and app.cache then app.cache.search_session = nil end
		if app and app.release_keyboard then app.release_keyboard() end
		return true, ""
	end
	if has_value then
		r.ImGui_SameLine(ctx, 0, spacing)
		local btn_h = r.ImGui_GetFrameHeight(ctx)
		local x, y = r.ImGui_GetCursorScreenPos(ctx)
		local clicked = r.ImGui_InvisibleButton(ctx, id .. "_clear", clear_w, btn_h)
		local hovered = r.ImGui_IsItemHovered(ctx)
		local draw_list = r.ImGui_GetWindowDrawList(ctx)
		local cx = x + clear_w * 0.5
		local cy = y + btn_h * 0.5
		local radius = UIScale.round(7)
		local circle = hovered and (Theme.colors.frame_hover or Theme.colors.frame_bg or 0x303030FF) or (Theme.colors.frame_bg or 0x242424FF)
		r.ImGui_DrawList_AddCircleFilled(draw_list, cx, cy, radius, circle, 16)
		local cross = hovered and (Theme.colors.text or 0xF0F0F0FF) or (Theme.colors.text_dim or 0xA0A0A0FF)
		local d = UIScale.round(3)
		local thickness = UIScale.px(1.4)
		r.ImGui_DrawList_AddLine(draw_list, cx - d, cy - d, cx + d, cy + d, cross, thickness)
		r.ImGui_DrawList_AddLine(draw_list, cx - d, cy + d, cx + d, cy - d, cross, thickness)
		if hovered and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx, "Clear search") end
		if clicked then return true, "" end
	end
	return changed, value
end

return M