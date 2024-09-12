-- @description PasteAllEnvelope
-- @version 1.0
-- @author TouristKiller
-- @about
--   # PasteAllEnvelope
--   This script retrieves the previously copied envelope data from REAPER's extended state and pastes it onto the selected tracks at the current edit cursor position
--   It handles both regular envelopes and on/off (mute) envelopes differently, ensuring smooth transitions at the start and end of the pasted section. 
--   The script also takes care to maintain the original envelope shapes and tensions.



function unserialize(str)
  local data = {}
  for track_str in str:gmatch("[^|]+") do
    local track = {}
    local parts = {}
    for part in track_str:gmatch("[^;]+") do
      table.insert(parts, part)
    end
    local num_envs = tonumber(parts[1])
    local index = 2
    for i = 1, num_envs do
      local env = {points = {}}
      local num_points, start_value, end_value, duration = parts[index]:match("([^,]+),([^,]+),([^,]+),([^,]+)")
      env.start_value = tonumber(start_value)
      env.end_value = tonumber(end_value)
      env.duration = tonumber(duration)
      index = index + 1
      for j = 1, tonumber(num_points) do
        local time, value, shape, tension = parts[index]:match("([^,]+),([^,]+),([^,]+),([^,]+)")
        table.insert(env.points, {time = tonumber(time), value = tonumber(value), shape = tonumber(shape), tension = tonumber(tension)})
        index = index + 1
      end
      table.insert(track, env)
    end
    table.insert(data, track)
  end
  return data
end

function InsertEnvelopePointSafe(env, time, value, shape, tension)
if type(time) == "number" and type(value) == "number" and type(shape) == "number" and type(tension) == "number" then
  reaper.InsertEnvelopePoint(env, time, value, shape, tension, false, true)
end
end

function isOnOffEnvelope(env)
local retval, envName = reaper.GetEnvelopeName(env, "")
return envName:lower():find("mute") or envName:lower():find("on/off")
end

function main()
reaper.Undo_BeginBlock()

cursor_pos = reaper.GetCursorPosition()

local copied_data = reaper.GetExtState("TK_CopyAllEnvelopes", "CopiedData")
if copied_data ~= "" then
  copied_envelopes = unserialize(copied_data)
  
  selected_tracks_count = reaper.CountSelectedTracks(0)
  
  for i = 0, math.min(selected_tracks_count, #copied_envelopes) - 1 do
    track = reaper.GetSelectedTrack(0, i)
    track_envelopes = copied_envelopes[i+1]
    
    for j = 0, math.min(reaper.CountTrackEnvelopes(track), #track_envelopes) - 1 do
      env = reaper.GetTrackEnvelope(track, j)
      env_data = track_envelopes[j+1]
      
      if env and env_data then
        local isOnOff = isOnOffEnvelope(env)
        
      
        local retval, start_value, _, _, _ = reaper.Envelope_Evaluate(env, cursor_pos, 0, 0)
  
        local retval, end_value, _, _, _ = reaper.Envelope_Evaluate(env, cursor_pos + env_data.duration, 0, 0)
        
        if not isOnOff then
      
          InsertEnvelopePointSafe(env, cursor_pos, start_value, 0, 0)
          InsertEnvelopePointSafe(env, cursor_pos, env_data.start_value, 0, 0)
        end
        
  
        for _, point in ipairs(env_data.points) do
          InsertEnvelopePointSafe(env, cursor_pos + point.time, point.value, point.shape, point.tension)
        end
        
        if not isOnOff then
      
          InsertEnvelopePointSafe(env, cursor_pos + env_data.duration, env_data.end_value, 0, 0)
          InsertEnvelopePointSafe(env, cursor_pos + env_data.duration, end_value, 0, 0)
        end
        
        reaper.Envelope_SortPoints(env)
      end
    end
  end
end

reaper.Undo_EndBlock("Paste all envelope points with direct transitions", -1)
reaper.UpdateArrange()
end

main()
