# Formaty plików / File formats

PL na górze, EN poniżej. / Polish first, English below.

---

# PL

## 1. `.mgdot` – plik projektu

`.mgdot` to **zwykły zip** (`unzip nazwa.mgdot` działa) pod własnym rozszerzeniem. Wersja formatu: **1**.

| wpis w archiwum | zawartość |
|---|---|
| `manifest.json` | `format: "mgdot"`, `format_version`, `app`, `app_version`, `name`, `saved`, `created`, `summary` (źródło, kondygnacje, liczba części), `has_thumbnail`, `has_prompt`, `files` (lista ścieżek z rozmiarami) |
| `thumbnail.png` | miniatura widoku 3D (480 px) lub ostatni render |
| `prompt.txt` | prompt dla ChatGPT wygenerowany dla tego budynku w chwili zapisu |
| `project.json` | cały stan: obrysy części, wysokości ścian, rodzaj i wysokość dachu, profil i walmy wygenerowanego dachu (`model_roof_gen`), kominy (`model_chimneys`), panele S1–S8 z kodami (`tex_panels`), układ arkusza (`tex_sheet_layout`), korekty UV i ręczne przypisania (`faces`, `rectified`), wszystkie ustawienia, pozycja mapy |
| `geo.txt`, `geo.json`, `geo/ortho.png` | dane z Geoportalu (EGiB) i wycinek ortofotomapy |
| `texture/…` | płótno od GPT, ułożony arkusz `<nazwa>_arkusz.jpg`, `<nazwa>.atlas.json`, `rectified/` (wyprostowane zdjęcia) |
| `project.log` | dziennik zdarzeń |

Nie pakuje się `exports/` ani `renders/`. Ścieżki w `project.json` są względne, więc archiwum można rozpakować gdziekolwiek.

Zasady odczytu: `manifest.json` musi mieć `format == "mgdot"`; `format_version` większy niż znany → odmowa z komunikatem; wpisy ze ścieżką zawierającą `..`, `\`, `:` lub zaczynające się od `/` są odrzucane (ochrona przed zapisem poza folderem).
Zapis: do `<plik>.tmp`, potem podmiana (stary plik jest przez chwilę `.bak`) – awaria w trakcie nie niszczy poprzedniej wersji.
Rozpakowany folder dostaje znacznik `.mgdot_from` z czasem zapisu źródła; dzięki niemu ponowne otwarcie tego samego zapisu używa tego samego folderu.

## 2. Eksport glTF / GLB

`ModelExporter` zapisuje przez `GLTFDocument` (Godot): Y w górę, metry. GLB: `<nazwa>.glb`; glTF: `<nazwa>.gltf` + plik `.bin` + obrazy w osobnym katalogu `exports/gltf/<nazwa>/`.
Obok każdego pliku leży `<nazwa>.meta.json`. Znaczenie modelu jest w metadanych (`extras.meta`), nie w nazwach – patrz [MODEL_META.md](MODEL_META.md).

## 3. Eksport T3D (MaSzyna)

Układ katalogów (jak w paczkach przykładowych, np. „domki” i „latarnie”), tworzony w `exports/t3d/<nazwa>/`:

```
models/<podfolder>/<nazwa>.t3d
textures/<podfolder>/<nazwa>_<tekstura>_diffuse.tga     (+ .mat dla każdej tekstury)
textures/<podfolder>/<nazwa>_plaska_normalmap.tga       neutralna mapa normalnych 4×4
textures/<podfolder>/<nazwa>_matowa_specgloss.tga       neutralna mapa połysku 4×4
scenery/<podfolder>/<nazwa>.inc
nodebank.txt                                            gotowy wpis (jedna linia)
info.txt                                                krótki opis paczki
```

**Model (`.t3d`)** – tekst z końcami linii CRLF, format indeksowany: dla każdego submodelu nagłówek (`Parent`, `Type: Mesh`, `Name`, `Anim`, `Ambient`, `Diffuse`, `Specular`,
`SelfIllum`, `Wire`, `WireSize`, `Opacity`, `Map`, `MaxDistance`, `MinDistance`, `Transform`), potem `NumIndices` (trójki indeksów) i `NumVerts` z wierszami
`x y z nx ny nz u v tx ty tz tw`.

| submodel | zawartość |
|---|---|
| `LOD0` (`LOD0_2`, …) | cała bryła, 0–200 m; jeden submodel na każdą teksturę, największa powierzchnia ma `Map: -1` (tekstura z linii `node`) |
| `LOD1` (`LOD1_2`, …) | ta sama bryła **bez kominów**, 200–2000 m |
| `light_on00` | tylko powierzchnie oznaczone jako świecące, `SelfIllum: true`, własna tekstura (opcja) |
| `smokesource_light` | pusty submodel (`NumVerts: 0`) z przesunięciem na szczycie komina; przy kilku kominach `smokesource_light_2`, … (opcja) |

**Układ współrzędnych.** Godot: Y w górę. T3D (jak 3ds Max): Z w górę. Przekształcenie `(x, y, z) → (x, −z, y)` jest obrotem, więc **kolejność wierzchołków trójkąta jest odwrócona**
(Godot: front zgodnie z ruchem wskazówek zegara, T3D: przeciwnie). Przód budynku (+Z w Godocie) wypada po stronie −Y, jak w przykładach. Współrzędna **V jest odwrócona** (`v' = 1 − v`),
a TGA zapisywane od dołu (jak w przykładowych teksturach). Tangenty liczone z UV.

