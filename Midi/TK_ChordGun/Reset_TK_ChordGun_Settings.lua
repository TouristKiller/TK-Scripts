-- Wis de opgeslagen venstergrootte van ChordGun (Global ExtState)
reaper.DeleteExtState("TK_ChordGun", "interfaceWidth", true)
reaper.DeleteExtState("TK_ChordGun", "interfaceHeight", true)
-- Position is not stored in Global, but deleting just in case
reaper.DeleteExtState("TK_ChordGun", "windowX", true)
reaper.DeleteExtState("TK_ChordGun", "windowY", true)

-- Wis de opgeslagen venstergrootte van ChordGun (Project ExtState)
-- Dit is belangrijk omdat getPersistentNumber terugvalt op Project ExtState als Global leeg is!
local projectSection = "com.touristkiller.TK_ChordGun"
-- Gebruik SetProjExtState met lege string om te verwijderen (DeleteExtState werkt alleen voor Global)
reaper.SetProjExtState(0, projectSection, "interfaceWidth", "")
reaper.SetProjExtState(0, projectSection, "interfaceHeight", "")
reaper.SetProjExtState(0, projectSection, "interfaceXPosition", "")
reaper.SetProjExtState(0, projectSection, "interfaceYPosition", "")

reaper.ShowMessageBox("ChordGun instellingen gewist (Global & Project)!\n\nStart het script nu opnieuw op om de 'Smart Initial Scaling' te testen.", "Reset Klaar", 0)
