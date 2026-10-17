# Photo-to-3D Studio (prototype)

**Pełna dokumentacja dla testerów: [docs/DOKUMENTACJA.md](docs/DOKUMENTACJA.md).**

Pick a building on the **Geoportal.gov.pl** map → get its footprint with dimensions → build a 3D
model → texture it automatically from a **texture atlas** (included: abandoned station Wroniawy).

Made for **Godot 4.6** (works with 4.3+; project features say 4.6 / Forward Plus).

## Project folder

At start the app asks for a **project folder** (one per building or group); nothing can be built before it
is chosen. The folder holds everything about the model, relative paths only, so it can be moved or zipped:

```
<project>/
  project.json     state: outlines (parts), settings snapshot, texture, map position, camera
  geo.txt          readable Geoportal data: ids/attributes, outlines (E N, EPSG:2180), services, time
  geo.json         the same, machine-readable (+ bounds of the ortho crop)
  geo/ortho.png    orthophoto crop around the building (reference for texturing)
  texture/         copy of the chosen texture + <name>.atlas.json (the cut into regions)
  renders/         lastView_<timestamp>.png, written when the app closes (newest N kept, default 3)
  exports/         reserved for glb / t3d
  project.log      timestamped events
```

Opening a project restores the model, the settings, the texture and the map position. *Projekt…* (top of the
sidebar) switches projects; *Opcje → Projekt* has *Zapisz render teraz* and *Otwórz folder projektu*.

## Open it
1. Install Godot 4.x (standard build, not .NET): <https://godotengine.org/download>
2. Godot Project Manager → **Import** → choose `project.godot` in this folder → **Import & Edit**.
3. Press **F5**. (The first open takes a few seconds while Godot imports the PNG.)

The app starts with an **empty scene** (no model, no texture). Step 3 (Tekstury) stays locked until a model has been built.
No GPU with Vulkan? Project Settings → Rendering → Renderer → *Compatibility*, or run
`godot --rendering-method gl_compatibility`.

## Use it
1. **Mapa Geoportal** tab: type `lat, lon` (e.g. `52.2297, 21.0122`) → *Przejdź do współrzędnych*.
   Drag = pan, wheel = zoom. Footprints appear when zoomed in to ≤ 2 m/px.
2. Click a building → size, area and floors (if EGiB has them) show in the sidebar.
   EGiB often cuts one building into several polygons: **Ctrl/Shift + click** adds or removes a
   polygon, **+ Sąsiednie części** adds every touching polygon automatically.
3. **Zbuduj model 3D z zaznaczenia** (the biggest polygon is the main body, the rest are annexes:
   lower walls, shed roof leaning on the main body, shared walls removed, small gaps between
   polygons healed – tolerance in *Budynek → Zaawansowane*). The **Części budynku** list on the Budynek tab sets wall
   height, roof type and roof height per part (↺ = back to automatic, ✕ = drop the part).
   **Zbuduj model 3D z wybranego budynku** → the app switches to **Model 3D**.
   Drag = orbit, wheel = zoom.
