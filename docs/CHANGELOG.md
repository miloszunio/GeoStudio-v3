# Historia zmian / Changelog

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
