# Architektura / Architecture

PL na górze, EN poniżej. / Polish first, English below.

---

# PL

`scripts/main.gd` składa scenę (UI, widok 3D, geometria modelu). Wydzielone moduły („flows”) dostają referencję do głównej sceny (`app`) i trzymają własny stan;
główna scena tworzy je w `_ready()`. Ustawienia są opisane jednym schematem (`app_settings.gd`), z którego `settings_panel.gd` buduje panel boczny.

| moduł | klasa | za co odpowiada |
|---|---|---|
| `gpt_flow.gd`, `gpt_prompt.gd` | `GptFlow`, `GptPrompt` | okno promptu dla ChatGPT; generator promptu z wymiarów budynku (bez JSON) |
| `atlas_flow.gd` | `AtlasFlow` | źródło tekstury, `_normalize_panels` (cache arkusza), biblioteka zdjęć, podgląd cięcia |
| `panel_frames.gd` | `PanelFrames` | wykrywanie czerwonych ramek na płótnie |
| `panel_sheet.gd` | `PanelSheet` | płótno sektorowe (`grid_panels`, ramki jasne, przycinanie tła), kody S1–S8, układ arkusza (`build`), JSON paneli |
| `panel_editor.gd` | `PanelEditor` | ręczne przypisanie paneli |
| `sheet_layout.gd` | `SheetLayout` | układ arkusza w skali rzeczywistej |
| `texture_atlas.gd`, `atlas_slicer.gd` | `TextureAtlas`, `AtlasSlicer` | regiony tekstury, automatyczne cięcie |
| `roof_gen.gd`, `roof_gen_editor.gd` | `RoofGen`, `RoofGenEditor` | profil dachu → płaszczyzny; okno rysowania na zdjęciu szczytu, `picture_profile` mierzy zdjęcie |
| `roof_flow.gd`, `roof_editor.gd` | `RoofFlow`, `RoofEditor` | okna dachu (generator i dawny „prosty dach”) |
| `chimney_flow.gd`, `chimney_editor.gd` | `ChimneyFlow`, `ChimneyEditor` | kominy: dane (`model_chimneys`), siatka, okno z trzema rzutami |
| `mapping_flow.gd`, `uv_editor.gd`, `face_panel.gd`, `face_preview.gd`, `face_store.gd`, `rectify.gd` | | korekta powierzchni: panel, edytor UV, prostowanie zdjęcia (homografia), magazyn korekt z undo |
| `edge_overlay.gd` | `EdgeOverlay` | nakładka krawędzi i wierzchołków („Edged Faces”): geometria w przestrzeni ekranu, dwa przebiegi (widoczne / zasłonięte) |
| `export_flow.gd`, `model_exporter.gd`, `model_meta.gd` | | eksport GLB / glTF i metadane |
| `t3d_exporter.gd` | `T3dExporter` | eksport T3D dla MaSzyny: submodele, LOD-y, TGA, `.mat`, `.inc`, nodebank |
| `mgdot.gd` | `MgDot` | format `.mgdot`: pakowanie (atomowe), rozpakowanie, manifest, kontrola wersji |
| `project_flow.gd`, `project_store.gd`, `project_dialog.gd` | | folder projektu, zapis/odczyt stanu, okno startowe, zapis i otwieranie `.mgdot` |
| `geoportal_client.gd`, `geo_cache.gd`, `place_search.gd`, `place_history.gd` | | Geoportal (WMS/WFS, EPSG:2180), cache, wyszukiwarka miejsc |
| `camera_rig.gd`, `parts_ui.gd`, `image_picker.gd`, `settings_panel.gd` | | kamera, lista części, przeglądarka obrazów, panel boczny |

Ustawienia ukryte (część stanu projektu): `tex_panels`, `tex_sheet_layout`, `tex_sheet_key` (klucz cache arkusza), `tex_px_per_m`, `model_roof_gen`, `model_chimneys`,
`ui_recent_projects`, `ui_recent_mgdot` (te z prefiksem `ui_` nie wchodzą do pliku projektu).

Wątki: analiza płótna (wykrywanie, układanie, zapis JPG) wykonuje się w głównym wątku, ale jest **pomijana przy powtórnym wczytaniu** dzięki kluczowi `tex_sheet_key`
(plik, panele, wymiary). Największy koszt – kodowanie PNG 4096² (~7 s) – zastąpiono zapisem JPG (~0,3 s).

