-- @description TK Media Explorer Web Controller - Bridge Script (Cross-Platform Test)
-- @author TK (TouristKiller)
-- @version 3.1-beta
-- @about
--   # TK Media Explorer Web Controller
--   
--   Control REAPER's Media Explorer from your smartphone or any web browser on your local network.
--   
--   ## Features
--   - Play/Stop, Random, Repeat
--   - Navigate through folders and files
--   - Volume control
--   - See current playing file, folder path, and selected item
--   
--   ## Requirements
--   - js_ReaScriptAPI extension (install via ReaPack)
--   - REAPER's built-in web server enabled (Preferences → Control/OSC/web)
--   
--   ## Setup
--   1. Run this script (it will stay running in background)
--   2. Open http://YOUR_IP:8080/TK_MediaExplorer.html in your browser
--   3. Make sure Media Explorer is open in REAPER
--   
--   The HTML interface will be automatically installed to reaper_www_root on first run.
--
-- @changelog
--   v3.1-beta: Cross-platform compatibility test version
--     - Flexible class name detection for ListView/TreeView (SWELL compatibility)
--     - Added Unix/macOS path detection


if not reaper.JS_Window_Find then
  reaper.MB("This script requires js_ReaScriptAPI extension.\n\nInstall via:\nExtensions → ReaPack → Browse packages\nSearch for 'js_ReaScriptAPI'", "Missing Extension", 0)
  return
end


