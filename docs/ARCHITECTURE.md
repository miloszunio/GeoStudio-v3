# Architektura (v2)

`scripts/main.gd` składa scenę (UI, widok 3D, geometria modelu). Wydzielone moduły dostają referencję do głównej sceny
(`app`) i trzymają własny stan. Główna scena tworzy je w `_ready()` (`gpt`, `exporter`, `mapping`, `rig`, `place`, `parts_ui`, `projflow`, `atlasflow`, `roofed`, `chimneys`).

| moduł | klasa | za co odpowiada |
|---|---|---|
| `gpt_flow.gd` | `GptFlow` | okno promptu dla GPT, okno wklejania JSON, zastosowanie opisu (materiały, otwory), dane do eksportu (`describe`) |
| `export_flow.gd` | `ExportFlow` | eksport GLB + meta (`export_info`) |
| `mapping_flow.gd` | `MappingFlow` | okno edytora mapowania, wyprostowane zdjęcia (`rectified`) |
| `camera_rig.gd` | `CameraRig` | orbita, zoom, przesuwanie środkowym przyciskiem, widoki prostopadłe, pełny ekran |
| `place_search.gd` | `PlaceSearch` | wyszukiwarka miejsc i historia 30 wyszukiwań |
| `parts_ui.gd` | `PartsUi` | lista części budynku (wysokość ścian, dach) |
| `project_flow.gd` | `ProjectFlow` | folder projektu: otwieranie, zapis, geo.txt, render przy zamknięciu |
| `atlas_flow.gd` | `AtlasFlow` | źródło tekstury, biblioteka zdjęć, podgląd cięcia, normal mapy |
| `roof_flow.gd` + `roof_editor.gd` | `RoofFlow`, `RoofEditor` | okno kąta i okapu dachu (asymetria, wysunięcie) |
| `chimney_flow.gd` + `chimney_editor.gd` | `ChimneyFlow`, `ChimneyEditor` | kominy: dane (`model_chimneys`), siatka na dachu, okno z rzutem z góry i dwoma rzutami bocznymi |

Moduły bez stanu sceny (testowalne osobno): `gpt_prompt.gd`, `gpt_describe.gd` (kontrakt JSON od GPT, walidacja, tabela klas materiałów, dociąganie prostokątów),
`tag_sheet.gd` (import arkusza z kolorowymi ramkami-tagami), `sheet_layout.gd` (układ arkusza z wymiarów ścian: MaxRects, wspólne px/m, obraz-szablon), `model_meta.gd`, `model_exporter.gd`, `rectify.gd` (homografia), `face_store.gd` (korekty powierzchni z undo), `atlas_slicer.gd`, `texture_atlas.gd`.

UI: `settings_panel.gd` buduje panel boczny z opisu w `app_settings.gd`. Sekcje z listy `AppSettings.ADVANCED_SECTIONS` trafiają do okna
„Zaawansowane…” danej karty (Zapisz / Anuluj). `face_panel.gd` + `face_preview.gd` + `uv_editor.gd` to panel korekt, podgląd ściany i edytor na całe okno.

Testy: `tools/selftest.gd` (bez okna), `tools/e2e_mock.gd` + `tools/mock_geoportal.py` (z xvfb), skrypty `*_shot.gd` robią zrzuty ekranu.
