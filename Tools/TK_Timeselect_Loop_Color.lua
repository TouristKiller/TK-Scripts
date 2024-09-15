-- @description TK_Timeselect_Loop_Color
-- @version 1.0
-- @author TouristKiller
-- @about
--   # if script is enabled, you can switch the time selection and arrange within that time selection color when the loop function is turned on or off.
-- @changelog
--   - Initial Release


function ChangeTimeSelectionColor()
    local is_loop_enabled = reaper.GetSetRepeat(-1)
    
    if is_loop_enabled == 1 then
      reaper.SetThemeColor("col_tl_bgsel", 0x0000FF, 0)
      reaper.SetThemeColor("col_tl_bgsel2", 0x0000FF, 0)  -- loop on colorloop on color
    else
      reaper.SetThemeColor("col_tl_bgsel", 0xFFFFFF, 0)
      reaper.SetThemeColor("col_tl_bgsel2", 0xFFFFFF, 0)
    end
    
    reaper.UpdateArrange()
    reaper.UpdateTimeline()
  end
  
  function Main()
    ChangeTimeSelectionColor()
    reaper.defer(Main)
  end
  
  Main()
  