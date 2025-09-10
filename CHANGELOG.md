# Changelog

Alle belangrijke wijzigingen aan dit script pakket worden hieronder bijgehouden.

## Ongeversioneerd (werk in uitvoering)

### Toegevoegd
- Horizontale toolbar (boven de waveform) als alternatief voor de verticale sidebar; toggle via View menu, Settings popup en pijltje (collapse).
- Persistente instelling `sidebar_layout` (vertical/horizontal).
- Fallback hit-test voor horizontale collapse toggle (zorgt dat opnieuw uitklappen altijd werkt).
- Automatische selectie van het linker (originele) item na Split.
- Optionele auto-glue voor Reverse Selection via nieuwe setting `reverse_sel_glue_after` (Behavior menu: "Reverse selection: glue back to single item").
- Behavior menu optie voor reverse glue; opgeslagen in ExtState.
- Negatieve icon/tekst spacing ondersteuning (voor zeer compacte horizontal buttons).

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
- Fix voor syntaxfout in info-knop callback (verkeerde multiple assignment).
- Dubbele weergave navigatiepijlen opgelost (icon + text → alleen icon).
- Collapse toggle werkte niet om uit te klappen → fallback hittest toegevoegd.
- Goto/label constructie verwijderd (Lua error) vervangen door conditionele flow.
- Split deselecteerde alle items → nu blijft linker deel geselecteerd.

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