4. The left sidebar follows the order of work – **1 Miejsce → 2 Budynek → 3 Tekstury → 4 Widok**, plus
   **⚙ Opcje** (font size, save/reset, Geoportal addresses). The tab strip is a single row; a finished
   step shows ✓. Every tab starts with a heading and one sentence saying what to do now, shows the
   essentials first (always open) and keeps advanced settings in collapsed sections (one open at a time).
   The **← / →** bar under the sidebar moves between steps. A value changed from its default gets an
   orange **↺** next to it (click = restore); each section also has *Przywróć domyślne*. The search box
   filters settings across all tabs. Step 1 shows the map, the other steps the 3D view. Settings are saved
   automatically (`user://photo_to_3d_settings.json`).
   - **Texture picker**: *Wybierz z podglądem…* (Tekstury → Źródło) opens its own window with thumbnails of
     the folder, a big preview and the image size; double click on a folder enters it, *Plik spoza listy…* /
     *Folder…* open the system dialogs.
   - **Roof pitch from the texture**: when the gable picture shows the roof outline on a plain background,
     the roof height is measured from it (*Kąt dachu z tekstury*; *Dopasuj wysokość dachu do tekstury* repeats
     it after a texture change; moving the height slider by hand switches the automatic pitch off).
     Empty background margins left and right of a cut-out elevation are trimmed, so they no longer show
     up as dark strips on the walls.
   - **2 Budynek** – wall/roof height, floor height, gable/flat roof, ridge direction, **roof overhang** (okap) and roof thickness – the roof is its own solid (top, underside, rim) that sticks out past the walls.
   - **3 Tekstury** – starts with **no texture**. *Źródło tekstury*: point at an image; a sheet with many panels on a plain background (elevations, roof, doors, windows, pipes…) is **cut automatically** into regions with guessed roles (long wall / gable / roof / door / window / chimney / pipe …), the cut is saved next to the image as `<name>.atlas.json` (edit it by hand if needed, it is reused on the next load; *Przeanalizuj obraz ponownie* redoes it), a plain photo stays one texture. *Podgląd cięcia* shows every region with its name. Changing the texture resets all per-wall choices and refills the lists. Samples to try: `textures/samples/*.png` and `textures/atlas_wroniawy.png`. **photo library**: every photo (PNG/JPG/WebP) in the library folder becomes its own texture (role guessed from the file/sub-folder name: dach/roof, szczyt/gable, drzwi, okno, otherwise facade); *Dodaj zdjęcia do biblioteki…* imports files; drop-downs show thumbnails; *Jedna tekstura na wszystkie ściany*, *Losuj tekstury*; *Eksportuj mapy normalnych* writes albedo + normal PNGs. Also: atlas file, per-wall region (long wall A/B, gable A/B, roof), variant, tile size; roof texture tiles in the picture's own proportions (toggle repeat / rotate 90°). **Relief**: normal map (optionally parallax) generated from the photo's brightness – low-frequency shading is removed, so joints, cracks, window frames and tiles stand out; strength per walls / roof, feature size, smoothing, invert.
   - **Widok 3D** – layers, ground/grid, light and background, camera.
   - **Usługi Geoportalu** – URLs, layer and feature-type names, **Testuj usługi**.
   - **Źródło: GeoJSON** – import your own footprint (`properties.wall_height` / `roof_height` optional).

## Project layout
```
project.godot, main.tscn, icon.svg
scripts/app_settings.gd     all settings in one schema (sidebar, saving, reset are generated from it)
scripts/settings_panel.gd   builds the sidebar from the schema
scripts/main.gd             map, model generation, texturing, camera
scripts/geoportal_client.gd WMS orthophoto + WFS (EGiB buildings) client, GML parser, EPSG:2180 maths
scripts/texture_atlas.gd    slices an atlas PNG into named regions using a JSON description
textures/atlas_wroniawy.*   the atlas + region description (edit rect values if edges need nudging)
samples/                    station demo + L-shaped GeoJSON
tools/                      headless tests, screenshot tool, mock Geoportal server
```

## Your own atlas
Copy `textures/atlas_wroniawy.json`, point `image` at your PNG and list regions:
`"name": { "role": "facade_long|facade_gable|roof|door|window|…", "rect": [x, y, w, h] }`.
Roles `facade_long`, `facade_gable` and `roof` are used for texturing; the rest are kept for the
door/window placement that is not implemented yet. For facades, `rect` should cover the wall only
(no roof, no ground) so that the texture maps 1:1 onto the model's wall.

## Tests (no internet needed)
```
godot --headless --path . --import                                   # once
godot --headless --path . --script res://tools/selftest.gd           # 265 checks, exit code 0 = OK
python3 tools/mock_geoportal.py &                                    # fake WMS/WFS on :8765
xvfb-run -a godot --path . --rendering-method gl_compatibility --script res://tools/e2e_mock.gd
```

## Known limits
- The Geoportal endpoints and feature-type names come from GUGiK documentation but were **not
  tested against the live service** (the authoring environment had no access). If the map stays
  empty, open *Usługi Geoportalu → Testuj usługi*, then fix the layer / type names there.
  The WFS client tries both axis orders for EPSG:2180 and detects the right one automatically.
- EGiB gives footprint and (sometimes) floors only, so the roof is an approximate gable/flat roof,
  not LoD2. Geoportal's 3D building models (CityGML, `measuredHeight`) would give real heights.
- Doors, windows, drainpipes and chimneys of the atlas are not placed on the model yet.
- Map coordinates are 32-bit floats inside Godot's `Vector2` (about 6 cm resolution at EPSG:2180
  magnitudes) – fine for building footprints.
- Data: © GUGiK / Geoportal.gov.pl – check the service terms before publishing results.

## Cache Geoportalu

Ortofotomapa jest pobierana jako kafelki 512 px na stałej siatce (poziomy 0,1·2^k m/px, max ~48 kafelków na widok),
obrysy budynków (EGiB) jako komórki 400 m. Wszystko ląduje w `user://geo_cache/` i jest współdzielone przez wszystkie
projekty, więc przewijanie mapy i powrót w znane miejsce nie generują zapytań. Zapytania idą przez kolejkę
(domyślnie 2 naraz, 150 ms odstępu, ponawianie przy 429/503 z uwzględnieniem `Retry-After`). Wpisy starsze niż TTL są
odświeżane, a gdy serwer nie odpowiada – używane jako kopia zapasowa. Ustawienia: Opcje → „Geoportal: cache i limity
zapytań” (ważność, rozmiar, równoległość, odstęp, przycisk „Wyczyść cache”).

