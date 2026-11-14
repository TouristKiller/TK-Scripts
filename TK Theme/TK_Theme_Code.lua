-- @noindex
-- Theme codes (Presets page, Share): a look as one line of text to post and paste.
--
-- A code is "TKT1-" and base64 (A-Z a-z 0-9 - _, safe on forums and in chat) of a 4 byte
-- checksum and a short binary: sections of a tag, their length and their entries, so a
-- newer TK Theme can add kinds an older one simply skips. Names (settings, colours, parts
-- and their choices) go as their number in the word list below; one it lacks goes as text.
--
-- THE WORD LIST IS FROZEN: never change or remove a word, never reorder. New words may
-- only be added at the end (WORDS_MORE), or old codes would mean something else.
local Code = {}

Code.PREFIX = "TKT1-"

-- -------------------------------------------------------------- the word list (frozen)
Code.WORDS_LOOKS = { "TK Theme Dark", "TK Theme Light" }
Code.WORDS_TEXT = [[
accent basic dg_display_light dg_meter display display_light items light_glass mcp_extmixbg mcp_hw mcp_pan
mcp_volthumb meter meter_lying midi_keys send_tint shade tcp_hw tcp_thumb toolbar_blank toolbar_text amber bar
black blue bright cap cell classic classic_accent colour colour_l colour_l_nu colour_m colour_m_nu colour_nu
dark dot glass graphite green grid heat heat_nu hw ice lamps lamps_nu lamps_s lamps_s_nu large led led_l
led_l_nu led_m led_m_nu led_nu light medium mono mono_nu normal off on orange plain red reversed ring segment
segment_l segment_l_nu segment_m segment_m_nu segment_nu silver slim small soft solid solid_nu standard subtle
violet LayoutA-hideTcpEnv LayoutA-hideTcpFxBlock LayoutA-hideTcpInputBlock LayoutA-hideTcpIo
LayoutA-hideTcpLabelBlock LayoutA-hideTcpLabelsValues LayoutA-hideTcpMSBlock LayoutA-hideTcpMeterValues
LayoutA-hideTcpPanBlock LayoutA-hideTcpPhase LayoutA-hideTcpRecmode LayoutA-hideTcpRecmon
LayoutA-mcpInterShowSecButtons LayoutA-mcpInterShowSecIn LayoutA-mcpInterShowSecPan LayoutA-mcpLabelSize
LayoutA-mcpMeterReadout LayoutA-mcpMeterVals LayoutA-mcpMeterValsRecarm LayoutA-mcpMeterValsSel
LayoutA-mcpNchanGrow LayoutA-mcpNchanGrowRecarm LayoutA-mcpNchanGrowSel LayoutA-mcpNormalDarkButtons
LayoutA-mcpNormalShowEnv LayoutA-mcpNormalShowPhase LayoutA-mcpNormalShowRoute LayoutA-mcpNormalShowSecFx
LayoutA-mcpNormalShowSecIn LayoutA-mcpNormalShowSecPan LayoutA-mcpSidebar LayoutA-mcpSidebarRecarm
LayoutA-mcpSidebarSel LayoutA-mcpStripHideExtmixer LayoutA-mcpStripInputHeight LayoutA-mcpStripLabelHeight
LayoutA-mcpStripMeterHeight LayoutA-mcpStripVolumeHeight LayoutA-mcpWidth LayoutA-mcpWidthRecarm
LayoutA-mcpWidthSel LayoutA-sectionLeftW LayoutA-sectionRightW LayoutA-sidebarWidth LayoutA-tcpFxLocation
LayoutA-tcpFxPin LayoutA-tcpFxembedLocation LayoutA-tcpFxembedPin LayoutA-tcpFxparmLocation
LayoutA-tcpFxparmPin LayoutA-tcpFxparmVisflag1 LayoutA-tcpFxparmVisflag2 LayoutA-tcpInputFontSize
LayoutA-tcpLabelLength LayoutA-tcpLabelSize LayoutA-tcpMeterBorder LayoutA-tcpMeterWidth
LayoutA-tcpRecinputLength LayoutA-tcpSectionBottomDiv LayoutA-tcpSendLocation LayoutA-tcpSendPin
LayoutA-tcpVolumeLength LayoutA-tkArmLeft LayoutA-tkHideArm LayoutA-tkHideButtons LayoutA-tkHideEmbed
LayoutA-tkHideFxBtn LayoutA-tkHideInput LayoutA-tkHideIoBtn LayoutA-tkHideMeter LayoutA-tkHideMs
LayoutA-tkHidePan LayoutA-tkHideParms LayoutA-tkHideVol LayoutA-tkIoW LayoutA-tkKnobs LayoutA-tkMcpKnobs
LayoutA-tkMeterLeft LayoutA-tkMsLeft LayoutA-tkNameOnly LayoutA-tkNameW LayoutA-tkNoFxCol LayoutA-tkNoIoCol
LayoutA-tkSidebarCols LayoutA-tkSidebarRight LayoutA-tkTopSliders LayoutA-useInfoBlock LayoutA-verboseMcp
LayoutB-hideTcpEnv LayoutB-hideTcpFxBlock LayoutB-hideTcpInputBlock LayoutB-hideTcpIo
LayoutB-hideTcpLabelBlock LayoutB-hideTcpLabelsValues LayoutB-hideTcpMSBlock LayoutB-hideTcpMeterValues
LayoutB-hideTcpPanBlock LayoutB-hideTcpPhase LayoutB-hideTcpRecmode LayoutB-hideTcpRecmon
LayoutB-mcpInterShowSecButtons LayoutB-mcpInterShowSecIn LayoutB-mcpInterShowSecPan LayoutB-mcpLabelSize
LayoutB-mcpMeterReadout LayoutB-mcpMeterVals LayoutB-mcpMeterValsRecarm LayoutB-mcpMeterValsSel
LayoutB-mcpNchanGrow LayoutB-mcpNchanGrowRecarm LayoutB-mcpNchanGrowSel LayoutB-mcpNormalDarkButtons
LayoutB-mcpNormalShowEnv LayoutB-mcpNormalShowPhase LayoutB-mcpNormalShowRoute LayoutB-mcpNormalShowSecFx
LayoutB-mcpNormalShowSecIn LayoutB-mcpNormalShowSecPan LayoutB-mcpSidebar LayoutB-mcpSidebarRecarm
LayoutB-mcpSidebarSel LayoutB-mcpStripHideExtmixer LayoutB-mcpStripInputHeight LayoutB-mcpStripLabelHeight
LayoutB-mcpStripMeterHeight LayoutB-mcpStripVolumeHeight LayoutB-mcpWidth LayoutB-mcpWidthRecarm
LayoutB-mcpWidthSel LayoutB-sectionLeftW LayoutB-sectionRightW LayoutB-sidebarWidth LayoutB-tcpFxLocation
LayoutB-tcpFxPin LayoutB-tcpFxembedLocation LayoutB-tcpFxembedPin LayoutB-tcpFxparmLocation
LayoutB-tcpFxparmPin LayoutB-tcpFxparmVisflag1 LayoutB-tcpFxparmVisflag2 LayoutB-tcpInputFontSize
LayoutB-tcpLabelLength LayoutB-tcpLabelSize LayoutB-tcpMeterBorder LayoutB-tcpMeterWidth
LayoutB-tcpRecinputLength LayoutB-tcpSectionBottomDiv LayoutB-tcpSendLocation LayoutB-tcpSendPin
LayoutB-tcpVolumeLength LayoutB-tkArmLeft LayoutB-tkHideArm LayoutB-tkHideButtons LayoutB-tkHideEmbed
LayoutB-tkHideFxBtn LayoutB-tkHideInput LayoutB-tkHideIoBtn LayoutB-tkHideMeter LayoutB-tkHideMs
LayoutB-tkHidePan LayoutB-tkHideParms LayoutB-tkHideVol LayoutB-tkIoW LayoutB-tkKnobs LayoutB-tkMcpKnobs
LayoutB-tkMeterLeft LayoutB-tkMsLeft LayoutB-tkNameOnly LayoutB-tkNameW LayoutB-tkNoFxCol LayoutB-tkNoIoCol
LayoutB-tkSidebarCols LayoutB-tkSidebarRight LayoutB-tkTopSliders LayoutB-useInfoBlock LayoutB-verboseMcp
LayoutC-hideTcpEnv LayoutC-hideTcpFxBlock LayoutC-hideTcpInputBlock LayoutC-hideTcpIo
LayoutC-hideTcpLabelBlock LayoutC-hideTcpLabelsValues LayoutC-hideTcpMSBlock LayoutC-hideTcpMeterValues
LayoutC-hideTcpPanBlock LayoutC-hideTcpPhase LayoutC-hideTcpRecmode LayoutC-hideTcpRecmon
LayoutC-mcpInterShowSecButtons LayoutC-mcpInterShowSecIn LayoutC-mcpInterShowSecPan LayoutC-mcpLabelSize
LayoutC-mcpMeterReadout LayoutC-mcpMeterVals LayoutC-mcpMeterValsRecarm LayoutC-mcpMeterValsSel
LayoutC-mcpNchanGrow LayoutC-mcpNchanGrowRecarm LayoutC-mcpNchanGrowSel LayoutC-mcpNormalDarkButtons
LayoutC-mcpNormalShowEnv LayoutC-mcpNormalShowPhase LayoutC-mcpNormalShowRoute LayoutC-mcpNormalShowSecFx
LayoutC-mcpNormalShowSecIn LayoutC-mcpNormalShowSecPan LayoutC-mcpSidebar LayoutC-mcpSidebarRecarm
LayoutC-mcpSidebarSel LayoutC-mcpStripHideExtmixer LayoutC-mcpStripInputHeight LayoutC-mcpStripLabelHeight
LayoutC-mcpStripMeterHeight LayoutC-mcpStripVolumeHeight LayoutC-mcpWidth LayoutC-mcpWidthRecarm
LayoutC-mcpWidthSel LayoutC-sectionLeftW LayoutC-sectionRightW LayoutC-sidebarWidth LayoutC-tcpFxLocation
LayoutC-tcpFxPin LayoutC-tcpFxembedLocation LayoutC-tcpFxembedPin LayoutC-tcpFxparmLocation
LayoutC-tcpFxparmPin LayoutC-tcpFxparmVisflag1 LayoutC-tcpFxparmVisflag2 LayoutC-tcpInputFontSize
LayoutC-tcpLabelLength LayoutC-tcpLabelSize LayoutC-tcpMeterBorder LayoutC-tcpMeterWidth
LayoutC-tcpRecinputLength LayoutC-tcpSectionBottomDiv LayoutC-tcpSendLocation LayoutC-tcpSendPin
LayoutC-tcpVolumeLength LayoutC-tkArmLeft LayoutC-tkHideArm LayoutC-tkHideButtons LayoutC-tkHideEmbed
LayoutC-tkHideFxBtn LayoutC-tkHideInput LayoutC-tkHideIoBtn LayoutC-tkHideMeter LayoutC-tkHideMs
LayoutC-tkHidePan LayoutC-tkHideParms LayoutC-tkHideVol LayoutC-tkIoW LayoutC-tkKnobs LayoutC-tkMcpKnobs
LayoutC-tkMeterLeft LayoutC-tkMsLeft LayoutC-tkNameOnly LayoutC-tkNameW LayoutC-tkNoFxCol LayoutC-tkNoIoCol
LayoutC-tkSidebarCols LayoutC-tkSidebarRight LayoutC-tkTopSliders LayoutC-useInfoBlock LayoutC-verboseMcp
colorTrackLabels customColorDepthParam emptyTcpSecOpacity envCustomColorDepth envcpBgColB envcpBgColG
envcpBgColR envcpDivOpacity envcpFaderLength envcpFontSize envcpLabelLength indentEnvcp masterMcpBgColB
masterMcpBgColG masterMcpBgColR masterMcpLabels masterMcpMeterVals masterMcpVals masterMcpWidth
masterTcpBgColB masterTcpBgColG masterTcpBgColR masterTcpLabels masterTcpMeterBorder masterTcpMeterVals
masterTcpMeterWidth masterTcpVals masterTcpVolumeLength mcpBgColB mcpBgColG mcpBgColR mcpDivOpacity
mcpStripFlowLocation1 mcpStripFlowLocation10 mcpStripFlowLocation11 mcpStripFlowLocation2
mcpStripFlowLocation3 mcpStripFlowLocation4 mcpStripFlowLocation5 mcpStripFlowLocation6 mcpStripFlowLocation7
mcpStripFlowLocation8 mcpStripFlowLocation9 mcpfolderBalanceType mcpfolderIndentSize sectionMargin selDot
selInvertLabels selectStrength showEnvValue tcpBgColB tcpBgColG tcpBgColR tcpDivOpacity tcpFlowLocation1
tcpFlowLocation10 tcpFlowLocation2 tcpFlowLocation3 tcpFlowLocation4 tcpFlowLocation5 tcpFlowLocation6
tcpFlowLocation7 tcpFlowLocation8 tcpFlowLocation9 tcpFxMaxWidth tcpFxMinWidth tcpFxparmMaxWidth
tcpFxparmMinWidth tcpSendMaxWidth tcpSendMinWidth tcpfolderBalanceType tcpfolderIndentSize textBrightness
themeVersionDate tkAlt_actions tkAlt_bay tkAlt_clock tkAlt_explorer tkAlt_fxbrowser tkAlt_mixer tkAlt_regions
tkAlt_routing tkAlt_trackmgr tkAlt_vkb tkBtnLeftEdge tkBtnRightEdge tkBtn_actions tkBtn_bay tkBtn_clock
tkBtn_explorer tkBtn_free1 tkBtn_free2 tkBtn_free3 tkBtn_fxbrowser tkBtn_master tkBtn_metro tkBtn_mixer
tkBtn_new tkBtn_open tkBtn_prefs tkBtn_projset tkBtn_quit tkBtn_redo tkBtn_regions tkBtn_render tkBtn_ripple
tkBtn_routing tkBtn_save tkBtn_trackmgr tkBtn_undo tkBtn_vkb tkGridA tkGridBox tkGridV tkLinePanTrk
tkLineVolTrk tkMasterHideEmbed tkMasterHideFxBtn tkMasterHideIoBtn tkMasterHideMeter tkMasterHideMs
tkMasterHidePan tkMasterHideParms tkMasterHideVol tkMasterKnobs tkMasterListCols tkMasterMcpHidePan
tkMasterMcpKnobs tkMasterMeterLeft tkMasterMeterOnly tkMasterMeterW tkMasterNoFx tkMasterNoIo tkMasterScrews
tkMasterSideCol tkMcpBasic tkMcpGlassM tkMcpLayBtn tkMcpNumStyle tkMcpPlate tkMcpWood tkMeterNoUnlit
tkNameAccent tkNumStyle tkPlLamps tkPlMeterIn tkPlMeterShort tkPlateLogo tkRailRight tkRateKnob tkSnapOn
tkTcpBasic tkTcpLayBtn tkTcpPlate tkTransMetroOn tkTransPlate tkTransScrews tkWood transBgColB transBgColG
transBgColR transMargin transRateFaderWidth transSelectionFontSize transSelectionWidth transStatusColB
transStatusColG transStatusColR transStatusWidth visSections xMargin yMargin activetake_tag areasel_drawmode
areasel_fill areasel_outline areasel_outlinemode arrange_vgrid auto_item_unsel autogroup cc_chase_drawmode
col_arrangebg col_buttonbg col_cursor col_cursor2 col_env1 col_env10 col_env11 col_env12 col_env13 col_env14
col_env15 col_env16 col_env2 col_env3 col_env4 col_env5 col_env6 col_env7 col_env8 col_env9
col_envlane1_divline col_envlane2_divline col_explorer_playtext col_explorer_playtext_dark col_explorer_sel
col_explorer_seldm col_explorer_seledge col_fadearm col_fadearm2 col_fadearm3 col_gridlines col_gridlines1dm
col_gridlines2 col_gridlines2dm col_gridlines3 col_gridlines3dm col_main_3dhl col_main_3dsh col_main_bg
col_main_bg2 col_main_editbk col_main_resize2 col_main_text col_main_text2 col_main_textshadow col_mi_bg
col_mi_bg2 col_mi_fade2 col_mi_fade2_drawmode col_mi_fades col_mi_label col_mi_label_float
col_mi_label_float_sel col_mi_label_sel col_mi_text_dark col_mi_text_light col_mi_text_sel_dark
col_mi_text_sel_light col_mixerbg col_nodarkmodemiscwnd col_offlinetext col_peaksedge col_peaksedge2
col_peaksedgesel col_peaksedgesel2 col_peaksfade col_peaksfade2 col_routingact col_routinghl1 col_routinghl2
col_seltrack col_seltrack2 col_stretchmarker col_stretchmarker_b col_stretchmarker_h0 col_stretchmarker_h1
col_stretchmarker_h2 col_stretchmarker_text col_stretchmarker_tm col_stretchmarkerm col_tcp_text
col_tcp_textsel col_tl_bg col_tl_bgsel col_tl_bgsel2 col_tl_fg col_tl_fg2 col_toolbar_frame col_toolbar_text
col_toolbar_text_on col_tr1_bg col_tr1_divline col_tr1_itembgsel col_tr1_peaks col_tr1_ps2 col_tr2_bg
col_tr2_divline col_tr2_itembgsel col_tr2_peaks col_tr2_ps2 col_tracklistbg col_trans_bg col_trans_fg
col_transport_editbk col_tsigmark col_vubot col_vuclip col_vudoint col_vuind1 col_vuind2 col_vuind3 col_vuind4
col_vuintcol col_vumid col_vumidi col_vutop docker_bg docker_selface docker_shadow docker_text docker_text_sel
docker_unselface env_item_mute env_item_pan env_item_pitch env_item_vol env_sends_mute env_track_mute
env_trim_vol explorer_grid explorer_pitchtext fadearea_color fadearea_drawmode fadezone_color
fadezone_drawmode genlist_bg genlist_fg genlist_grid genlist_hilite genlist_hilite_dark
genlist_hilite_dark_sel genlist_hilite_sel genlist_selbg genlist_selfg genlist_seliabg genlist_seliafg group_0
group_1 group_10 group_11 group_12 group_13 group_14 group_15 group_16 group_17 group_18 group_19 group_2
group_20 group_21 group_22 group_23 group_24 group_25 group_26 group_27 group_28 group_29 group_3 group_30
group_31 group_32 group_33 group_34 group_35 group_36 group_37 group_38 group_39 group_4 group_40 group_41
group_42 group_43 group_44 group_45 group_46 group_47 group_48 group_49 group_5 group_50 group_51 group_52
group_53 group_54 group_55 group_56 group_57 group_58 group_59 group_6 group_60 group_61 group_62 group_63
group_7 group_8 group_9 guideline_color guideline_drawmode inactive_take_overlay_col
inactive_take_overlay_mode io_3dhl io_3dsh io_text item_grouphl itembg_drawmode linkedlane_fill
linkedlane_fillmode linkedlane_outline linkedlane_outlinemode linkedlane_unsynced linkedlane_unsynced_mode
locked_overlay_col locked_overlay_mode marker marker_edge marker_edge_sel marker_lane_bg marker_lane_text
marquee_drawmode marquee_fill marquee_outline marqueezoom_drawmode marqueezoom_fill marqueezoom_outline
mcp_fx_bypassed mcp_fx_normal mcp_fx_offlined mcp_fxparm_bypassed mcp_fxparm_normal mcp_fxparm_offlined
mcp_list_scrollbar mcp_list_scrollbar_mode mcp_list_scrollbar_mouseover mcp_list_scrollbar_mouseover_mode
mcp_send_midihw mcp_sends_levels mcp_sends_muted mcp_sends_normal midi_ccbut midi_ccbut_arrow midi_ccbut_text
midi_editcurs midi_endpt midi_grid1 midi_grid2 midi_grid3 midi_griddm1 midi_griddm2 midi_griddm3 midi_gridh
midi_gridhc midi_gridhcdm midi_gridhdm midi_inline_trackbg1 midi_inline_trackbg2 midi_itemctl midi_leftbg
midi_notebg midi_notefg midi_notemute midi_notemute_sel midi_noteon_flash midi_ofsn midi_ofsnsel midi_pkey1
midi_pkey2 midi_pkey3 midi_rulerbg midi_rulerfg midi_selbg midi_selbg_drawmode midi_selpitch1 midi_selpitch2
midi_trackbg1 midi_trackbg2 midi_trackbg_outer1 midi_trackbg_outer2 midieditorlist_bg midieditorlist_bg2
midieditorlist_fg midieditorlist_fg2 midieditorlist_grid midieditorlist_selbg midieditorlist_selbg2
midieditorlist_selfg midieditorlist_selfg2 midieditorlist_seliabg midieditorlist_seliafg midifont_col_dark
midifont_col_dark_unsel midifont_col_light midifont_col_light_unsel midifont_mode midifont_mode_unsel midioct
midioct_inline mouseitem_color mouseitem_mode mute_overlay_col mute_overlay_mode pinned_track_gap
pinned_track_gap_mode pinned_track_gap_unreachable playcursor_color playcursor_drawmode playrate_edited region
region_edge region_edge_sel region_lane_bg region_lane_text score_bg score_fg score_loop score_sel
score_timesel selcol_tr1_bg selcol_tr2_bg selitem_dot selitem_tag send_meter_tint_mode take_marker
take_marker_sel tcp_list_scrollbar tcp_list_scrollbar_mode tcp_list_scrollbar_mouseover
tcp_list_scrollbar_mouseover_mode tcplocked_color tcplocked_drawmode timesel_drawmode timesig_sel_bg
toolbararmed_color toolbararmed_drawmode track_lane_gutter track_lane_gutter_drawmode track_lane_tabcol
track_lanesolo_tabcol track_lanesolo_text ts_lane_bg ts_lane_text vu_gr_bgcol vu_gr_fgcol windowtab_bg
wiring_activity wiring_border wiring_fader wiring_grid wiring_grid2 wiring_horz_col wiring_hwout
wiring_hwoutwire wiring_media wiring_parent wiring_parentwire_border wiring_parentwire_folder
wiring_parentwire_master wiring_pin_connected wiring_pin_disconnected wiring_pin_normal wiring_recbg
wiring_recinput wiring_recinputwire wiring_recitem wiring_recv wiring_send wiring_sendwire wiring_tbg
wiring_ticon
]]
-- words added after TKT1's first list: append here, one per line, never in between
Code.WORDS_MORE = [[
tcp_recarm
mcp_recarm
lamp
glass_white
glass_red
tkSelLed
tkSelLit
tkTcpRecLamp
tkMcpRecLamp
]]