local function install_html_interface()
  local resource_path = reaper.GetResourcePath()
  local separator = reaper.GetOS():find("Win") and "\\" or "/"
  if separator == "\\" then
    resource_path = resource_path:gsub("/", "\\")
  end
  
  local www_path = resource_path .. separator .. "reaper_www_root"
  local html_file = www_path .. separator .. "TK_MediaExplorer.html"
  

  reaper.RecursiveCreateDirectory(www_path, 0)
  

  local html_content = [[<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
    <title>MEDIA EXPLORER REMOTE</title>
    <style>
        :root {
            --bg-body: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            --bg-container: rgba(255, 255, 255, 0.1);
            --text-main: white;
            --btn-bg: rgba(255, 255, 255, 0.9);
            --btn-text: #667eea;
            --btn-radius: 50px;
            --btn-shadow: 0 4px 15px rgba(0, 0, 0, 0.2);
            --info-bg: rgba(0, 0, 0, 0.2);
            --active-green: rgba(100, 255, 100, 0.9);
            --active-blue: rgba(100, 200, 255, 0.9);
            --active-orange: rgba(255, 200, 100, 0.9);
        }

        [data-theme="sleek"] {
            --bg-body: #1a1a1a;
            --bg-container: #2d2d2d;
            --text-main: #e0e0e0;
            --btn-bg: #3d3d3d;
            --btn-text: #e0e0e0;
            --btn-radius: 6px;
            --btn-shadow: 0 2px 4px rgba(0, 0, 0, 0.4);
            --info-bg: #252525;
            --active-green: #2e7d32;
            --active-blue: #1565c0;
            --active-orange: #ef6c00;
        }

        [data-theme="reaper"] {
            --bg-body: #333333;
            --bg-container: #1f1f1f;
            --text-main: #e6e6e6;
            --btn-bg: #4d4d4d;
            --btn-text: #ffffff;
            --btn-radius: 3px;
            --btn-shadow: inset 0 1px 0 rgba(255,255,255,0.1), 0 2px 4px rgba(0,0,0,0.4);
            --info-bg: #121212;
            --active-green: #388e3c;
            --active-blue: #1976d2;
            --active-orange: #d84315;
        }

        [data-theme="rainbow"] {
            --bg-body: linear-gradient(45deg, #ff0000, #ff7f00, #ffff00, #00ff00, #0000ff, #4b0082, #9400d3);
            --bg-container: rgba(255, 255, 255, 0.25);
            --text-main: #ffffff;
            --btn-bg: rgba(255, 255, 255, 0.4);
            --btn-text: #000000;
            --btn-radius: 25px;
            --btn-shadow: 0 8px 32px rgba(31, 38, 135, 0.37);
            --info-bg: rgba(0, 0, 0, 0.3);
            --active-green: #00ff00;
            --active-blue: #00ffff;
            --active-orange: #ff00ff;
        }

        [data-theme="future"] {
            --bg-body: #000000;
            --bg-container: rgba(20, 20, 20, 0.9);
            --text-main: #00ff00;
            --btn-bg: linear-gradient(180deg, #2b2b2b 0%, #1a1a1a 100%);
            --btn-text: #c0c0c0;
            --btn-radius: 0px;
            --btn-shadow: 0 0 5px rgba(0, 255, 0, 0.2), inset 0 0 2px #c0c0c0;
            --info-bg: #0a0a0a;
            --active-green: #00ff00;
            --active-blue: #00ffff;
            --active-orange: #ffaa00;
        }

        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Arial, sans-serif;
            background: var(--bg-body);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 20px;
            color: var(--text-main);
            transition: background 0.3s ease;
        }
        .container {
            background: var(--bg-container);
            backdrop-filter: blur(10px);
            border-radius: 20px;
            padding: 30px;
            max-width: 500px;
            width: 100%;
            box-shadow: 0 8px 32px rgba(0, 0, 0, 0.3);
            transition: background 0.3s ease;
            position: relative;
        }
        h1 {
            text-align: center;
            margin-bottom: 10px;
            font-size: 28px;
            text-shadow: 2px 2px 4px rgba(0, 0, 0, 0.3);
        }
        .current-file {
            background: var(--info-bg);
            padding: 15px;
            border-radius: 10px;
            text-align: center;
            margin-bottom: 30px;
            min-height: 50px;
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            font-size: 14px;
            word-break: break-all;
        }
        
        .progress-container {
            width: 100%;
            height: 4px;
            background: rgba(255,255,255,0.1);
            border-radius: 2px;
            margin-top: 10px;
            overflow: hidden;
        }
        .progress-fill {
            height: 100%;
            background: var(--active-green);
            width: 0%;
            transition: width 0.2s linear;
            box-shadow: 0 0 10px var(--active-green);
        }
        
        .controls {
            display: flex;
            flex-direction: column;
            gap: 20px;
        }
        .button-row {
            display: flex;
            gap: 10px;
            justify-content: center;
        }
        button {
            background: var(--btn-bg);
            border: none;
            padding: 18px 8px;
            border-radius: var(--btn-radius);
            font-size: 16px;
            cursor: pointer;
            transition: all 0.3s;
            box-shadow: var(--btn-shadow);
            flex: 1 1 0px;
            min-width: 0;
            max-width: 200px;
            font-weight: 600;
            color: var(--btn-text);
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
        }
        button:active {
            transform: scale(0.95);
            box-shadow: 0 2px 8px rgba(0, 0, 0, 0.2);
        }
        
        /* Active States */
        button.state-active-green { background: var(--active-green) !important; color: white !important; }
        button.state-active-blue { background: var(--active-blue) !important; color: white !important; }
        button.state-active-orange { background: var(--active-orange) !important; color: white !important; }
        
        .theme-toggle {
            position: absolute;
            top: 10px;
            right: 15px;
            background: transparent;
            border: 1px solid rgba(255,255,255,0.3);
            padding: 5px 10px;
            font-size: 12px;
            width: auto;
            border-radius: 15px;
            color: var(--text-main);
            box-shadow: none;
        }
        
        .status {
            margin-top: 25px;
            text-align: center;
            font-size: 12px;
            opacity: 0.8;
        }
        
        .power-btn {
            background: #ff4444 !important;
            color: white !important;
            border-radius: 50% !important;
            width: 50px !important;
            height: 50px !important;
            padding: 0 !important;
            flex: 0 0 50px !important;
            display: flex;
            align-items: center;
            justify-content: center;
            font-size: 24px !important;
            box-shadow: 0 4px 10px rgba(255, 0, 0, 0.4) !important;
            margin-right: 10px;
        }
        .power-btn:active {
            transform: scale(0.9);
            box-shadow: 0 2px 5px rgba(255, 0, 0, 0.4) !important;
        }
    </style>
</head>
<body>
    <div class="container">
        <button class="theme-toggle" onclick="toggleTheme()">Theme</button>
        <h1>MEDIA EXPLORER REMOTE</h1>
        <div class="current-file">
            <div id="currentFile">REAPER Connected</div>
            <div class="progress-container"><div class="progress-fill" id="progressFill"></div></div>
        </div>
        <div class="current-file" id="currentFolder" style="font-size: 11px; min-height: 30px; margin-top: -20px;">Folder</div>
        <div class="current-file" id="selectedItem" style="font-size: 13px; min-height: 35px; margin-top: -15px; background: rgba(255, 200, 0, 0.2);">Selected</div>
        
        <div class="controls">
            <div class="button-row">
                <button onclick="sendCommand(40024)" id="btnPlay">Play/Stop</button>
                <button onclick="sendCommand(1010)" id="btnPause">Pause</button>
                <button onclick="sendCommand('TOGGLE_AUTO_ADVANCE')" id="btnAutoAdv">Auto-Adv</button>
            </div>
            
            <div class="button-row">
                <button onclick="sendCommand(42184)">Random</button>
                <button onclick="sendCommand(1068)" id="btnRepeat">Repeat</button>
                <button onclick="sendCommand(1011)" id="btnAutoplay">Autoplay</button>
            </div>
            
            <div class="button-row">
                <button onclick="sendTreeKey('up')">Sidebar Up</button>
                <button onclick="sendTreeKey('down')">Sidebar Down</button>
            </div>
            
            <div class="button-row">
                <button onclick="sendArrowKey('up')">Up List</button>
                <button onclick="sendArrowKey('down')">Down List</button>
            </div>
            
            <div class="button-row">
                <button onclick="sendCommand(1004)">Back</button>
                <button onclick="sendCommand('OPEN_FOLDER')">Open</button>
            </div>
            
            <div class="button-row">
                <button onclick="sendCommand(50124)" class="power-btn" title="Show/Hide Media Explorer">
                    <svg viewBox="0 0 24 24" width="24" height="24" stroke="currentColor" stroke-width="3" fill="none" stroke-linecap="round" stroke-linejoin="round">
                        <path d="M18.36 6.64a9 9 0 1 1-12.73 0"></path>
                        <line x1="12" y1="2" x2="12" y2="12"></line>
                    </svg>
                </button>
                <button onclick="sendCommand(42178)">Vol -</button>
                <button onclick="sendCommand(42177)">Vol +</button>
            </div>
        </div>
        
        <div class="status" id="status">Ready (v3.1-beta Cross-Platform)</div>
        <div id="debug" style="font-size: 10px; color: #ffaaaa; margin-top: 10px; font-family: monospace; white-space: pre-wrap; display: none;"></div>
    </div>

    <script>
        function sendCommand(commandId) {
            const uniqueCmd = commandId + ':' + Date.now();
            fetch(`/_/SET/EXTSTATE/TK_MediaExplorer/webcmd/${uniqueCmd}`, { method: 'GET' })
                .then(() => {
                    if (commandId === 'TOGGLE_AUTO_ADVANCE') {
                        document.getElementById('status').textContent = 'Command Sent: Auto-Adv';
                    } else {
                        document.getElementById('status').textContent = 'Command: ' + commandId;
                    }
                    setTimeout(() => {
                        if (document.getElementById('status').textContent.startsWith('Command')) {
                            document.getElementById('status').textContent = 'Ready (v3.1-beta Cross-Platform)';
                        }
                    }, 1000);
                })
                .catch(e => document.getElementById('status').textContent = 'Error: ' + e.message);
        }
        
        function sendArrowKey(direction) {
            const keyCmd = 'KEY_' + direction.toUpperCase() + ':' + Date.now();
            fetch(`/_/SET/EXTSTATE/TK_MediaExplorer/webcmd/${keyCmd}`, { method: 'GET' })
                .then(() => {
                    document.getElementById('status').textContent = 'Arrow: ' + direction;
                    setTimeout(() => document.getElementById('status').textContent = 'Ready (v3.1-beta Cross-Platform)', 1000);
                })
                .catch(e => document.getElementById('status').textContent = 'Error: ' + e.message);
        }
        
        function sendTreeKey(direction) {
            const keyCmd = 'KEY_TREE_' + direction.toUpperCase() + ':' + Date.now();
            fetch(`/_/SET/EXTSTATE/TK_MediaExplorer/webcmd/${keyCmd}`, { method: 'GET' })
                .then(() => {
                    document.getElementById('status').textContent = 'Sidebar: ' + direction;
                    setTimeout(() => document.getElementById('status').textContent = 'Ready (v3.1-beta Cross-Platform)', 1000);
                })
                .catch(e => document.getElementById('status').textContent = 'Error: ' + e.message);
        }
        
        function toggleTheme() {
            const body = document.body;
            const current = body.getAttribute('data-theme') || 'default';
            let next = 'default';
            
            if (current === 'default') next = 'sleek';
            else if (current === 'sleek') next = 'reaper';
            else if (current === 'reaper') next = 'rainbow';
            else if (current === 'rainbow') next = 'future';
            else if (current === 'future') next = 'default';
            
            if (next === 'default') {
                body.removeAttribute('data-theme');
            } else {
                body.setAttribute('data-theme', next);
            }
            localStorage.setItem('tk_theme', next);
        }

        // Init Theme
        const savedTheme = localStorage.getItem('tk_theme');
        if (savedTheme && savedTheme !== 'default') {
            document.body.setAttribute('data-theme', savedTheme);
        }
        
        function updateStatus() {
            // Fetch Status JSON from ExtState (Disable Cache)
            fetch('/_/GET/EXTSTATE/TK_MediaExplorer/status', { cache: "no-store" })
                .then(r => r.text())
                .then(str => {
                    if (!str) return;
                    
                    // Check for REAPER error page (starts with <HTML>)
                    if (str.trim().startsWith('<')) {
                         document.getElementById('debug').style.display = 'block';
                         document.getElementById('debug').textContent = "Error: Received HTML instead of JSON. Check REAPER Web Interface settings.";
                         return;
                    }

                    try {
                        // Clean up the string
                        let cleanStr = str.trim();
                        
                        // REAPER sometimes returns "EXTSTATE section key value"
                        // We need to find the start of the JSON object
                        const jsonStartIndex = cleanStr.indexOf('{');
                        if (jsonStartIndex > -1) {
                            cleanStr = cleanStr.substring(jsonStartIndex);
                        }

                        // Sometimes ExtState returns the string wrapped in quotes?
                        // If it looks like "{\"is_playing\"...}" remove outer quotes and unescape
                        let jsonStr = cleanStr;
                        if (jsonStr.startsWith('"') && jsonStr.endsWith('"')) {
                            try {
                                jsonStr = JSON.parse(jsonStr); // This unescapes the string
                            } catch(e) {
                                // If unescaping fails, use original
                            }
                        }

                        const data = JSON.parse(jsonStr);
                        
                        const btnPlay = document.getElementById('btnPlay');
                        const btnPause = document.getElementById('btnPause');
                        const btnRepeat = document.getElementById('btnRepeat');
                        const btnAutoplay = document.getElementById('btnAutoplay');
                        const btnAutoAdv = document.getElementById('btnAutoAdv');
                        
                        // Helper to toggle active class
                        const toggleActive = (btn, isActive, className) => {
                            if (isActive) {
                                btn.classList.add(className);
                                btn.style.background = ''; // Clear inline style if present
                            } else {
                                btn.classList.remove(className);
                                btn.style.background = '';
                            }
                        };

                        // Play
                        toggleActive(btnPlay, data.is_playing, 'state-active-green');
                        
                        // Pause
                        toggleActive(btnPause, data.is_paused, 'state-active-orange');
                        
                        // Repeat
                        toggleActive(btnRepeat, data.is_repeat, 'state-active-blue');

                        // Autoplay
                        toggleActive(btnAutoplay, data.is_autoplay, 'state-active-blue');
                        
                        // Auto-Adv
                        toggleActive(btnAutoAdv, data.auto_advance, 'state-active-green');

                        // Update Progress Bar
                        if (data.progress !== undefined) {
                            const fill = document.getElementById('progressFill');
                            if(fill) fill.style.width = data.progress + '%';
                        }

                    } catch(e) { 
                        document.getElementById('debug').style.display = 'block';
                        document.getElementById('debug').textContent = "JSON Error: " + e.message + "\nReceived: " + str.substring(0, 100);
                    }
                })
                .catch(e => {
                    document.getElementById('debug').style.display = 'block';
                    document.getElementById('debug').textContent = "Fetch Error: " + e.message;
                });

            // Fetch Current File (Keep using file for now as it works and is low freq)
            fetch('/_/GET/EXTSTATE/TK_MediaExplorer/current_file', { cache: "no-store" })
                .then(r => r.text())
                .then(str => {
                    let data = str;
                    // Clean up REAPER response prefix if present
                    const sepIndex = data.indexOf('\t');
                    if (sepIndex > -1) {
                        // Usually format is: EXTSTATE \t section \t key \t value
                        // We want the last part
                        const parts = data.split('\t');
                        if (parts.length >= 4) {
                            data = parts.slice(3).join('\t');
                        }
                    }
                    
                    if (data && data.trim() !== '' && data.trim() !== 'Ready') {
                        document.getElementById('currentFile').textContent = data.trim();
                    } else {
                        document.getElementById('currentFile').textContent = 'Media Explorer Ready';
                    }
                })
                .catch(e => {});
            
            fetch('/_/GET/EXTSTATE/TK_MediaExplorer/current_folder', { cache: "no-store" })
                .then(r => r.text())
                .then(str => { 
                    let data = str;
                    const sepIndex = data.indexOf('\t');
                    if (sepIndex > -1) {
                        const parts = data.split('\t');
                        if (parts.length >= 4) data = parts.slice(3).join('\t');
                    }
                    // Always update, even if empty, to clear old folder name
                    if (data) document.getElementById('currentFolder').textContent = data.trim(); 
                })
                .catch(e => {});
            
            fetch('/_/GET/EXTSTATE/TK_MediaExplorer/selected_item', { cache: "no-store" })
                .then(r => r.text())
                .then(str => {
                    let data = str;
                    const sepIndex = data.indexOf('\t');
                    if (sepIndex > -1) {
                        const parts = data.split('\t');
                        if (parts.length >= 4) data = parts.slice(3).join('\t');
                    }
                    
                    if (data && data.trim() !== '') {
                        document.getElementById('selectedItem').textContent = data.trim();
                    } else {
                        document.getElementById('selectedItem').textContent = 'Selected: ---';
                    }
                })
                .catch(e => {});
        }
        
        setInterval(updateStatus, 1000);
        updateStatus();
    </script>
</body>
</html>]]
  

  local file = io.open(html_file, "w")
  if file then
    file:write(html_content)
    file:close()
    reaper.ShowConsoleMsg("TK Media Explorer: HTML interface installed to " .. html_file .. "\n")
    return true
  else
    reaper.MB("Failed to write HTML file to:\n" .. html_file .. "\n\nPlease check file permissions.", "Installation Error", 0)
    return false
  end
end


install_html_interface()

local me_hwnd = nil
local function get_media_explorer_hwnd()
  if not me_hwnd or not reaper.ValidatePtr(me_hwnd, "HWND") then
    me_hwnd = reaper.JS_Window_Find("Media Explorer", true)
    if not me_hwnd then
      reaper.OpenMediaExplorer("", false)
      reaper.defer(function()
        me_hwnd = reaper.JS_Window_Find("Media Explorer", true)
      end)
    end
  end
  return me_hwnd
end

local function is_listview_class(class_name)
  if not class_name then return false end
  local cn_lower = class_name:lower()
  return class_name == "SysListView32" or cn_lower:match("listview") or cn_lower:match("list")
end

local function is_treeview_class(class_name)
  if not class_name then return false end
  local cn_lower = class_name:lower()
  return class_name == "SysTreeView32" or cn_lower:match("treeview") or cn_lower:match("tree")
end

local function get_media_explorer_listview()
  local me_hwnd = get_media_explorer_hwnd()
  if not me_hwnd then return nil end
  

  local child_list = reaper.new_array({}, 1000)
  reaper.JS_Window_ArrayAllChild(me_hwnd, child_list)
  local child_addresses = child_list.table()
  
  for i = 1, #child_addresses do
    local child = reaper.JS_Window_HandleFromAddress(child_addresses[i])
    if child then
      local class_name = reaper.JS_Window_GetClassName(child)
      if is_listview_class(class_name) then
        return child
      end
    end
  end
  
  return nil
end

local function get_media_explorer_treeview()
  local me_hwnd = get_media_explorer_hwnd()
  if not me_hwnd then return nil end
  

  local child_list = reaper.new_array({}, 1000)
  reaper.JS_Window_ArrayAllChild(me_hwnd, child_list)
  local child_addresses = child_list.table()
  
  for i = 1, #child_addresses do
    local child = reaper.JS_Window_HandleFromAddress(child_addresses[i])
    if child then
      local class_name = reaper.JS_Window_GetClassName(child)
      if is_treeview_class(class_name) then
        return child
      end
    end
  end
  
  return nil
end

local function execute_media_explorer_command(cmd_id)
  local hwnd = get_media_explorer_hwnd()
  if not hwnd then
    reaper.ShowConsoleMsg("Media Explorer not found!\n")
    return false
  end
  
  reaper.ShowConsoleMsg(string.format("Executing ME command: %d\n", cmd_id))
  reaper.JS_WindowMessage_Send(hwnd, "WM_COMMAND", cmd_id, 0, 0, 0)
  return true
end

local auto_advance_active = false
local last_finished_filename = ""
local last_time_str = ""
local last_time_change_ts = 0
local is_paused = false


local last_json_str = ""
local last_filename_str = ""
local last_folder_str = ""
local last_selected_str = ""
local force_update = true

local last_cmd = ""

local function parse_time_seconds(str)
  local m, s = str:match("(%d+):(%d+%.%d+)")
  if m and s then
    return tonumber(m) * 60 + tonumber(s)
  end
  return 0
end

local function is_filesystem_path(text)
  if not text then return false end
  if text:match("^[A-Z]:\\") then return true end
  if text:match("\\") then return true end
  if text:match("^/") then return true end
  return false
end

local update_counter = 0
local function update_current_file()
  local filename = "Ready"
  local folder_path = ""
  local selected_item = ""
  local is_playing = false
  local time_info = ""
  
  local hwnd = get_media_explorer_hwnd()
  if hwnd then

    local child_list = reaper.new_array({}, 1000)
    reaper.JS_Window_ArrayAllChild(hwnd, child_list)
    local child_addresses = child_list.table()
    

    update_counter = update_counter + 1
    local debug = (update_counter % 50 == 0)
    
    local potential_db = ""
    local found_combobox_db = false
    local me_retval, me_left, me_top, me_right, me_bottom = reaper.JS_Window_GetRect(hwnd)
    if not me_retval then me_top = 0 end
    
    for i = 1, #child_addresses do
      local child = reaper.JS_Window_HandleFromAddress(child_addresses[i])
      if child then
        local text = reaper.JS_Window_GetTitle(child)
        local class = reaper.JS_Window_GetClassName(child)
        
        if text and text ~= "" and text ~= "Media Explorer" then

          if not folder_path or folder_path == "" then
            if is_filesystem_path(text) then
              folder_path = text
            end
          end
          

          if (not folder_path or folder_path == "") and class == "Edit" and text ~= "" then
             local c_retval, c_left, c_top, c_right, c_bottom = reaper.JS_Window_GetRect(child)
             if c_retval then
                 local rel_y = c_top - me_top
                 

                 if rel_y < 250 then 
                     local parent = reaper.JS_Window_GetParent(child)
                     local parent_class = reaper.JS_Window_GetClassName(parent)
                     

                     if parent_class == "ComboBox" or parent_class == "ComboBoxEx32" then

                         if not text:match("%.%w+$") and not text:match("^%d+:%d+") then
                             potential_db = text
                         end
                     end
                 end
             end
          end
          

          if text:match("^%d+:%d+%.%d+%s+/%s+%d+:%d+%.%d+$") then
            time_info = text
          end
          

          local text_lower = text:lower()
          if text_lower:match("%.mp3$") or text_lower:match("%.wav$") or text_lower:match("%.flac$") or 
             text_lower:match("%.ogg$") or text_lower:match("%.m4a$") or text_lower:match("%.aif[f]?$") or
             text_lower:match("%.wma$") or text_lower:match("%.aac$") then
            filename = text
            is_playing = true
          end
        end
      end
    end
    

    if folder_path == "" and potential_db ~= "" then
        folder_path = potential_db
    end


    local listview = get_media_explorer_listview()
    if listview then
      local item_count = reaper.JS_ListView_GetItemCount(listview)
      for i = 0, item_count - 1 do
        local state = reaper.JS_ListView_GetItemState(listview, i)
        if state and (state & 2 == 2) then
          local item_text = reaper.JS_ListView_GetItemText(listview, i, 0)
          if item_text and item_text ~= "" then
            selected_item = item_text
            break
          end
        end
      end
    end
  end
  


  local state_play = reaper.GetToggleCommandStateEx(32063, 1009)
  

  local curr_sec = 0
  if time_info ~= "" then
    local curr_str = time_info:match("^(%d+:%d+%.%d+)")
    if curr_str then
        curr_sec = parse_time_seconds(curr_str)
    end
  end

  if state_play == 1 then
    is_playing = true
    is_paused = false

    last_time_str = time_info
    last_time_change_ts = reaper.time_precise()
  else

    is_playing = false
    


    if curr_sec > 0.0 then

        if time_info == last_time_str then

             is_paused = true
        else


             is_playing = true
             is_paused = false
             last_time_str = time_info
             last_time_change_ts = reaper.time_precise()
        end
    else

        is_paused = false
    end
  end


  local is_repeat = (reaper.GetToggleCommandStateEx(32063, 1068) == 1)
  local is_autoplay = (reaper.GetToggleCommandStateEx(32063, 1011) == 1)


  local progress_pct = 0
  if time_info ~= "" then
    local curr_str, tot_str = time_info:match("^(.*)%s+/%s+(.*)$")
    if curr_str and tot_str then
        local c = parse_time_seconds(curr_str)
        local t = parse_time_seconds(tot_str)
        if t > 0 then
            progress_pct = (c / t) * 100
            if progress_pct > 100 then progress_pct = 100 end
        end
    end
  end


  local json_str = string.format(
      '{"is_playing": %s, "is_paused": %s, "is_repeat": %s, "is_autoplay": %s, "auto_advance": %s, "progress": %.1f}',
      tostring(is_playing), tostring(is_paused), tostring(is_repeat), tostring(is_autoplay), tostring(auto_advance_active), progress_pct
  )
  

  reaper.SetExtState("TK_MediaExplorer", "status", json_str, false)
  

  reaper.SetExtState("TK_MediaExplorer", "current_file", filename, false)
  reaper.SetExtState("TK_MediaExplorer", "current_folder", folder_path, false)
  reaper.SetExtState("TK_MediaExplorer", "selected_item", selected_item, false)
  

  if update_counter % 100 == 0 then

  end

  return is_playing, filename, time_info
end

local function check_commands()
  local cmd_str = reaper.GetExtState("TK_MediaExplorer", "webcmd")
  
  if cmd_str ~= "" and cmd_str ~= last_cmd then
    last_cmd = cmd_str
    reaper.ShowConsoleMsg("Received command: " .. cmd_str .. "\n")
    

    if cmd_str:match("^KEY_TREE_") then
      local key_direction = cmd_str:match("^KEY_TREE_(%w+)")
      local treeview = get_media_explorer_treeview()
      
      if treeview and key_direction then
        local vkey_code = nil
        if key_direction == "UP" then vkey_code = 0x26 end
        if key_direction == "DOWN" then vkey_code = 0x28 end
        if key_direction == "ENTER" then vkey_code = 0x0D end
        
        if vkey_code then
          reaper.ShowConsoleMsg(string.format("Sending key to treeview: %s (0x%X)\n", key_direction, vkey_code))
          reaper.JS_WindowMessage_Send(treeview, "WM_KEYDOWN", vkey_code, 0, 0, 0)
          reaper.JS_WindowMessage_Send(treeview, "WM_KEYUP", vkey_code, 0, 0, 0)
        end
      else
        reaper.ShowConsoleMsg("Could not find treeview control!\n")
      end
      reaper.SetExtState("TK_MediaExplorer", "webcmd", "", false)
    elseif cmd_str:match("^KEY_") then
      local key_direction = cmd_str:match("^KEY_(%w+)")
      local listview = get_media_explorer_listview()
      
      if listview and key_direction then
        local vkey_code = nil
        if key_direction == "UP" then
          vkey_code = 0x26
        elseif key_direction == "DOWN" then
          vkey_code = 0x28
        elseif key_direction == "LEFT" then
          vkey_code = 0x25
        elseif key_direction == "RIGHT" then
          vkey_code = 0x27
        end
        
        if vkey_code then
          reaper.ShowConsoleMsg(string.format("Sending arrow key to listview: %s (0x%X)\n", key_direction, vkey_code))

          reaper.JS_WindowMessage_Send(listview, "WM_KEYDOWN", vkey_code, 0, 0, 0)

          reaper.JS_WindowMessage_Send(listview, "WM_KEYUP", vkey_code, 0, 0, 0)
        end
      else
        reaper.ShowConsoleMsg("Could not find listview control!\n")
      end
      reaper.SetExtState("TK_MediaExplorer", "webcmd", "", false)
    elseif cmd_str:match("^OPEN_FOLDER") then
      local listview = get_media_explorer_listview()
      local should_open = false
      local current_path = reaper.GetExtState("TK_MediaExplorer", "current_folder")
      local separator = reaper.GetOS():find("Win") and "\\" or "/"

      if listview then
        local item_count = reaper.JS_ListView_GetItemCount(listview)
        for i = 0, item_count - 1 do
          local state = reaper.JS_ListView_GetItemState(listview, i)
          if state and (state & 2 == 2) then
            local text = reaper.JS_ListView_GetItemText(listview, i, 0)
            
            if text and text ~= "" then
                if current_path:match("^DB:") then
                    if not text:match("%.%w+$") then
                        should_open = true
                    end
                else
                    local is_dir = false
                    local idx = 0
                    while true do
                        local subdir = reaper.EnumerateSubdirectories(current_path, idx)
                        if not subdir then break end
                        if subdir == text then
                            is_dir = true
                            break
                        end
                        idx = idx + 1
                    end
                    
                    if is_dir then
                        should_open = true
                    end
                end
            end
            break
          end
        end
      end

      if should_open then
        execute_media_explorer_command(1013)
        reaper.defer(function()
          local listview = get_media_explorer_listview()
          if listview then
            reaper.JS_WindowMessage_Send(listview, "WM_KEYDOWN", 0x24, 0, 0, 0)
          end
        end)
      end
      reaper.SetExtState("TK_MediaExplorer", "webcmd", "", false)
    elseif cmd_str:match("^TOGGLE_AUTO_ADVANCE") then
      auto_advance_active = not auto_advance_active
      last_finished_filename = ""
      reaper.ShowConsoleMsg("Auto-Advance: " .. tostring(auto_advance_active) .. "\n")
      reaper.SetExtState("TK_MediaExplorer", "webcmd", "", false)
    else

      local cmd_id = tonumber(cmd_str:match("^(%d+)"))
      
      if cmd_id then
        if cmd_id == 50124 then

            reaper.Main_OnCommand(50124, 0)
        else

            local hwnd = get_media_explorer_hwnd()
            if not hwnd then

                reaper.Main_OnCommand(50124, 0)
                

                local attempts = 0
                local function retry_cmd()
                    hwnd = get_media_explorer_hwnd()
                    if hwnd then
                        execute_media_explorer_command(cmd_id)
                    else
                        attempts = attempts + 1
                        if attempts < 10 then reaper.defer(retry_cmd) end
                    end
                end
                reaper.defer(retry_cmd)
            else
                execute_media_explorer_command(cmd_id)
            end
        end
        reaper.SetExtState("TK_MediaExplorer", "webcmd", "", false)
      end
    end
  end
  
  local is_playing, current_filename, time_info = update_current_file()
  

  if auto_advance_active and time_info ~= "" then
    local curr_str, tot_str = time_info:match("^(.*)%s+/%s+(.*)$")
    if curr_str and tot_str then
      local curr_sec = parse_time_seconds(curr_str)
      local tot_sec = parse_time_seconds(tot_str)
      


      if tot_sec > 0 and curr_sec >= (tot_sec - 0.1) then
        if current_filename ~= last_finished_filename then
          reaper.ShowConsoleMsg("Auto-advancing: " .. current_filename .. "\n")
          last_finished_filename = current_filename
          
          execute_media_explorer_command(40030)
          

          reaper.defer(function()
            execute_media_explorer_command(1009)
          end)
        end
      elseif curr_sec < 0.5 then


        if last_finished_filename == current_filename then
           last_finished_filename = ""
        end
      end
    end
  end
  
  reaper.defer(check_commands)
end

reaper.ShowConsoleMsg("\n=== TK Media Explorer Web Bridge (Cross-Platform Test) ===\n")
reaper.ShowConsoleMsg("✅ Bridge is running!\n")
reaper.ShowConsoleMsg("📱 Listening for web commands...\n")
reaper.ShowConsoleMsg("Media Explorer will be controlled via ExtState\n")
reaper.ShowConsoleMsg("OS: " .. reaper.GetOS() .. "\n\n")

reaper.SetExtState("TK_MediaExplorer", "webcmd", "", false)

check_commands()
