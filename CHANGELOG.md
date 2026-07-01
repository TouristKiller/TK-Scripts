# Changelog

Alle belangrijke wijzigingen aan dit script pakket worden hieronder bijgehouden.

## [TK Trackname in Arrange 1.9.3] - 2026-07-01

### TK Trackname in Arrange
#### Bugfixes
- **macOS/Retina zichtbaarheid**: Tracknamen en envelope-waardes verdwenen voor tracks onder het midden van de arrange. Het zichtbare bereik wordt nu afgeleid uit de overlay-geometrie in plaats van de onbetrouwbare client-rect hoogte.
- **Volume envelope waardes**: Waarde-labels van volume-envelopes dreven bij hogere lanes weg van hun punten. De positionering gebruikt nu het fader-geschaalde domein, zodat de labels op de punten blijven plakken.

## [TK Transport 1.9.9] - 2026-06-11

### TK Transport
#### Bugfixes
- **Settings tijdens verslepen**: Foutmelding "bad argument #5 (number has no integer representation)" opgelost die kon optreden bij het openen van de Settings terwijl het transportpaneel werd versleept.

## [TK FX Tabs 1.0.2] - 2026-06-10

### TK FX Tabs
#### Toegevoegd
- **Tabbar edge calibration**: Linker- en rechterrand van de tabbar kunnen nu apart worden afgesteld vanuit de settings.

#### Gewijzigd
- **Floating FX positionering**: Tabbar-breedtecorrecties blijven los van de floating FX-window positie, zodat het FX-window niet meesnapt tijdens edge calibration.

## [TK Workbench 0.2.8] - 2026-06-06

### TK Workbench
#### Bugfixes
- **Tags module installatie**: `modules/track_tags.lua` toegevoegd aan de ReaPack package index, zodat de Tags-module correct wordt meegeinstalleerd bij Workbench updates.

## [TK Workbench 0.2.7] - 2026-06-06

### TK Workbench
#### Toegevoegd
- **Auto-collapse**: Floating Workbench kan automatisch inklappen naar een smalle randstrip met REAPER edge pinning.
- **Auto-collapse voorkeuren**: Edge offset en close delay toegevoegd zodat gebruikers zelf kunnen bepalen hoeveel ruimte Workbench vrijlaat en hoe snel het venster inklapt.
- **Auto-height modes**: Auto-collapse kan de hoogte volgen van manual height, arrange height, REAPER window height of arrange-to-window-bottom height.
- **Keep-expanded pin**: Pin-knop toegevoegd om Workbench tijdelijk uitgeklapt te houden.
- **Module error logging**: Modulefouten worden gelogd naar `workbench_errors.txt` voor betere diagnose bij gebruikersrapporten.

#### Gewijzigd
- **Auto-collapse gedrag**: Workbench blijft uitgeklapt zolang popups, dropdowns, hovered popup windows of actieve module-acties open zijn.
- **Auto-collapse positionering**: Native-to-ImGui coordinate conversion verbeterd voor scaling en multi-monitor setups.
- **Docked gedrag**: Auto-collapse voorkeuren zijn uitgeschakeld wanneer Workbench gedockt is, omdat auto-collapse alleen voor floating windows geldt.
- **Module errors**: Statuslabels zijn specifieker en stale draw errors van inactieve modules nemen de globale statusbalk niet meer over.

#### Bugfixes
- **Plugin Browser**: External FX drag overlay staat nu correct op secundaire monitoren.
- **Plugin Browser**: Workbench blijft uitgeklapt tijdens pending en actieve external FX drags zodat drops niet worden onderbroken.
- **Tags**: Track GUID handling robuuster gemaakt met persistente fallbacks en zonder onstabiele index-fallbacks.
- **Tags**: Store path handling verbeterd voor portable installaties en custom Workbench-locaties.
- **Tags**: Tag-kleuren worden genormaliseerd en compacte pane heights worden defensief begrensd.

## [TK Workbench 0.2.5] - 2026-06-04

### TK Workbench
#### Toegevoegd
- **Split screen**: Workbench kan nu twee modules boven elkaar tonen met een verstelbare splitter, swap-knop en gedeelde shell-controls.
- **Timepiece module**: Nieuwe klokmodule toegevoegd met grote tijdweergave voor time, local clock, measures/beats, beats/ticks, seconds, samples en frames.
- **Timepiece next marker**: Optionele full-width next marker-balk toegevoegd onder de region progress en boven de badges.
- **Timepiece context badges**: Optionele project position, region progress, play rate, context info, lokale tijd en lokale datum toegevoegd.