## Teksturowanie budynków wielobryłowych

Cały budynek (korpus + przybudówki) używa jednego zestawu tekstur: korpus wg ról (długa/szczytowa A/B, dach), przybudówki
(dach pulpitowy) biorą zdjęcia „długich” ścian i ten sam dach, w tej samej skali co korpus (niższa przybudówka pokazuje dolną
część zdjęcia zamiast ściśniętej kopii całości).

## Szukanie miejsc i prompt dla GPT

- **Szukaj miejsca** (krok 1): wpisz miejscowość/adres i Enter; wyniki z Nominatim (adres usługi w Opcje → Połączenie). Kliknięcie
  przenosi mapę i zapisuje miejsce w historii (30 ostatnich, bez duplikatów); pusty Enter pokazuje historię.
- **Generuj prompt dla GPT** (krok 3, sekcja „0. Przygotuj arkusz”): tekst zadania dla ChatGPT z szablonem 4096×4096
  (8 sektorów 2048×1024: S1/S2 ściany długie, S3/S4 szczyty, S5 dach, S6–S8 dobudówki lub puste), wymiarami ścian
  z ewidencji i zasadami (bez perspektywy, jednolite tło, bez nieba/ludzi). Zapisuje się też w `texture/prompt_gpt.txt`.

## Szablon arkusza (4096 × 4096, sektory S1–S8)

Arkusz kwadratowy z panelami leżącymi w sektorach 2 × 4 (po 2048 × 1024 px przy 4096) jest rozpoznawany automatycznie
(Tekstury → Cięcie arkusza → Tryb: „Automatycznie” lub „Szablon 4096”). Regiony dostają nazwy i role z pozycji:
S1, S2 – ściany długie (A, B) · S3, S4 – szczyty (A, B) · S5 – dach · S6–S8 – ściany dobudówek (bez nich dobudówki
noszą zdjęcia ścian długich). Pusty sektor jest pomijany.

**Skala arkusza (px/m)** (Tekstury → Źródło): informacja dla promptu, metadanych i kafelkowania dachu; ściany zawsze dostają cały panel na całą ścianę. „Generuj prompt dla GPT” ustawia skalę sam –
największą całkowitą liczbę px/m, przy której każdy element mieści się w swoim sektorze – i wpisuje ją do promptu wraz z
rozmiarami elementów w pikselach.

## Korekty powierzchni (klik w scenie 3D)

W zakładce **Model 3D** kliknięcie dowolnej ściany lub połaci dachu (bez przeciągania) zaznacza ją (żółty obrys + błękitna
nakładka) i otwiera panel po prawej. Wszystko działa na żywo, zmiany są w projekcie (`project.json`, pole `faces`).
`Esc` albo klik w puste miejsce odznacza; `Ctrl+Z` / `Ctrl+Y` cofają i ponawiają.

- **Mapowanie**: przesunięcie lewo/prawo i góra/dół (m), skala szerokości i wysokości osobno (lub razem), obrót, odbicie.
  Przyciski ◀ ▶ przesuwają o stały krok, z Shiftem 10× więcej.
- **Kawałek**: inne zdjęcie z arkusza dla tej powierzchni albo wycięty z niego kawałek (utnij z każdej strony), który
  powiela się na całej powierzchni (kawałek to osobna mała tekstura, więc powtarza się bez „przeciekania” sąsiadów).
- **Materiał**: kolor (mnożony ze zdjęciem), chropowatość, połysk (specular), metaliczność, siła reliefu (normal).
- **Bryła**: podnoszenie i opuszczanie okapu razem z dachem, zmiana samej kalenicy, przesunięcie okapu przy stałej kalenicy
  (krok 1 dm, Shift = 5 dm).

Identyfikatory: `p<bryła>:w<krawędź>` (ściana), `p<bryła>:roofA|roofB` (połać). Przy zbudowaniu innego budynku korekty
są zerowane, bo należą do konkretnego obrysu.


## Eksport modelu (glTF / GLB)