local words, index = {}, {}
local function add_word(w)
    if not index[w] then
        words[#words + 1] = w
        index[w] = #words - 1
    end
end
for _, w in ipairs(Code.WORDS_LOOKS) do add_word(w) end
for w in Code.WORDS_TEXT:gmatch("%S+") do add_word(w) end
for w in Code.WORDS_MORE:gmatch("%S+") do add_word(w) end
Code.word_count = #words

-- -------------------------------------------------------------- bytes

local function varint(n)
    local out = {}
    repeat
        local b = n & 127
        n = n >> 7
        out[#out + 1] = string.char(n > 0 and (b | 128) or b)
    until n == 0
    return table.concat(out)
end

local function zigzag(n) return n >= 0 and n * 2 or -n * 2 - 1 end
local function unzigzag(n) return n % 2 == 0 and n // 2 or -(n + 1) // 2 end

-- a name: its number in the list (even), or its length and the text (odd)
local function ref(w)
    local i = index[w]
    if i then return varint(i * 2) end
    return varint(#w * 2 + 1) .. w
end

local function text(s) return varint(#s) .. s end

-- reading: r = { s = bytes, at = position }; every read returns nil past the end
local function read_varint(rd)
    local n, shift = 0, 0
    while true do
        local b = rd.s:byte(rd.at)
        if not b or shift > 35 then return nil end
        rd.at = rd.at + 1
        n = n | ((b & 127) << shift)
        if b < 128 then return n end
        shift = shift + 7
    end
end

local function read_bytes(rd, n)
    if rd.at + n - 1 > #rd.s then return nil end
    local s = rd.s:sub(rd.at, rd.at + n - 1)
    rd.at = rd.at + n
    return s
end

local function read_ref(rd)
    local n = read_varint(rd)
    if not n then return nil end
    if n % 2 == 0 then return words[n // 2 + 1] or false end    -- false: a word of a newer list
    return read_bytes(rd, (n - 1) // 2)
end

local function read_text(rd)
    local n = read_varint(rd)
    return n and read_bytes(rd, n)
end

-- -------------------------------------------------------------- base64

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
local B64_INDEX = {}
for i = 1, 64 do B64_INDEX[B64:byte(i)] = i - 1 end

function Code.b64(s)
    local out = {}
    for i = 1, #s, 3 do
        local a, b, c = s:byte(i, i + 2)
        local n = (a << 16) | ((b or 0) << 8) | (c or 0)
        for k = 1, 2 + (b and 1 or 0) + (c and 1 or 0) do
            local v = (n >> (18 - 6 * (k - 1))) & 63
            out[#out + 1] = B64:sub(v + 1, v + 1)
        end
    end
    return table.concat(out)
end

function Code.unb64(s)
    local out, acc, nbits = {}, 0, 0
    for i = 1, #s do
        local v = B64_INDEX[s:byte(i)]
        if not v then return nil end
        acc = ((acc << 6) | v) & 0xFFFFFF
        nbits = nbits + 6
        if nbits >= 8 then
            nbits = nbits - 8
            out[#out + 1] = string.char((acc >> nbits) & 255)
        end
    end
    return table.concat(out)
end

-- -------------------------------------------------------------- codes

local TAG = { look = 1, params = 2, colours = 3, parts = 4, processing = 5, handle = 6, plate = 7 }

local function sorted_keys(t, numeric)
    local keys = {}
    for k in pairs(t or {}) do keys[#keys + 1] = k end
    table.sort(keys, numeric and nil or function(a, b) return tostring(a) < tostring(b) end)
    return keys
end

-- data: { look = theme name, params = { name = number }, colours = { key = 0xBBGGRR as in a
-- .ReaperTheme }, parts = { part = variant }, processing = { id = number }, handle = "dot"
-- or "cap", plate = { top = text, name = text } }; every field may be missing
function Code.encode(data, crc32)
    local sections = {}
    local function section(tag, body) sections[#sections + 1] = string.char(tag) .. varint(#body) .. body end
    if data.look then section(TAG.look, ref(data.look)) end
    local function list(tag, t, entry, numeric)
        local keys = sorted_keys(t, numeric)
        if #keys == 0 then return end
        local out = { varint(#keys) }
        for _, k in ipairs(keys) do out[#out + 1] = entry(k, t[k]) end
        section(tag, table.concat(out))
    end
    list(TAG.params, data.params, function(k, v) return ref(k) .. varint(zigzag(math.floor(v))) end)
    list(TAG.colours, data.colours, function(k, v) return ref(k) .. string.pack("<I3", v & 0xFFFFFF) end)
    list(TAG.parts, data.parts, function(k, v) return ref(k) .. ref(v) end)
    list(TAG.processing, data.processing, function(k, v) return varint(zigzag(k)) .. varint(zigzag(math.floor(v))) end, true)
    if data.handle then section(TAG.handle, string.char(data.handle == "dot" and 1 or 0)) end
    if data.plate then section(TAG.plate, text(data.plate.top or "") .. text(data.plate.name or "")) end
    local body = table.concat(sections)
    return Code.PREFIX .. Code.b64(string.pack(">I4", crc32(body)) .. body)
end

-- "TKT1-..." (spaces and line breaks a forum added are ignored) -> data, or nil and why
function Code.decode(code, crc32)
    code = (code or ""):gsub("%s+", "")
    if code == "" then return nil, "Paste a theme code first." end
    if code:sub(1, #Code.PREFIX) ~= Code.PREFIX then
        if code:match("^TKT%d+%-") then return nil, "This code is from a newer TK Theme: update it first." end
        return nil, "This isn't a TK Theme code (it starts with " .. Code.PREFIX .. ")."
    end
    local raw = Code.unb64(code:sub(#Code.PREFIX + 1))
    if not raw or #raw < 4 or crc32(raw:sub(5)) ~= string.unpack(">I4", raw) then
        return nil, "This code is incomplete or damaged: copy it again, as a whole."
    end
    local data, unknown = { params = {}, colours = {}, parts = {}, processing = {} }, 0
    local rd = { s = raw, at = 5 }
    while rd.at <= #raw do
        local tag = raw:byte(rd.at)
        rd.at = rd.at + 1
        local len = read_varint(rd)
        local body = len and read_bytes(rd, len)
        if not body then return nil, "This code is damaged: copy it again, as a whole." end
        local sr = { s = body, at = 1 }
        local function each(fn)
            local n = read_varint(sr) or 0
            for _ = 1, n do
                if not fn() then return end
            end
        end
        if tag == TAG.look then
            data.look = read_ref(sr) or nil
        elseif tag == TAG.params then
            each(function()
                local k, v = read_ref(sr), read_varint(sr)
                if k == nil or not v then return false end
                if k then data.params[k] = unzigzag(v) else unknown = unknown + 1 end
                return true
            end)
        elseif tag == TAG.colours then
            each(function()
                local k, v = read_ref(sr), read_bytes(sr, 3)
                if k == nil or not v then return false end
                if k then data.colours[k] = string.unpack("<I3", v) else unknown = unknown + 1 end
                return true
            end)
        elseif tag == TAG.parts then
            each(function()
                local k, v = read_ref(sr), read_ref(sr)
                if k == nil or v == nil then return false end
                if k and v then data.parts[k] = v else unknown = unknown + 1 end
                return true
            end)
        elseif tag == TAG.processing then
            each(function()
                local k, v = read_varint(sr), read_varint(sr)
                if not k or not v then return false end
                data.processing[unzigzag(k)] = unzigzag(v)
                return true
            end)
        elseif tag == TAG.handle then
            data.handle = body:byte(1) == 1 and "dot" or "cap"
        elseif tag == TAG.plate then
            data.plate = { top = read_text(sr) or "", name = read_text(sr) or "" }
        end
        -- (another tag: from a newer TK Theme, skipped)
    end
    data.unknown = unknown
    return data
end

return Code