#### Gewijzigd
- **Timepiece instellingen**: Status, BPM, signature, display mode, klokpositie, kloktekst-zichtbaarheid en extra badges staan in een compacte settings-popup.
- **Timepiece klokgedrag**: De hoofdklok volgt automatisch de play position tijdens transport en de edit cursor wanneer transport stilstaat.
- **Timepiece layout**: De hoofdklok kan nu bovenaan direct onder de statusregel worden weergegeven, met compactere afstand in top mode.

## [TK Workbench 0.2.3] - 2026-06-03

### TK Workbench
#### Toegevoegd
- **Instrument Rack**: TK FX Browser Mini toegevoegd als optie voor het Add FX target.
- **Project Browser en Media Browser**: Compact list view toegevoegd met kleinere rijafstand voor dichtere lijsten.

#### Gewijzigd
- **Project Browser**: Een via Browse gekozen locatie wordt nu direct toegevoegd en gescand, in plaats van alleen in het locatieveld te blijven staan.

## [TK Workbench 0.2.2] - 2026-06-03

### TK Workbench
#### Toegevoegd
- **Action Clipboard module**: Action Clipboard is losgetrokken uit de Action Browser en als zelfstandige Workbench-module toegevoegd.
- **Native action capture voor Windows/macOS/Linux**: Nieuwe `reaper_tk_action_capture` extensie vangt REAPER actions uit Action List, menus, toolbar buttons, floating toolbars, shortcuts en custom actions op.
- **Action Clipboard opener**: Nieuwe mappable module-action om Action Clipboard direct te openen.
- **Cross-platform native artifacts**: Windows x64, macOS universal en Linux x64 builds worden meegeleverd voor installatie in `REAPER/UserPlugins`.

#### Gewijzigd
- **Action Browser**: Clipboard footer verwijderd; acties kunnen nog steeds via contextmenu naar Action Clipboard worden gestuurd.
- **Native capture distributie**: Windows x64 DLL, macOS universal dylib en Linux x64 SO worden via ReaPack direct in de Workbench-map meegeleverd voor handmatige kopie naar `REAPER/UserPlugins`.

## [2.2.7] - 2025-11-24

### TK_ChordGun
#### Toegevoegd
- **Surprise Me (Randomize)**: Nieuwe dobbelsteen-knop in het akkoord-weergave vak. Vult lege slots in de progressie met willekeurige akkoorden (gewogen op basis van pop-muziek theorie: I, IV, V, vi komen vaker voor).
- **Randomize Settings**: Rechtsklik-menu op de dobbelsteen:
  - **Progression Length**: Kies tussen 4 of 8 slots.
  - **Always Start on Tonic**: Optie om de progressie altijd met de grondtoon (I) te laten beginnen.
  - **Clear Progression**: Snel de hele progressie wissen.
- **Sync Play**: Nieuwe "Sync" knop (naast Scale Type). Synchroniseert de ChordGun Tonic met de MIDI Editor Key Snap.
- **Transport Sync**: Play/Stop knoppen zijn nu gesynchroniseerd met het project transport (start/stop playback van Reaper).

## [2.2.0] - 2025-11-22

### TK_ChordGun
#### Toegevoegd
- **Automatic Voice Leading**: Nieuwe "Lead" knop. Berekent automatisch de beste inversie voor het volgende akkoord zodat de noten zo min mogelijk verspringen (smooth transitions).
- **Keyboard Shortcuts**: Uitgebreid naar 10 toetsen (0, ), p, ;, /).
- **Stop All Notes**: Spatiebalk toegevoegd als sneltoets om alle noten te stoppen.

#### Gewijzigd
- **Piano Display**: De piano toont nu correct de daadwerkelijk gespeelde noten, inclusief Voice Leading inversies en Drop/Bass voicings.
- **UI**: Chord Text Label verplaatst naar rechts (offset 250) en blauw gekleurd voor betere leesbaarheid.
- **Bugfix**: Opgelost probleem met "ghost notes" (dubbele noten) bij gebruik van Voice Leading.

## [2.0.9] - 2025-11-20