**Tekstury.** Każda użyta tekstura (region arkusza lub kolor) → nieskompresowane `.tga` 24-bit (32-bit, gdy ma alfę), zmniejszone do ustawionego maksimum (domyślnie 2048 px).
`<tekstura>.mat`:

```
shader: normalmap_specgloss
texture_diffuse: textures/<podfolder>/<nazwa>_<tekstura>_diffuse
texture_normalmap: textures/<podfolder>/<nazwa>_plaska_normalmap
texture_specgloss: textures/<podfolder>/<nazwa>_matowa_specgloss
```

**`.inc`** (parametry: `p1 p2 p3` – położenie, `p4` – obrót wokół osi pionowej):

```
origin (p1) (p2) (p3)
rotate 0 (p4) 0
node 2000 0 none model 0 0 0 0 <podfolder>/<nazwa>.t3d <podfolder>/<nazwa>_<tekstura> lights 4 endmodel
rotate 0 0 0
endorigin
```

**Do potwierdzenia w symulatorze** (nie był dostępny przy pisaniu): kierunek V, nazwy `smokesource_*` przy wielu kominach, `light_on00` bez maski okien, wygląd z neutralnymi mapami normalnych/połysku.
Kontrole automatyczne sprawdzają: trójki indeksów, indeksy w zakresie, normalne jednostkowe, każdy trójkąt przeciwnie do ruchu wskazówek patrząc z zewnątrz, budynek stoi na z = 0, LOD1 lżejszy od LOD0, nagłówek i rozmiar TGA.

---

# EN

## 1. `.mgdot` – the project file

`.mgdot` is an **ordinary zip** (`unzip name.mgdot` works) under its own extension. Format version: **1**.

| archive entry | content |
|---|---|
| `manifest.json` | `format: "mgdot"`, `format_version`, `app`, `app_version`, `name`, `saved`, `created`, `summary` (source, floors, number of parts), `has_thumbnail`, `has_prompt`, `files` (paths with sizes) |
| `thumbnail.png` | thumbnail of the 3D view (480 px) or the last render |
| `prompt.txt` | the ChatGPT prompt generated for this building at save time |
| `project.json` | the whole state: part outlines, wall heights, roof kind and height, profile and hips of the generated roof (`model_roof_gen`), chimneys (`model_chimneys`), panels S1–S8 with codes (`tex_panels`), sheet layout (`tex_sheet_layout`), UV edits and manual assignments (`faces`, `rectified`), all settings, map position |
| `geo.txt`, `geo.json`, `geo/ortho.png` | Geoportal (EGiB) data and the orthophoto crop |
| `texture/…` | GPT canvas, laid-out sheet `<name>_arkusz.jpg`, `<name>.atlas.json`, `rectified/` (rectified photos) |
| `project.log` | event log |

`exports/` and `renders/` are not packed. Paths in `project.json` are relative, so the archive can be unpacked anywhere.

