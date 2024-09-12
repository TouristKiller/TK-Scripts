-- @description CopyAllEnvelope
-- @author TouristKiller
-- @version 1.0
-- @about
--   # CopyAllEnvelope
--   This script copies all envelope points from selected tracks within the defined time selection. 
--   It captures the start and end values, as well as all intermediate points, for each envelope on the selected tracks.
--   The copied data is then serialized and stored in the REAPER extended state for later use. Use together with PasteAllEnvelope.



function GetEnvelopeValueAtTime(env, time)
  local retval, value, _, _, _ = reaper.Envelope_Evaluate(env, time, 0, 0)
  return value
end

function serialize(data)
  local str = ""
  for i, track in ipairs(data) do
    str = str .. #track .. ";"
    for j, env in ipairs(track) do
      str = str .. #env.points .. "," .. env.start_value .. "," .. env.end_value .. "," .. env.duration .. ";"
      for _, point in ipairs(env.points) do
        str = str .. point.time .. "," .. point.value .. "," .. point.shape .. "," .. point.tension .. ";"
      end
    end
    str = str .. "|"
  end
  return str
end

function main()
  reaper.Undo_BeginBlock()
  
  start_time, end_time = reaper.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
  
  if start_time ~= end_time then
    start_time = math.floor(start_time * 100000000+0.5)/100000000
    end_time = math.floor(end_time * 100000000+0.5)/100000000
    
    copied_envelopes = {}
    
    selected_tracks_count = reaper.CountSelectedTracks(0)
    
    for i = 0, selected_tracks_count - 1 do
      track = reaper.GetSelectedTrack(0, i)
      track_envelopes = {}
      
      env_count = reaper.CountTrackEnvelopes(track)
      
      for j = 0, env_count - 1 do
        env = reaper.GetTrackEnvelope(track, j)
        env_points = {}
        
        env_points_count = reaper.CountEnvelopePoints(env)
        
        for k = 0, env_points_count - 1 do 
          retval, time, value, shape, tension, selected = reaper.GetEnvelopePoint(env, k)
          if time >= start_time and time <= end_time then
            table.insert(env_points, {time = time - start_time, value = value, shape = shape, tension = tension})
          end
        end
        
        start_value = GetEnvelopeValueAtTime(env, start_time)
        end_value = GetEnvelopeValueAtTime(env, end_time)
        
        table.insert(track_envelopes, {points = env_points, start_value = start_value, end_value = end_value, duration = end_time - start_time})
      end
      
      table.insert(copied_envelopes, track_envelopes)
    end
    
    reaper.SetExtState("TK_CopyAllEnvelopes", "CopiedData", serialize(copied_envelopes), false)
  end
  
  reaper.Undo_EndBlock("Copy all envelope points", -1)
end

main()