### TK_ChordGun
#### Toegevoegd
- **Melody Generator**: Nieuwe functie om willekeurige melodieën te genereren op basis van de akkoordprogressie.
- **Melody Settings**: Rechtsklik-menu op de Melody knop voor instellingen:
  - **Rhythm Density**: Slow, Normal, Fast.
  - **Octave Range**: Low, Mid, High.
  - **Note Selection**: Chord Tones Only of Include Scale Notes.
- **Preset Verbeteringen**: Presets slaan nu ook de **Scale** en **Tonic** op, zodat deze correct worden hersteld bij het laden.

#### Gewijzigd
- **Export to Chord Track**:
  - Track wordt nu onderaan het project toegevoegd (behoudt tracknummering).
  - Track wordt automatisch **vastgepind bovenaan** (Lock to top).
  - Track height en items worden vergrendeld (Locked).
- **UI**: Melody knop verplaatst naar de tweede rij (naast Ratio) voor betere indeling.

## [2.1.0] - 2025-11-28

### TK_SMART
#### Toegevoegd
- **Zoom Controls**: "+" knop om in te zoomen op een specifieke regio, en "-" knop om uit te zoomen naar het hele project.
- **Auto-Color Rules**: Nieuwe "Rules" tab om regels in te stellen (bijv. "Vocal" = Blauw). Inclusief "Auto-Apply on Rename" optie.

## Ongeversioneerd (werk in uitvoering)

### Toegevoegd
- **MIDI/Video playback options**:
  - **Independent playback mode**: Media browser speelt nu standaard onafhankelijk van project transport af
  - **Link mode**: Optionele synchronisatie tussen media browser en project playback (schakelbaar via LINK knop)
    - Start from edit cursor optie (via rechtermuisklik op LINK knop)
    - Bidirectionele synchronisatie: transport controls sturen ook media browser aan
  - **SOLO toggle**: Exclusieve solo mode voor MIDI/video files (verschijnt links van GRID knop)
    - Solo knop werkt onafhankelijk van playback status
    - Automatisch opslaan/herstellen van solo states
  - **Use Selected Track for MIDI**: Optie om MIDI files via geselecteerde track af te spelen
    - Gebruikt bestaande FX chain op geselecteerde track (geen automatische synth)
    - Error melding in MIDI info veld wanneer geen track geselecteerd is
    - Solo functionaliteit werkt ook met geselecteerde track
- **Selection preservation**: Bestandselectie in lijst en waveform blijven behouden tijdens playback start/stop
- **Transport startup wait loop**: Verbeterde synchronisatie timing (50ms wait, 1ms intervals) voor betrouwbare link mode
- **Pitch & Rate controls**: Volledige pitch en playback rate aanpassing van audio items met real-time preview
  - Pitch slider (-24 tot +24 semitonen) met fine-tuning
  - Rate slider (0.25x tot 4.0x speed) voor tempo aanpassingen  
  - "Preserve pitch" optie om pitch constant te houden bij rate changes
  - "Preserve formants" optie voor natuurlijkere vocal pitch shifting
  - Unified slider styling en responsieve UI controls
- **Sidebar tabs**: Edit en FX tabs in de verticale sidebar voor georganiseerde tool toegang
- Horizontale toolbar (boven de waveform) als alternatief voor de verticale sidebar; toggle via View menu, Settings popup en pijltje (collapse).
- Persistente instelling `sidebar_layout` (vertical/horizontal).
- Fallback hit-test voor horizontale collapse toggle (zorgt dat opnieuw uitklappen altijd werkt).
- Automatische selectie van het linker (originele) item na Split.
- Optionele auto-glue voor Reverse Selection via nieuwe setting `reverse_sel_glue_after` (Behavior menu: "Reverse selection: glue back to single item").
- Behavior menu optie voor reverse glue; opgeslagen in ExtState.
- Negatieve icon/tekst spacing ondersteuning (voor zeer compacte horizontal buttons).
- Tool indicator overlay in horizontale modus die actieve pencil/envelope mode toont (zoals in verticale modus).

### Gewijzigd
- Horizontal toolbar verplaatst naar boven de ruler; volledige breedte inclusief linker gutter; inhoud links uitgelijnd.
- Knoppen horizontale balk stijl gelijkgetrokken met verticale sidebar.
- Navigatieknoppen nu alleen pijlen en vierkant (icon-only) i.p.v. dubbele labels.
- Icon/tekst spacing herhaaldelijk geoptimaliseerd (laatste toestand: zeer compact, gebruiker experimenteerde met ICON_TEXT_GAP = -10).
- Split logica herschreven (deterministische selectie + direct laden nieuwe peaks).
- Reverse Selection herschreven: whole-item pad + selectie pad met optionele glue -> blijft één item.
- Ruler & waveform geometrie aangepast voor nieuwe balkhoogte.
- Verwijderd: automatische responsive modi (icon-only / overflow) — altijd volledige knoppen tonen.