Reading rules: `manifest.json` must have `format == "mgdot"`; a `format_version` higher than known → refusal with a message; entries whose path contains `..`, `\`, `:` or starts with `/` are rejected (protection against writing outside the folder).
Writing: to `<file>.tmp`, then swapped in (the old file is `.bak` for a moment) – a crash cannot destroy the previous version.
The unpacked folder gets a `.mgdot_from` marker with the source save time; opening the same save again reuses that folder.

## 2. glTF / GLB export

`ModelExporter` writes through Godot's `GLTFDocument`: Y up, metres. GLB: `<name>.glb`; glTF: `<name>.gltf` + a `.bin` file + images in a separate directory `exports/gltf/<name>/`.
Next to each file there is `<name>.meta.json`. The meaning of the model lives in metadata (`extras.meta`), not in names – see [MODEL_META.md](MODEL_META.md).

## 3. T3D export (MaSzyna)

Directory layout (as in the sample packs, e.g. "domki" and "latarnie"), created in `exports/t3d/<name>/`:

```
models/<folder>/<name>.t3d
textures/<folder>/<name>_<texture>_diffuse.tga          (+ a .mat for every texture)
textures/<folder>/<name>_plaska_normalmap.tga           neutral 4×4 normal map
textures/<folder>/<name>_matowa_specgloss.tga           neutral 4×4 spec/gloss map
scenery/<folder>/<name>.inc
nodebank.txt                                            ready entry (one line)
info.txt                                                short pack description
```

**Model (`.t3d`)** – text with CRLF line ends, indexed format: each submodel has a header (`Parent`, `Type: Mesh`, `Name`, `Anim`, `Ambient`, `Diffuse`, `Specular`,
`SelfIllum`, `Wire`, `WireSize`, `Opacity`, `Map`, `MaxDistance`, `MinDistance`, `Transform`), then `NumIndices` (index triplets) and `NumVerts` with rows
`x y z nx ny nz u v tx ty tz tw`.

| submodel | content |
|---|---|
| `LOD0` (`LOD0_2`, …) | the whole solid, 0–200 m; one submodel per texture, the largest surface has `Map: -1` (texture comes from the `node` line) |
| `LOD1` (`LOD1_2`, …) | the same solid **without chimneys**, 200–2000 m |
| `light_on00` | only surfaces marked as glowing, `SelfIllum: true`, own texture (option) |
| `smokesource_light` | empty submodel (`NumVerts: 0`) translated to the top of a chimney; with several chimneys `smokesource_light_2`, … (option) |

**Coordinates.** Godot is Y-up. T3D (like 3ds Max) is Z-up. The mapping `(x, y, z) → (x, −z, y)` is a rotation, so **the triangle vertex order is reversed**
(Godot: front faces clockwise, T3D: counter-clockwise). The building front (+Z in Godot) ends up on the −Y side, as in the samples. The **V coordinate is flipped** (`v' = 1 − v`)
and TGA is written bottom-up (like the sample textures). Tangents are computed from the UVs.

**Textures.** Each texture used (an atlas region or a colour) → an uncompressed 24-bit `.tga` (32-bit when it has alpha), reduced to the configured maximum (2048 px by default).
`<texture>.mat`:

```
shader: normalmap_specgloss
texture_diffuse: textures/<folder>/<name>_<texture>_diffuse
texture_normalmap: textures/<folder>/<name>_plaska_normalmap
texture_specgloss: textures/<folder>/<name>_matowa_specgloss
```

**`.inc`** (parameters: `p1 p2 p3` – position, `p4` – rotation about the vertical axis):

```
origin (p1) (p2) (p3)
rotate 0 (p4) 0
node 2000 0 none model 0 0 0 0 <folder>/<name>.t3d <folder>/<name>_<texture> lights 4 endmodel
rotate 0 0 0
endorigin
```

**To be confirmed in the simulator** (not available while writing): the V direction, `smokesource_*` names with several chimneys, `light_on00` without a window mask, appearance with the neutral normal/gloss maps.
The automatic checks verify: index triplets, indices in range, unit normals, every triangle counter-clockwise seen from outside, the building standing on z = 0, LOD1 lighter than LOD0, TGA header and size.