Sidebar → *Widok* → **Eksport modelu (glTF)**: `Eksportuj model do GLB` zapisuje `exports/<projekt>.glb`
(Y w górę, metry) oraz `<projekt>.meta.json`. Siatka niesie tylko wizualizację; opis (typ, piętra, wysokość, dach,
położenie w EPSG:2180, części świecące) jest w `extras.meta` węzłów. Kontrakt: [docs/MODEL_META.md](docs/MODEL_META.md) (wersja robocza).
Powierzchnię można oznaczyć jako świecącą w panelu korekt (zakładka *Materiał*). Panel pokazuje też podgląd:
które miejsce zdjęcia leży na wybranej ścianie. T3D/E3D powstają z GLB w osobnym potoku.

## Opis od GPT (materiały, okna, drzwi)

„Generuj prompt dla GPT” daje pełny prompt: arkusz tekstur (4096², sektory S1–S8, wspólna skala) **oraz** drugą część odpowiedzi — JSON
(`geo3d_describe_v1`) z klasą materiału, stanem i kolorem każdego sektora oraz oknami/drzwiami (`rect` w ułamkach obrazu ściany).
Odpowiedź wkleja się przyciskiem „Wklej opis od GPT (JSON)…” (karta Tekstury). Program waliduje JSON (nieznane klasy → `other`,
zepsute elementy są pomijane z uwagą), ustawia chropowatość/metaliczność/połysk powierzchni z własnej tabeli klas, dociąga prostokąty
okien do krawędzi na obrazie i zapisuje wszystko w projekcie oraz w metadanych eksportu (`surfaces`, `openings`). Okna widać jako
niebieskie ramki (pomarańczowe = świecące) w podglądzie panelu korekt.

## Widok 3D

Lewy przycisk: obrót, kółko: zoom, **środkowy przycisk (rolka) przytrzymany: przesuwanie sceny**. Przyciski w prawym dolnym rogu:
Góra / Przód / Tył / Lewo / Prawo (widok prostopadły, rzut ortogonalny) i „3D” (powrót do perspektywy). Okno startuje na pełnym
ekranie (opcja „Start na pełnym ekranie”), F11 przełącza pełny ekran i okno zmaksymalizowane.

## Nowości w v2

- **Zaawansowane…** (karty Miejsce, Budynek, Tekstury, Widok, Opcje): rzadko używane ustawienia są w osobnym oknie z przyciskami Zapisz / Anuluj
  (Anuluj przywraca wartości sprzed otwarcia okna).
- **Karta Miejsce** w trzech kartach (szukaj, współrzędne, zaznaczony budynek); karta **Budynek** jest zablokowana do czasu zbudowania modelu,
  a „Dach ze zdjęcia szczytu” jest w karcie Tekstury.
- **Prompt dla GPT**: zasada „popraw widoczną ścianę zamiast rysować nową”, spis przed rysowaniem, ściana kończy się na okapie, ściany bez zdjęcia
  tylko wywnioskowane (`inferred`). Odpowiedź ma JSON z `photo_counts`; program porównuje liczbę okien na zdjęciu z liczbą na arkuszu i ostrzega.
- **Wklej opis od GPT**: zawsze otwiera okno z polem tekstowym (licznik wklejonych znaków, „Wklej ze schowka”), wyniki i błędy są w oknie.
- **Edytor mapowania na cały ekran** (panel korekt → „Edytor mapowania – całe okno…”): ramka wycinka z przeciąganymi krawędziami i narożnikami,
  zoom kółkiem, przesuwanie środkowym przyciskiem; zakładka **Prostowanie zdjęcia**: cztery narożniki na prawdziwym zdjęciu ściany → płaski obraz
  (zapisany w `texture/rectified/` projektu i użyty na powierzchni).
- Architektura: patrz [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

### Arkusz od GPT w innym rozmiarze / sklejone panele
- Cięcie arkusza rozdziela panele, które się stykają (np. S1 przylegające do S3) – cięcie XY po pustych liniach.
- Skala px/m jest przeliczana na faktyczny rozmiar obrazu (GPT często oddaje 1254 px zamiast 4096).
- Obraz ściany o kształcie zbliżonym do ściany jest rozciągany na całą ścianę (bez powtarzania i obcinania); dach (S5) dalej kafelkuje w skali.

### Kąt i okap dachu (okno)
Przycisk „Kąt i okap dachu – okno…” (zakładka Budynek i Tekstury) otwiera duże okno ze zdjęciem szczytu i narysowanym dachem.
Przeciągasz linię okapu (wysokość dachu), końce żółtej linii (wysunięcie dachu), a po zaznaczeniu „Dach asymetryczny” także kalenicę w bok;
osobno ustawiasz kąty obu połaci, okap lewej/prawej strony i wysunięcie przy szczytach. Model za oknem zmienia się na żywo, ZAPISZ zatwierdza, ANULUJ cofa.