### Bugfixes
- **SOLO toggle interferentie**: Verwijderd alle automatische solo logica uit play/stop functies; solo wordt nu alleen beheerd door toggle knop
- **Waveform seek tijdens SOLO**: Play cursor sprong naar knop locatie bij klikken op SOLO → `solo_hovered` check toegevoegd aan waveform click detection

## [Recent Updates]

### Toegevoegd
- **Spectral View**: FFT-gebaseerde frequentie analyse met kleurverloop (rood=bass, oranje=low-mid, groen=mid, blauw=high-mid, paars=high)
  - SPECTRAL toggle knop (alleen voor audio files)
  - 6-band frequentie analyse met compensatie en weighting
  - Cache systeem voor snelle weergave
- **Settings Preset Systeem**: Opslaan en laden van volledige settings configuraties via JSON
  - Save/Load/Delete presets in Settings view
  - Presets opgeslagen in PRESETS subfolder
  - Error handling voor corrupte bestanden
- **Waveform Zoom & Scroll**:
  - Horizontale zoom (Ctrl+Wheel, 1x tot 500x)
  - Verticale zoom (Ctrl+Alt+Wheel, 0.5x tot 10x)
  - Horizontaal scrollen (Wheel wanneer ingezoomd)
  - Mouse-centered zoom (zoom blijft op cursor positie)
  - Zoom indicators (H: % en V: % rechts boven)
  - RESET knop (links onder) om zoom terug te zetten
  - Alleen voor audio files (niet MIDI/video)
- **Dynamische Waveform Resolutie**: Waveform resolutie past zich automatisch aan window breedte (2x pixels voor extra detail)
- **Zoom-aware UI**: Ruler, play cursor, selection en grid overlay bewegen correct mee met zoom/scroll

### Gewijzigd
- SOLO, SPECTRAL en GRID knoppen verplaatst naar betere positie (10px omlaag)
- Spectral view en normale waveform beide ondersteund met zoom/scroll
- Waveform resolutie verhoogd van vaste 725 naar dynamisch 2x window breedte
- **Link mode timing**: Transport wait loop toegevoegd voor betrouwbare synchronisatie bij start
- **Selection reset bij stop**: Bestandslijst selectie bleef niet behouden → monitor_file_path logica toegevoegd
- Fix voor syntaxfout in info-knop callback (verkeerde multiple assignment).
- Dubbele weergave navigatiepijlen opgelost (icon + text → alleen icon).
- Collapse toggle werkte niet om uit te klappen → fallback hittest toegevoegd.
- Goto/label constructie verwijderd (Lua error) vervangen door conditionele flow.
- Split deselecteerde alle items → nu blijft linker deel geselecteerd.
- Debug venster dat verscheen bij horizontale toolbar met envelope mode → vervangen door correcte tool indicator overlay.
- Envelope punten "springen" weg van randen bij bepaalde zoom niveaus → zoom factor wordt niet meer toegepast op extreme waarden.

### Interne / Code Structuur
- Definitiestructuur voor horizontale knoppen (lijst met id/icon/callback) geïntroduceerd.
- Hulpfuncties voor knopbreedtes & rendering (CalcFullButtonWidth / DrawFullButton).
- ReverseSelectionWithinItem uitgebreid met glue pad + whole item detectie.

### Verwijderd
- Responsive icon-only / overflow layout (niet gewenst qua uitstraling).
- Overflow “⋯” popup en bijbehorende breedteberekening.

### Mogelijke vervolgstappen
- Opruimen ongebruikte functies (CalcIconButtonWidth e.d.) na verwijderen overflow variant.
- Instelbare GUI spacing parameter in Settings i.p.v. handmatige code-edit.
- Consistente tooltips per knop (nu beperkt).
- Optionele minimale fade-indicator bij extreem inzoomen.
- Versienummering starten (bijv. v0.10.0 als volgende stap) en taggen.

---
Dit document kan worden opgesplitst in release secties zodra formele versies/tagging worden ingevoerd.
