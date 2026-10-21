# Historia zmian / Changelog

## 3.0.7 (2026-10-21)

**PL**
- Poprawka awarii zaraz po starcie na Windowsie (Forward+) zgłoszonej przy 3.0.6. Nie udało się jej odtworzyć (środowisko testowe nie ma Vulkana), więc usunięto najbardziej podejrzany element, czyli SSAO i poświatę włączane przy otoczeniu tylko w Forward+.
- Zabezpieczenie: przed budową otoczenia program zapisuje znacznik, a po 12 s pracy go kasuje. Jeśli poprzedni start zakończył się awarią, otoczenie startuje wyłączone (z komunikatem) i włączysz je w Widok → Otoczenie. Jeśli awaria wróci, prześlij `godot.log` z `%APPDATA%\Godot\app_userdata\Photo-to-3D Studio v3\logs\`.

**EN**
- Fix for the crash right after start on Windows (Forward+) reported with 3.0.6. It could not be reproduced (the test environment has no Vulkan), so the most suspicious part was removed: the SSAO and glow that were switched on with the surroundings, Forward+ only.
- Safety net: before building the surroundings the program writes a marker and deletes it after 12 s of running. If the previous start ended in a crash, the surroundings start switched off (with a message) and can be turned on in View → Otoczenie. If the crash returns, send `godot.log` from `%APPDATA%\Godot\app_userdata\Photo-to-3D Studio v3\logs\`.

## 3.0.6 (2026-10-21)

**PL**
- **Otoczenie w podglądzie** (Widok → „Otoczenie (tylko podgląd)”, domyślnie włączone): łąka z shaderem (ziemia, trawa, plamy suchej trawy), kawałek drogi z krawężnikiem, chodnikiem i żwirowym poboczem, ok. 50 000 źdźbeł trawy i kwiaty kołyszące się na wietrze, dęby, brzozy, świerki i krzewy z tysięcy kart liści (liście ciemniejsze w głębi korony, pnie i gałęzie), las na horyzoncie, płynące chmury, niebo, mgiełka, pory roku (lato, wiosna, jesień). Wiatr z ustawień „Efekty” rusza roślinami, a razem z nim dymem i deszczem. Ustawienia: pora roku, liczba drzew, gęstość trawy, chmury, mgiełka, droga (strona i odległość), ziarno losowania. Kierunek startowej kamery zostaje wolny od drzew.
- Nic z tego nie trafia do eksportu (eksport czyta tylko węzeł Building). Włączone otoczenie chowa zwykłe podłoże i siatkę. Nowe pliki: `scenery.gd`, `scenery_trees.gd`, `scenery_grass.gd`, `scenery_shaders.gd`, `tools/scenery_shot.gd`. Testy: 382 sprawdzenia.
- Nie sprawdzono w Forward+ (testy w trybie Compatibility); przy słabszym GPU zmniejsz trawę i drzewa.

**EN**
- **Surroundings in the preview** (View → "Otoczenie (tylko podgląd)", on by default): a meadow shader (earth, grass, dry patches), a piece of road with kerb, pavement and gravel verge, about 50,000 grass blades and flowers swaying in the wind, oaks, birches, spruces and bushes built from thousands of leaf cards (darker inside the crown, trunks and branches), a forest line on the horizon, drifting clouds, a tuned sky, haze, seasons (summer, spring, autumn). The wind from the "Efekty" settings moves the plants together with smoke and rain. Settings: season, tree count, grass density, clouds, haze, road (side and distance), random seed. The default camera direction is kept free of trees.
- None of it goes into an export (exports read the Building node only). With the surroundings on, the plain ground and the grid are hidden. New files: `scenery.gd`, `scenery_trees.gd`, `scenery_grass.gd`, `scenery_shaders.gd`, `tools/scenery_shot.gd`. Tests: 382 checks.
- Not tested in Forward+ (tests ran in Compatibility); on a weaker GPU lower the grass and tree settings.

## 3.0.5 (2026-10-21)

**PL**
- **Emitery – zarządzanie**: lista emiterów w karcie Emitery (zaznacz, ⧉ powiel, ✕ usuń); parametry zaznaczonego emitera pod listą. W widoku 3D każdy emiter ma delikatną, klikalną kulę; zaznaczony świeci na złoto i dostaje **strzałki przesuwania** (osie X/Y/Z, światło powierzchniowe: 2 osie). Strzałki mają pierwszeństwo przed kulami. Przeciągnięcie emitera przypiętego do komina odpina go od komina. Puste kliknięcie odznacza. Nowe pliki: `emitter_pick.gd`, `emitter_gizmo.gd`, `emitter_pick_sphere.gd`.
- **Komin – lustro**: w edytorze kominów dwa pola „Lustro poziome/pionowe”: powtarzany fragment ściany jest na przemian odbijany (A A′ A A′ zamiast A A A A), więc krawędzie łączą się bez szwu. Pasek podglądu kafelków; prawa kolumna edytora przewija się.
- Testy: 378 sprawdzeń; nowy `tools/emitter_pick_test.gd`.

**EN**
- **Emitter management**: an emitter list in the Emitters tab (select, ⧉ duplicate, ✕ delete) with the selected emitter's properties below. In the 3D view each emitter has a faint clickable ball; the selected one glows gold and gets **move arrows** (X/Y/Z; surface light: 2 axes). Arrows take priority over the balls. Dragging an emitter bound to a chimney detaches it. A click on empty space deselects. New files: `emitter_pick.gd`, `emitter_gizmo.gd`, `emitter_pick_sphere.gd`.
- **Chimney mirror**: two "mirror horizontal/vertical" options in the chimney editor: the repeated wall fragment alternates with its flipped copy (A A′ A A′ instead of A A A A), so edges meet seamlessly. Tile preview strip; the editor's right column scrolls.
- Tests: 378 checks; new `tools/emitter_pick_test.gd`.

## 3.0.4 (2026-10-21)

**PL**
- **Silnik efektów** (`fx_particles.gd`, `fx_tex.gd`): cząstki na GPU (Godot `GPUParticles3D`) z proceduralnymi arkuszami sprite'ów (kłęby dymu, płomień, smugi, kropla, iskra, poświata, kręgi), krzywymi koloru i rozmiaru w czasie życia, turbulencją, wiatrem, obrotem, miękkimi krawędziami i **warstwami**: ogień = płomień + poświata + iskry + żar + dym + migoczące światło; dym = kłęby + smugi; woda = strumień + mgiełka + bryzgi; para.
- **Deszcz** (nowy emiter „Pogoda – deszcz”): smugi spadają na ziemię i na połacie dachu, rozbryzgi na dachu, **strużki spływające po dachu** wzdłuż linii największego spadku, krople i strumień z okapów, kręgi i bryzgi na ziemi. Wszystko z geometrii dachu, więc działa dla każdego dachu.
- Wiatr sceny (Widok → Efekty): prędkość i kierunek znoszą dym, iskry i deszcz w podglądzie.
- Metadane: `particle_fx` przy każdym emiterze cząstek (warstwy, tekstura, mieszanie, krzywe, turbulencja, wiatr, światło) i `weather_source` + `particle_fx` typu `rain` (powierzchnie dachu, okapy, spływ, krople, kręgi); arkusze sprite'ów zapisują się jako `fx/*.png` obok modelu. Rozszerzenie GeoStudio, propozycja dla profilu Reloaded (MODEL_META.md 4.3a, 4.3b).
- Karta Emitery: tekstura, mieszanie, turbulencja, wiatr, obrót, światło, lista warstw (tempo, usuwanie), przycisk „↺ wzór”; parametry deszczu.
- Presety dymu, ognia, wody i pary przestrojone (większe, gęstsze). Testy: 368 sprawdzeń; nowe `tools/fx_shot.gd`, `tools/fx_tex_test.gd`.
- Nie sprawdzono w MaSzyna Reloaded; wygląd oceniany tylko w podglądzie edytora.

**EN**
- **Effects engine** (`fx_particles.gd`, `fx_tex.gd`): GPU particles (Godot `GPUParticles3D`) with procedural sprite sheets (smoke puffs, flame, wisps, drop, spark, glow, ripple rings), colour and scale over life, turbulence, wind, spin, soft edges and **layers**: fire = flame + glow + sparks + embers + smoke + flickering light; smoke = puffs + wisps; water = jet + mist + spray; steam.
- **Rain** (new emitter "Pogoda – deszcz"): streaks fall onto the ground and the roof facets, splashes on the roof, **rivulets running down the roof** along the line of steepest descent, drips and gutter streams from the eaves, ripples and spray on the ground. All derived from the roof geometry, so it works for any roof.
- Scene wind (Widok → Efekty): speed and direction blow smoke, sparks and rain in the preview.
- Metadata: `particle_fx` on every particle emitter (layers, texture, blend, curves, turbulence, wind, light) and `weather_source` + `particle_fx` of type `rain` (roof surfaces, eaves, runoff, drips, ripples); sprite sheets are written as `fx/*.png` next to the model. A GeoStudio extension, a proposal for the Reloaded profile (MODEL_META.md 4.3a, 4.3b).
- Emitters tab: texture, blend, turbulence, wind, spin, light, a layer list (rate, remove), a "↺ wzór" (reset to preset) button; rain parameters.
- Smoke, fire, water and steam presets retuned (bigger, denser). Tests: 368 checks; new `tools/fx_shot.gd`, `tools/fx_tex_test.gd`.
- Not verified in MaSzyna Reloaded; the look was judged only in the editor preview.

## 3.0.3 (2026-10-21)

**PL**
- **Eksport glTF/GLB zapisuje domyślnie profil z `MODEL_META.md`** (zgodny z MODEL_FORMAT 0.4.0 MaSzyna Reloaded): `asset.extras` (`model_format_version`, `osm`, `geo` z WGS84 i kierunkiem, `geostudio` z obrysem, dachem, kominami, powierzchniami, kanałami i autorstwem), `asset.copyright`, stabilne `semantic_id` na węzłach, warstwy świateł (`light_id`, `light_state`), `KHR_lights_punctual` z `light_control`, `smoke_source`, `audio_source`. Plik `.meta.json` obok modelu zostaje.
- Emitery: światło (powierzchnia, punkt, reflektor), **cząstki (dym, ogień, woda, para)**, dźwięk (dookólny, kierunkowy); kanały `budynek.*` w stylu `building.lights`; komin może być miejscem emisji.
- Opcje projektu: autor, licencja (SPDX), „dodaj stary układ metadanych (v1)” (domyślnie wyłączone).
- **Podgląd cząstek na żywo** w widoku 3D (dym, ogień, woda, para; CPUParticles3D z parametrami eksportu). MaSzyna Reloaded działa na Godocie, więc wygląd jest zbliżony do gry, ale nie identyczny.
- Testy: 350 sprawdzeń; nowe `tools/profile_export_test.gd`.

**EN**
- **glTF/GLB export now writes the `MODEL_META.md` profile by default** (compatible with MaSzyna Reloaded MODEL_FORMAT 0.4.0): `asset.extras` (`model_format_version`, `osm`, `geo` with WGS84 and heading, `geostudio` with footprint, roof, chimneys, surfaces, channels and credits), `asset.copyright`, stable node `semantic_id`s, light layers (`light_id`, `light_state`), `KHR_lights_punctual` with `light_control`, `smoke_source`, `audio_source`. The `.meta.json` sidecar stays.
- Emitters: light (surface, point, spot), **particles (smoke, fire, water, steam)**, audio (omni, directional); channels named like `building.lights`; a chimney can be the emission point.
- Project options: author, licence (SPDX), "add the old metadata layout (v1)" (off by default).
- **Live particle preview** in the 3D view (smoke, fire, water, steam; CPUParticles3D with the export's parameters). MaSzyna Reloaded runs on Godot, so the look is close to the game, but not identical.
- Tests: 350 checks; new `tools/profile_export_test.gd`.

## Docs (2026-10-21, po 3.0.2)

**PL** – `MODEL_META.md` przepisany jako profil generatora nad formatem modeli MaSzyna Reloaded (MODEL_FORMAT 0.4.0): mapowanie na ich pola, trzy rodziny emiterów (światło, cząstki, dźwięk), kanały, autorstwo, etapy wdrożenia i pytania do ich zespołu. Dotychczasowy opis (wersja 1, to co zapisuje eksporter) przeniesiony do `MODEL_META_V1.md`.
**EN** – `MODEL_META.md` rewritten as a generator profile on top of the MaSzyna Reloaded model format (MODEL_FORMAT 0.4.0): mapping to their fields, three emitter families (light, particles, audio), channels, credits, rollout phases and questions for their team. The previous description (version 1, what the exporter writes) moved to `MODEL_META_V1.md`.

## 3.0.2 (2026-10-21)

**PL**
- Okno „Projekt” na starcie ma przycisk **Zamknij program** (wcześniej programu nie dało się zamknąć bez wskazania folderu), a okno zapisu `.mgdot` nie blokuje już zamykania okna programu.
- Karta **Opcje** nazywa się teraz **Projekt** (sekcja „Zapis i pliki projektu”); pasek kart zawija się do drugiego rzędu.
- Nowa karta **Emitery** (przed kartą Projekt): dodawanie emiterów światła (powierzchnia, punkt, reflektor), dźwięku (dookólny, kierunkowy) i dymu, kanały sterowania, znaczniki w 3D, zapis w projekcie i w metadanych (`emitters`, `channels`; szkic v2).
- Testy: 342 sprawdzenia; nowe `tools/quit_dialog_test.gd`, `tools/emitters_shot.gd`.

**EN**
- The start-up "Projekt" window has a **Zamknij program** (close program) button (before, the program could not be closed without choosing a folder), and the `.mgdot` save dialog no longer blocks closing the main window.
- The **Opcje** tab is now **Projekt** (section "Zapis i pliki projektu"); the tab strip wraps to a second row.
- New **Emitery** tab (before Projekt): add light (surface, point, spot), audio (omni, directional) and smoke emitters, control channels, 3D markers, saved in the project and in the metadata (`emitters`, `channels`; draft v2).
- Tests: 342 checks; new `tools/quit_dialog_test.gd`, `tools/emitters_shot.gd`.

## Docs-only (2026-10-20)

**PL** – dodano licencję MIT (`LICENSE`), zapis o przeznaczeniu dla MaSzyny / MaSzyna Reloaded oraz listę prac w toku (metadane, wycinanki pod elementy udające świecenie).
**EN** – added the MIT licence (`LICENSE`), a note that the tool targets MaSzyna / MaSzyna Reloaded, and the work-in-progress list (metadata, cut-outs for lighting-imitating elements).

## 3.0.1 (2026-10-20)

**PL**
- Edytor dachu **stosuje zmiany na bieżąco** (bez „GENERUJ DACH”); pole „Wysokość dachu” działa także na dachu narysowanym i własnym. Usunięty zdublowany przycisk.
- Nowe typy dachu: **kopertowy** i **własny** (rzut z góry, strzałka spadku na każdej krawędzi, ściany szczytowe, ścięcie szczytu).
- Przyciski ↺ mają stałe miejsce – panel nie skacze. Zdjęcie szczytu: dodatkowo S3/S4 jako zapas.
- Opcja **Eksport jako paczka ZIP** (GLB, glTF, T3D).

**EN**
- The roof editor **applies changes live** (no "GENERUJ DACH"); the roof height field also works on a drawn and a custom roof. Duplicate button removed.
- New roof types: **hip** and **custom** (top view, a slope arrow on every edge, gable walls, flat-top cap).
- ↺ buttons keep their slot – the panel no longer jumps. Gable picture: S3/S4 as a fallback.
- **Export as ZIP package** option (GLB, glTF, T3D).

## 3.0.0 (2026-10-19)

**PL**

- **Nowy przepływ z ChatGPT**: prompt dla 8 sektorów 2 × 4 (4096², wspólna skala px/m, KROK 0 – spis przed rysowaniem, zakaz pomijania elewacji), **bez JSON**. Przycisk „Wklej opis od GPT” i cała obsługa opisu otworów usunięte.
- **Import płótna sektorowego**: sektory → kody S1–S8, pomijanie jasnych ramek rysowanych przez GPT, przycinanie tła, puste sektory pomijane; starszy tryb z czerwonymi ramkami nadal działa. Edytor paneli.
- **Generator dachu** (zakładka Dach): profil rysowany na **prawdziwym zdjęciu szczytu w skali** (≤ 7 wierzchołków, mansarda, naczółki), pomiar okapu i kalenicy ze zdjęcia, GENERUJ DACH; ściany szczytowe i kominy podążają za profilem.
- **Wydajność wczytywania tekstury**: arkusz zapisywany jako JPG (było PNG, ~7 s), wynik zapamiętany (`tex_sheet_key`), tańsze wykrywanie sektorów przed szukaniem ramek. Wczytanie płótna 4096²: ok. 14 s → ok. 4,6 s, powtórne – bez analizy.
- **Krawędzie i wierzchołki jak „Edged Faces”**: grubość w pikselach, kolor, nieprzezroczystość, krawędzie zasłonięte bledsze, wierzchołki o stałej wielkości z obwódką i kolorem wg rodzaju.
- **Plik projektu `.mgdot`** (zip z manifestem, miniaturą i promptem), zapis atomowy, lista ostatnich plików z miniaturami, ochrona przed `../`, kontrola wersji formatu.
- **Eksport glTF** (`.gltf` + `.bin` + tekstury) i **eksport T3D dla MaSzyny** (LOD0/LOD1, TGA + MAT, `.inc`, nodebank, źródła dymu, `light_on00`).
- Metadane: `part_roofs` (profil i walmy dachu). Usunięte: `surfaces`, `openings`, `described_building`.
- Dokumentacja przepisana w całości, po polsku i angielsku. Selftest: 326 sprawdzeń.

**EN**

- **New ChatGPT flow**: a prompt for 8 sectors in 2 × 4 (4096², one px/m scale, STEP 0 inventory before drawing, a ban on skipping elevations), **no JSON**. The "paste GPT description" button and all opening-description handling were removed.
- **Sector canvas import**: sectors → codes S1–S8, skipping the light frames GPT draws, background trimming, empty sectors skipped; the older red-frame mode still works. Panel editor.
- **Roof generator** (Dach tab): the profile is drawn on the **real gable picture at true scale** (≤ 7 vertices, mansard, hips), eaves and apex measured from the picture, GENERUJ DACH; gable walls and chimneys follow the profile.
- **Texture load performance**: the sheet is written as JPG (was PNG, ~7 s), the result is remembered (`tex_sheet_key`), cheaper sector detection before looking for frames. Loading a 4096² canvas: about 14 s → about 4.6 s, a reload skips the analysis.
- **Edges and vertices like "Edged Faces"**: thickness in pixels, colour, opacity, hidden edges paler, constant-size vertices with an outline and a colour by kind.
- **Project file `.mgdot`** (zip with manifest, thumbnail and prompt), atomic write, recent-files list with thumbnails, `../` protection, format version check.
- **glTF export** (`.gltf` + `.bin` + textures) and **T3D export for MaSzyna** (LOD0/LOD1, TGA + MAT, `.inc`, nodebank, smoke sources, `light_on00`).
- Metadata: `part_roofs` (roof profile and hips). Removed: `surfaces`, `openings`, `described_building`.
- Documentation rewritten completely, in Polish and English. Selftest: 326 checks.

## 2.x

Studio v2 is frozen in its own folder: Geoportal footprints, walls + roof solid, colour-tag sheets, chimneys, UV editor, GLB export with metadata.
