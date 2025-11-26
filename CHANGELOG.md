# Changelog

Alle belangrijke wijzigingen aan dit script pakket worden hieronder bijgehouden.

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
