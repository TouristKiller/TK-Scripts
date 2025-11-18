-- @description TK Media Explorer Web Controller - Bridge Script
-- @author TK (TouristKiller)
-- @version 1.7
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
--   v1.7: HTML now embedded in script and auto-installed to reaper_www_root

-- Check for required extension
if not reaper.JS_Window_Find then
  reaper.MB("This script requires js_ReaScriptAPI extension.\n\nInstall via:\nExtensions → ReaPack → Browse packages\nSearch for 'js_ReaScriptAPI'", "Missing Extension", 0)
  return
end

-- Install HTML interface to reaper_www_root
local function install_html_interface()
  local resource_path = reaper.GetResourcePath()
  local www_path = resource_path .. "/reaper_www_root"
  local html_file = www_path .. "/TK_MediaExplorer.html"
  
  -- Create reaper_www_root directory if it doesn't exist
  reaper.RecursiveCreateDirectory(www_path, 0)
  
  -- HTML content (embedded in script)
  local html_content = [[<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
    <title>Media Explorer Controller</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Arial, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 20px;
            color: white;
        }
        .container {
            background: rgba(255, 255, 255, 0.1);
            backdrop-filter: blur(10px);
            border-radius: 20px;
            padding: 30px;
            max-width: 500px;
            width: 100%;
            box-shadow: 0 8px 32px rgba(0, 0, 0, 0.3);
        }
        h1 {
            text-align: center;
            margin-bottom: 10px;
            font-size: 28px;
            text-shadow: 2px 2px 4px rgba(0, 0, 0, 0.3);
        }
        .current-file {
            background: rgba(0, 0, 0, 0.2);
            padding: 15px;
            border-radius: 10px;
            text-align: center;
            margin-bottom: 30px;
            min-height: 50px;
            display: flex;
            align-items: center;
            justify-content: center;
            font-size: 14px;
            word-break: break-all;
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
            background: rgba(255, 255, 255, 0.9);
            border: none;
            padding: 18px 25px;
            border-radius: 50px;
            font-size: 18px;
            cursor: pointer;
            transition: all 0.3s;
            box-shadow: 0 4px 15px rgba(0, 0, 0, 0.2);
            flex: 1;
            max-width: 200px;
            font-weight: 600;
            color: #667eea;
        }
        button:active {
            transform: scale(0.95);
            box-shadow: 0 2px 8px rgba(0, 0, 0, 0.2);
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🎵 Media Explorer</h1>
        <div class="current-file" id="currentFile">REAPER Connected</div>
        <div class="current-file" id="currentFolder" style="font-size: 11px; min-height: 30px; margin-top: -20px;">📁 Folder</div>
        <div class="current-file" id="selectedItem" style="font-size: 13px; min-height: 35px; margin-top: -15px; background: rgba(255, 200, 0, 0.2);">Selected</div>
        
        <div class="controls">
            <div class="button-row">
                <button onclick="sendCommand(40024)">▶️ Play/Stop</button>
            </div>
            
            <div class="button-row">
                <button onclick="sendCommand(42184)">🔀 Random</button>
                <button onclick="sendCommand(1068)">🔁 Repeat</button>
            </div>
            
            <div class="button-row">
                <button onclick="sendArrowKey('up')">⬆️ Up List</button>
                <button onclick="sendArrowKey('down')">⬇️ Down List</button>
            </div>
            
            <div class="button-row">
                <button onclick="sendCommand(1004)">◀️ Back</button>
                <button onclick="sendCommand(1013)">📁 Open</button>
            </div>
            
            <div class="button-row">
                <button onclick="sendCommand(42178)">🔉 Vol -</button>
                <button onclick="sendCommand(42177)">🔊 Vol +</button>
            </div>
        </div>
        
        <div class="status" id="status">Ready</div>
    </div>

    <script>
        function sendCommand(commandId) {
            const uniqueCmd = commandId + ':' + Date.now();
            fetch(`/_/SET/EXTSTATE/TK_MediaExplorer/webcmd/${uniqueCmd}`, { method: 'GET' })
                .then(() => {
                    document.getElementById('status').textContent = 'Command: ' + commandId;
                    setTimeout(() => document.getElementById('status').textContent = 'Ready', 1000);
                })
                .catch(e => document.getElementById('status').textContent = 'Error: ' + e.message);
        }
        
        function sendArrowKey(direction) {
            const keyCmd = 'KEY_' + direction.toUpperCase() + ':' + Date.now();
            fetch(`/_/SET/EXTSTATE/TK_MediaExplorer/webcmd/${keyCmd}`, { method: 'GET' })
                .then(() => {
                    document.getElementById('status').textContent = 'Arrow: ' + direction;
                    setTimeout(() => document.getElementById('status').textContent = 'Ready', 1000);
                })
                .catch(e => document.getElementById('status').textContent = 'Error: ' + e.message);
        }
        
        function updateStatus() {
            fetch('/TK_currentfile.txt', { method: 'GET', cache: 'no-cache' })
                .then(r => r.text())
                .then(data => {
                    if (data && data.trim() !== '' && data.trim() !== 'Ready') {
                        document.getElementById('currentFile').textContent = data.trim();
                    } else {
                        document.getElementById('currentFile').textContent = 'Media Explorer Ready';
                    }
                })
                .catch(e => document.getElementById('currentFile').textContent = 'REAPER Connected');
            
            fetch('/TK_currentfolder.txt', { method: 'GET', cache: 'no-cache' })
                .then(r => r.text())
                .then(data => { if (data && data.trim() !== '') document.getElementById('currentFolder').textContent = '📁 ' + data.trim(); })
                .catch(e => {});
            
            fetch('/TK_selecteditem.txt', { method: 'GET', cache: 'no-cache' })
                .then(r => r.text())
                .then(data => {
                    if (data && data.trim() !== '') {
                        document.getElementById('selectedItem').textContent = data.trim();
                    } else {
                        document.getElementById('selectedItem').textContent = 'Selected: ---';
                    }
                })
                .catch(e => document.getElementById('selectedItem').textContent = 'Selected: ---');
        }
        
        setInterval(updateStatus, 1000);
        updateStatus();
    </script>
</body>
</html>]]
  
  -- Write HTML file (always overwrite to ensure updates)
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

