# Historia zmian / Changelog

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
