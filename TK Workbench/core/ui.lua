local r = reaper
local Theme = require("core.theme")

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
	while #text > 1 and text_width(ctx, text .. ellipsis) > max_width do text = text:sub(1, -2) end
	if #text <= 1 and text_width(ctx, ellipsis) > max_width then return "" end
	return text .. ellipsis
end

local function actual_info_line_height(ctx)
	if not info_line_enabled() then return 0 end
	return r.ImGui_GetTextLineHeight(ctx) + 12
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
	local color = options.text_color or Theme.colors.text_dim or 0xA0A0A0FF
	local dot = is_error and (Theme.colors.danger or 0xBF616AFF) or (is_warning and (Theme.colors.warning or 0xEBCB8BFF) or (Theme.colors.accent or 0xD8DEE9FF))
	local text_h = r.ImGui_GetTextLineHeight(ctx)
	local text_y = y + math.max(0, (height - text_h) * 0.5)
	local text_x = x + 18
	local display = fit_text(ctx, full_text, math.max(0, width - 26))
	r.ImGui_DrawList_AddRectFilled(draw_list, x, y + 2, x + width, y + height, bg, 4)
	r.ImGui_DrawList_AddLine(draw_list, x, y + 2, x + width, y + 2, border, 1)
	r.ImGui_DrawList_AddCircleFilled(draw_list, x + 9, y + height * 0.5 + 1, 2.4, dot, 12)
	r.ImGui_DrawList_PushClipRect(draw_list, text_x, y + 2, x + width - 6, y + height, true)
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

return M