Testy: `tools/selftest.gd` (bez okna, 316 sprawdzeń), `tools/e2e_mock.gd` + `tools/mock_geoportal.py`, skrypty `tools/*_shot.gd` (zrzuty ekranu), `tools/mgdot_flow_test.gd` (zapis i odczyt `.mgdot` przez prawdziwy przepływ).

---

# EN

`scripts/main.gd` assembles the scene (UI, 3D view, model geometry). Separate modules ("flows") get a reference to the main scene (`app`) and keep their own state;
the main scene creates them in `_ready()`. All settings are described by one schema (`app_settings.gd`) from which `settings_panel.gd` builds the side panel.

| module | class | responsibility |
|---|---|---|
| `gpt_flow.gd`, `gpt_prompt.gd` | `GptFlow`, `GptPrompt` | the ChatGPT prompt window; prompt generator from the building dimensions (no JSON) |
| `atlas_flow.gd` | `AtlasFlow` | texture source, `_normalize_panels` (sheet cache), photo library, slice preview |
| `panel_frames.gd` | `PanelFrames` | detection of red frames on the canvas |
| `panel_sheet.gd` | `PanelSheet` | sector canvas (`grid_panels`, light frames, background trimming), codes S1–S8, sheet layout (`build`), panel JSON |
| `panel_editor.gd` | `PanelEditor` | manual panel assignment |
| `sheet_layout.gd` | `SheetLayout` | real-scale sheet layout |
| `texture_atlas.gd`, `atlas_slicer.gd` | `TextureAtlas`, `AtlasSlicer` | texture regions, automatic slicing |
| `roof_gen.gd`, `roof_gen_editor.gd` | `RoofGen`, `RoofGenEditor` | roof profile → planes; the window for drawing on the gable picture, `picture_profile` measures the picture |
| `roof_flow.gd`, `roof_editor.gd` | `RoofFlow`, `RoofEditor` | roof windows (the generator and the old "simple roof") |
| `chimney_flow.gd`, `chimney_editor.gd` | `ChimneyFlow`, `ChimneyEditor` | chimneys: data (`model_chimneys`), mesh, the window with three views |
| `mapping_flow.gd`, `uv_editor.gd`, `face_panel.gd`, `face_preview.gd`, `face_store.gd`, `rectify.gd` | | surface editing: panel, UV editor, photo rectification (homography), edit store with undo |
| `edge_overlay.gd` | `EdgeOverlay` | edge and vertex overlay ("Edged Faces"): screen-space geometry, two passes (visible / hidden) |
| `export_flow.gd`, `model_exporter.gd`, `model_meta.gd` | | GLB / glTF export and metadata |
| `t3d_exporter.gd` | `T3dExporter` | T3D export for MaSzyna: submodels, LODs, TGA, `.mat`, `.inc`, nodebank |
| `mgdot.gd` | `MgDot` | the `.mgdot` format: (atomic) packing, unpacking, manifest, version check |
| `project_flow.gd`, `project_store.gd`, `project_dialog.gd` | | project folder, state save/load, start window, saving and opening `.mgdot` |
| `geoportal_client.gd`, `geo_cache.gd`, `place_search.gd`, `place_history.gd` | | Geoportal (WMS/WFS, EPSG:2180), cache, place search |
| `camera_rig.gd`, `parts_ui.gd`, `image_picker.gd`, `settings_panel.gd` | | camera, parts list, image picker, side panel |

Hidden settings (part of the project state): `tex_panels`, `tex_sheet_layout`, `tex_sheet_key` (sheet cache key), `tex_px_per_m`, `model_roof_gen`, `model_chimneys`,
`ui_recent_projects`, `ui_recent_mgdot` (those with the `ui_` prefix are not put into the project file).

Threading: the canvas analysis (detection, layout, JPG write) runs on the main thread but is **skipped on reload** thanks to the `tex_sheet_key` key
(file, panels, dimensions). The biggest cost – encoding a 4096² PNG (~7 s) – was replaced by writing a JPG (~0.3 s).

Tests: `tools/selftest.gd` (windowless, 316 checks), `tools/e2e_mock.gd` + `tools/mock_geoportal.py`, `tools/*_shot.gd` screenshot scripts, `tools/mgdot_flow_test.gd` (saving and reading `.mgdot` through the real flow).