-- Install HTML on startup
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

local function get_media_explorer_listview()
  local me_hwnd = get_media_explorer_hwnd()
  if not me_hwnd then return nil end
  
  -- Find the SysListView32 control (the file list)
  local child_list = reaper.new_array({}, 1000)
  reaper.JS_Window_ArrayAllChild(me_hwnd, child_list)
  local child_addresses = child_list.table()
  
  for i = 1, #child_addresses do
    local child = reaper.JS_Window_HandleFromAddress(child_addresses[i])
    if child then
      local class_name = reaper.JS_Window_GetClassName(child)
      if class_name == "SysListView32" then
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

local update_counter = 0
local function update_current_file()
  local filename = "Ready"
  local folder_path = ""
  local selected_item = ""
  
  local hwnd = get_media_explorer_hwnd()
  if hwnd then
    -- Try to find status bar or text field with filename
    local child_list = reaper.new_array({}, 1000)
    reaper.JS_Window_ArrayAllChild(hwnd, child_list)
    local child_addresses = child_list.table()
    
    -- Only print debug info every 50 updates to avoid spam
    update_counter = update_counter + 1
    local debug = (update_counter % 50 == 0)
    
    for i = 1, #child_addresses do
      local child = reaper.JS_Window_HandleFromAddress(child_addresses[i])
      if child then
        local text = reaper.JS_Window_GetTitle(child)
        if text and text ~= "" and text ~= "Media Explorer" then
          -- Check if it looks like a folder path (starts with drive letter or has backslashes)
          if not folder_path or folder_path == "" then
            if text:match("^[A-Z]:\\") or text:match("\\") then
              folder_path = text
            end
          end
          
          -- Check if it looks like an audio filename
          if text:match("%.mp3$") or text:match("%.wav$") or text:match("%.flac$") or 
             text:match("%.ogg$") or text:match("%.m4a$") or text:match("%.aif[f]?$") or
             text:match("%.wma$") or text:match("%.aac$") then
            filename = "▶️ " .. text
            break
          end
        end
      end
    end
    
    -- Try to get selected item from listview
    local listview = get_media_explorer_listview()
    if listview then
      local item_count = reaper.JS_ListView_GetItemCount(listview)
      for i = 0, item_count - 1 do
        local state = reaper.JS_ListView_GetItemState(listview, i)
        if state and (state & 2 == 2) then -- Check if LVIS_SELECTED flag is set
          local item_text = reaper.JS_ListView_GetItemText(listview, i, 0)
          if item_text and item_text ~= "" then
            selected_item = "📌 " .. item_text
            break
          end
        end
      end
    end
  end
  
  -- Write filename
  local resource_path = reaper.GetResourcePath()
  local file_path = resource_path .. "/reaper_www_root/TK_currentfile.txt"
  local file = io.open(file_path, "w")
  if file then
    file:write(filename)
    file:close()
  end
  
  -- Write folder path
  if folder_path ~= "" then
    local folder_file_path = resource_path .. "/reaper_www_root/TK_currentfolder.txt"
    local folder_file = io.open(folder_file_path, "w")
    if folder_file then
      folder_file:write(folder_path)
      folder_file:close()
    end
  end
  
  -- Write selected item
  if selected_item ~= "" then
    local selected_file_path = resource_path .. "/reaper_www_root/TK_selecteditem.txt"
    local selected_file = io.open(selected_file_path, "w")
    if selected_file then
      selected_file:write(selected_item)
      selected_file:close()
    end
  end
end

local last_cmd = ""
local function check_commands()
  local cmd_str = reaper.GetExtState("TK_MediaExplorer", "webcmd")
  
  if cmd_str ~= "" and cmd_str ~= last_cmd then
    last_cmd = cmd_str
    reaper.ShowConsoleMsg("Received command: " .. cmd_str .. "\n")
    
    -- Check if it's an arrow key command
    if cmd_str:match("^KEY_") then
      local key_direction = cmd_str:match("^KEY_(%w+)")
      local listview = get_media_explorer_listview()
      
      if listview and key_direction then
        local vkey_code = nil
        if key_direction == "UP" then
          vkey_code = 0x26  -- VK_UP
        elseif key_direction == "DOWN" then
          vkey_code = 0x28  -- VK_DOWN
        elseif key_direction == "LEFT" then
          vkey_code = 0x25  -- VK_LEFT
        elseif key_direction == "RIGHT" then
          vkey_code = 0x27  -- VK_RIGHT
        end
        
        if vkey_code then
          reaper.ShowConsoleMsg(string.format("Sending arrow key to listview: %s (0x%X)\n", key_direction, vkey_code))
          -- Send key down
          reaper.JS_WindowMessage_Send(listview, "WM_KEYDOWN", vkey_code, 0, 0, 0)
          -- Send key up
          reaper.JS_WindowMessage_Send(listview, "WM_KEYUP", vkey_code, 0, 0, 0)
        end
      else
        reaper.ShowConsoleMsg("Could not find listview control!\n")
      end
      reaper.SetExtState("TK_MediaExplorer", "webcmd", "", false)
    else
      -- Normal command
      local cmd_id = tonumber(cmd_str:match("^(%d+)"))
      
      if cmd_id then
        execute_media_explorer_command(cmd_id)
        reaper.SetExtState("TK_MediaExplorer", "webcmd", "", false)
      end
    end
  end
  
  update_current_file()
  
  reaper.defer(check_commands)
end

reaper.ShowConsoleMsg("\n=== TK Media Explorer Web Bridge ===\n")
reaper.ShowConsoleMsg("✅ Bridge is running!\n")
reaper.ShowConsoleMsg("📱 Listening for web commands...\n")
reaper.ShowConsoleMsg("Media Explorer will be controlled via ExtState\n\n")

reaper.SetExtState("TK_MediaExplorer", "webcmd", "", false)

check_commands()
