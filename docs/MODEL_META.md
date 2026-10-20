# Język opisu modeli (warstwa metadanych) — wersja robocza 2 / Model description language (metadata layer) — draft 2

PL poniżej, krótkie EN na końcu. / Polish below, a short English summary at the end.

**Status: szkic do przeglądu przez zespół. Wersja 2 to PROPOZYCJA kontraktu – kod jeszcze jej nie zapisuje (eksporter pisze `meta_version` 1).**
Kierunek: celujemy przede wszystkim w **MaSzyna Reloaded** i **dużo opisujemy w metadanych**, a nie w geometrii: łatwiej zignorować dane niż ciąć modele i dublować podmodele. Dokument opisuje *kontrakt* między eksporterem
(Photo-to-3D Studio) a konsumentami (Blender, Godot world-assets / Reloaded, dalsze potoki do E3D/T3D).
E3D/T3D to warstwa implementacji; tu opisujemy warstwę **znaczenia**.

## Zasady

1. **Siatka = wizualizacja, meta = opis.** Geometria i materiały służą tylko do wyświetlenia.
   Wszystko, co ma znaczenie semantyczne (typ obiektu, piętra, dach, światło), siedzi w metadanych.
2. **Znaczenie tylko z meta, nigdy z nazw.** Nazwy węzłów (`walls_p0`, `roof_p0_lit`) są czytelne
   dla człowieka, ale konsument **nie może** na nich polegać (żadnego `starts_with("light_")`).
3. Metadane to glTF `extras` węzła, klucz `meta`. Ten sam opis trafia do pliku `<model>.meta.json`
   obok `.glb` (dla narzędzi, które nie czytają `extras`).
4. Nieznane klucze konsument ignoruje; brak klucza = wartość domyślna. Zmiany łamiące podnoszą `meta_version`.
5. **Opis zamiast geometrii.** Elementy funkcjonalne (świecące okna, wejścia) są *danymi* na powierzchni, nie osobną siatką. Eksporter ich nie wycina z modelu ani nie dubluje podmodeli; konsument sam decyduje, jak je pokazać (shader, maska emisji, ukryty quad) albo je pominąć.
6. Jednostki: metry, oś Y w górę (glTF). Współrzędne świata: EPSG:2180.

## Węzeł główny `Building` — `extras.meta`

| klucz | typ | opis |
|---|---|---|
| `meta_version` | int | wersja kontraktu (obecnie 1) |
| `model_type` | string | `building` (kolejne typy w przyszłości) |
| `generator` | string | program, który wyeksportował |
| `name`, `source` | string | nazwa projektu, źródło (np. EGiB/Geoportal) |
| `egib_ids` | string[] | identyfikatory budynków z ewidencji |
| `parts` | int | liczba brył (część główna + przybudówki) |
| `floors` | int | liczba kondygnacji (jeśli znana) |
| `height` | float | wysokość całkowita [m] |
| `wall_height` | float | wysokość ścian części głównej [m] |
| `roof_shape` | string | `gabled` / `skillion` / `flat` (nazwy jak w OSM `roof:shape`) |
| `roof_height` | float | wzniesienie dachu ponad ścianami [m] |
| `roof_orientation` | string | `along` / `across` — kalenica względem dłuższego boku (tylko dach spadzisty) |
| `colour` | string | `#rrggbb` — średni kolor elewacji |
| `footprints` | float[][][] | obrysy brył w metrach lokalnych [x, z] |
| `texture` | object | `file`, `px_per_m` |
| `placement` | object | położenie w świecie, patrz niżej |

| `part_roofs` | object[] | (gdy dach z generatora lub asymetryczny) dach per część, patrz niżej |
| `chimneys` | object[] | kominy, patrz niżej |

## Położenie (`placement`)

```
{ "crs": "EPSG:2180", "origin": [E, N], "local_x": [ex, ey], "local_z": [fx, fy], "rotation_deg": θ }

E = origin[0] + x * local_x[0] + z * local_z[0]
N = origin[1] + x * local_x[1] + z * local_z[1]       (x, z = współrzędne węzła glTF, metry)
```

Wektory są ortonormalne. Uwaga: liczyć w podwójnej precyzji (EPSG:2180 ma wartości rzędu 10⁵–10⁶, 32-bit float da błąd ~3 cm).

## Podmodele (węzły siatki) — `extras.meta`

| klucz | typ | opis |
|---|---|---|
| `layer` | string | `walls` / `roof` / `chimney` |
| `part` | int | indeks bryły (0 = główna) |
| `part_role` | string | `main` / `annex` |
| `chimney_id` | int | tylko `layer == "chimney"`: numer komina, zgodny z `id` w liście `chimneys` na węźle głównym |
| `emissive_light` | bool | **tylko gdy `true`**: część świeci (okna, lampy). Brak klucza = nie świeci. |

Części świecące są wydzielone do osobnego węzła (`..._lit`), więc konsument nie musi filtrować trójkątów.
Oznaczana jest cała ściana/połać (pole „Świeci” w panelu powierzchni); światło tylko w oknach wymaga osobnej geometrii okien (nie zrobione; opis otworów z GPT usunięto).

## Wersja 2 – propozycja (do akceptacji)

Nowe elementy węzła głównego (`meta_version: 2`). Stare klucze zostają; konsument v2 czyta też v1 (brak nowych kluczy = brak tych funkcji).

### Powierzchnie – `surfaces[]`

Każda ściana, połać i ściana szczytowa ma **stabilny identyfikator** liczony z roli i strony, a nie z kolejności generowania (przebudowa dachu nie może zmieniać id ścian).

| klucz | typ | opis |
|---|---|---|
| `id` | string | np. `p0_wall_S`, `p0_roof_A`, `p0_gable_W` (część, rola, strona) |
| `part` | int | indeks bryły |
| `role` | string | `wall` / `roof` / `gable` |
| `facing` | string | `N` / `E` / `S` / `W` / `up` – strona świata, w którą patrzy powierzchnia |
| `size` | [szerokość, wysokość] | wymiary w metrach, w układzie powierzchni (poniżej) |
| `sector` | string | kod sektora tekstury (`S1`…`S8`), jeśli jest |

**Układ powierzchni:** `u` biegnie w prawo, patrząc na powierzchnię z zewnątrz; `v` w górę od dolnej krawędzi (u ściany: od cokołu/ziemi, u połaci: od okapu). Metry.

### Emitery – `emitters[]`

Fragment powierzchni, który **może** świecić. To wyłącznie opis; nic nie jest wycinane w siatce.

| klucz | typ | opis |
|---|---|---|
| `id` | string | unikalny w modelu |
| `surface` | string | `id` powierzchni, na której leży |
| `rect` | [u, v, szerokość, wysokość] | prostokąt w układzie powierzchni, metry |
| `kind` | string | `window` / `lamp` / `sign` / `door_glass` |
| `group` | string | grupa włączania (np. `floor1`, `all`); konsument zapala grupy razem |
| `colour` | string | `#rrggbb`, kolor po zapaleniu (domyślnie ciepła biel) |
| `strength` | float | jasność względna, domyślnie 1.0 |
| `mask` | string | (opcjonalnie) plik maski emisji w skali tekstury, jeśli prostokąt nie wystarcza |

Maska w panelu (wycinanka okna) służy **tylko do wyznaczenia `rect`** (i opcjonalnie pliku `mask`). `emissive_light` z wersji 1 zostaje jako przestarzałe i oznacza „cała powierzchnia świeci”.
Eksport T3D **nie** tworzy podmodeli `light_on` z emiterów (zostaje neutralne `light_on00`).

### Kanały i emitery sterowane z zewnątrz (rozszerzenie v2)

Zasada: **model deklaruje, co można sterować i jak jest ukształtowane; to, co się dzieje, ustala wywołujący** (silnik, symulator, scenariusz). Model nie zawiera skryptów ani próbek dźwięku.

**`channels[]`** – nazwane wejścia stanu obiektu:

| klucz | typ | opis |
|---|---|---|
| `id` | string | np. `floor1_lights` |
| `type` | string | `switch` (0/1) / `level` (0…1) |
| `default` | number | stan początkowy |
| `ramp_up`, `ramp_down` | float | domyślny czas narastania/opadania [s] |

**`emitters[]`** (zastępuje wąski opis z poprzedniej sekcji; `group` zastąpione przez `channel`). Wspólne: `id`, `kind` (`light` / `audio` / `smoke`), `channel` (opcjonalnie – kanał, który nim steruje; jeden kanał może sterować wieloma emiterami).

- `kind: light` – jak wyżej: `surface`, `rect`, `colour`, `strength`, `mask`, plus `channel`.
- `kind: audio` – tylko kształt źródła, **bez klipu**:
  - `position` [x, y, z] – metry, układ modelu,
  - `pattern` – `omni` (dookólne) / `directional` (kierunkowe),
  - `direction` [x, y, z] i `cone_deg` – tylko dla `directional`,
  - `range_m` – zasięg domyślny (opcjonalnie).
- `kind: smoke` – komin (`chimney_id`), intensywność z kanału.

**Wywołania (nie są częścią modelu, to słownik dla konsumentów):**
- `set(channel, value, ramp?)`, `on(channel)`, `off(channel)`, `toggle(channel)` – stan (światło, dym),
- `emit(emitter_id, params)` – zdarzenie, np. dla `audio`: `{clip, gain, pitch, loop}`. Klip wybiera ten, kto wywołuje, więc model nie niesie żadnego dźwięku.

### Źródła światła i latarnie (propozycja)

Emiter `light` dostaje pole `shape`: `surface` (prostokąt na powierzchni, jak okna – domyślne) albo `point` / `spot` (prawdziwe źródło światła: `position`, `direction`, `cone_deg`, `range_m`, `colour`, `strength`). Latarnia ma zwykle oba na jednym kanale (np. `lamp`): świecący klosz (`surface`) i światło na ulicę (`spot`).
Nowy typ `model_type: street_lamp` (rekwizyt): składany z parametrów (wysokość słupa, wysięgnik, oprawa), nie z obrysu EGiB. Pozycje wielu sztuk w świecie należą do scenerii, nie do modelu.

### Autorstwo i licencja – `credits` (propozycja)

| klucz | typ | opis |
|---|---|---|
| `author` | string | autor modelu (np. `Miłosz "pol102" Mindak`), ustawiany w programie |
| `created` | string | data utworzenia projektu, ISO 8601 UTC (`2026-10-21T01:58:00Z`); **nie zmienia się** przy kolejnych eksportach |
| `modified` | string | data ostatniej zmiany projektu, ISO 8601 UTC; aktualizowana przy zapisie/eksporcie |
| `licence` | string | licencja **modelu** jako identyfikator SPDX (np. `CC-BY-4.0`, `CC0-1.0`, `MIT`); pusty = „wszelkie prawa zastrzeżone” |
| `licence_url` | string | (opcjonalnie) link do pełnego tekstu |
| `sources` | object[] | źródła danych: `{name, url, licence, note}` – np. Geoportal.gov.pl (obrys, ortofoto), własne zdjęcia, tekstury zewnętrzne |
| `generator` | string | program i wersja (już jest w węźle głównym; tu dla spójności) |

Daty i autor są zapisywane także w pliku projektu `.mgdot` (`project.json`), a program ma ustawienie „Autor” i „Domyślna licencja”. Licencja modelu nie zmienia licencji danych źródłowych (zdjęć, ortofotomapy): wpisywane są osobno w `sources`.

### Dalsze warstwy (do omówienia)

- **Elementy funkcjonalne:** punkty zaczepienia (komin z dymem – jest; wejście, antena) jako pozycja + kierunek.
- **Dla symulatora:** obrys do kolizji/podłoża, tagi scenerii (epoka, region, styl).
- **Pochodzenie:** źródła danych, wersja programu, licencja tekstur, skala.

## Czego format nie niesie

- LOD-ów (są dopiero w eksporcie T3D, patrz [FORMATS.md](FORMATS.md)), speculara (core glTF go nie ma).
- Szczegółów korekt mapowania (są w pliku projektu, nie w eksporcie).

## Pytania do zespołu

- Czy `roof_shape` w nazwach OSM wystarcza, czy potrzebujecie własnego słownika?
- ~~Czy `emissive_light` ma być bool, czy poziom/kolor?~~ W wersji 2: `emitters[]` z `strength` i `colour`.
- Czego dokładnie oczekuje importer **MaSzyna Reloaded** (nazwy, `extras`, sposób zapalania)? Do uzgodnienia z ich dokumentacją.
- Czy potrzebne dodatkowe typy `model_type` (kapliczka, wiata, ogrodzenie)?

### Dach per część – `part_roofs` (opcjonalne)
Lista wpisów `{part, ...}`; pola występują tylko wtedy, gdy dotyczą części:
- `ridge_shift` – przesunięcie kalenicy od środka rozpiętości w metrach (dodatnie = w stronę strony A, czyli t > 0 osi poprzecznej do kalenicy),
- `roof_profile` – (v3, tylko dla dachu z zakładki Dach) profil dachu w rzucie szczytu: pary `[x od lewej krawędzi zdjęcia szczytu, y ponad okapem]` w metrach, od ściany do ściany (≤7 wierzchołków); `roof_hip_a`, `roof_hip_b` – wcięcie naczółków od końców kalenicy w metrach (0 = brak).
- `roof_angles` – `[kąt połaci A, kąt połaci B]` w stopniach.
Brak wpisu = dach symetryczny, prosty. Wysunięcie dachu poza ściany jest już zawarte w bryle dachu (mesh), meta go nie powtarza.

### Kominy (opcjonalne)
Węzły `chimney_<n>` (`layer: "chimney"`, `part` = bryła, na której dachu stoi komin). Węzeł główny ma dodatkowo listę `chimneys`:

| klucz | typ | opis |
|---|---|---|
| `id` | int | numer komina (zgodny z `chimney_id` węzła i nazwą `chimney_<id>`) |
| `part` | int | indeks bryły |
| `centre` | [x, z] | środek komina, współrzędne węzłów glTF, metry |
| `size` | [szerokość X, długość Z] | wymiary korpusu bez czapki, metry |
| `height_above_roof` | number | wysokość nad najwyższym punktem połaci pod kominem (od strony kalenicy), metry |
| `base_y`, `top_y` | number | dolna (schowana w dachu) i górna krawędź, metry nad ziemią |
| `cap` | bool | czy ma betonową czapkę (płyta 8 cm, wysunięta o 5 cm poza korpus) |

Brak listy = brak kominów. Korpus ma teksturę powielaną z fragmentu ściany (materiał `chimney_<n>`).


---

## English summary

The meta layer is the **meaning** of the model; the mesh is only visualisation. Metadata live in the glTF node `extras.meta` and in `<model>.meta.json`. Units: metres, Y up; world: EPSG:2180.

- Root node `Building`: `meta_version`, `model_type`, `generator`, `name`, `source`, `egib_ids`, `parts`, `floors`, `height`, `wall_height`, `roof_shape` (`gabled`/`skillion`/`flat`), `roof_height`,
  `roof_orientation`, `colour`, `footprints` (local metres [x, z]), `texture` (`file`, `px_per_m`), `placement`, `part_roofs`, `chimneys`.
- `placement`: `E = origin[0] + x·local_x[0] + z·local_z[0]`, `N = origin[1] + x·local_x[1] + z·local_z[1]` (compute in double precision).
- Submodels (mesh nodes): `layer` (`walls`/`roof`/`chimney`), `part`, `part_role` (`main`/`annex`), `chimney_id`, `emissive_light` (only when true; lit parts are separate nodes `..._lit`).
- `part_roofs[]`: `part`, `ridge_shift` (m from the middle, + towards side A), `roof_angles` [A, B] (deg), `roof_profile` (pairs `[x from the left edge of the gable picture, y above the eaves]`, m, wall to wall, ≤ 7 vertices),
  `roof_hip_a`, `roof_hip_b` (hip setback from the ridge ends, m; 0 = none). The overhang is already part of the roof mesh.
- `chimneys[]`: `id`, `part`, `centre` [x, z], `size` [width X, length Z], `height_above_roof`, `base_y`, `top_y`, `cap`.
- Not carried: LODs (only in the T3D export), specular, UV edit details (those are in the project file).
- Removed in v3: `surfaces`, `openings`, `described_building` (the ChatGPT JSON description no longer exists).

### Version 2 – proposal (for approval)
Focus: **MaSzyna Reloaded**, **describe rather than cut**: functional elements are data on a surface, not separate geometry; the consumer decides how to show them (shader, emission mask, hidden quad) or ignores them. Not yet written by the exporter (it still writes `meta_version` 1).
- `surfaces[]`: `id` (stable, from part + role + side, e.g. `p0_wall_S`), `part`, `role` (`wall`/`roof`/`gable`), `facing` (`N`/`E`/`S`/`W`/`up`), `size` [w, h] m, `sector` (`S1`…`S8`). Surface frame: `u` to the right seen from outside, `v` up from the bottom edge (plinth/eaves).
- `emitters[]`: `id`, `surface`, `rect` [u, v, w, h] m, `kind` (`window`/`lamp`/`sign`/`door_glass`), `group` (switched together), `colour`, `strength`, optional `mask` file. The panel cut-out only defines `rect`/`mask`. `emissive_light` (v1) stays, deprecated = whole surface glows. T3D export does not create `light_on` submodels from emitters.
- `channels[]` (`id`, `type` `switch`/`level`, `default`, `ramp_up`/`ramp_down`) and `emitters[]` (`kind` `light`/`audio`/`smoke`, optional `channel`; `group` is replaced by `channel`). Audio emitters carry only the source shape: `position`, `pattern` (`omni`/`directional`), `direction` + `cone_deg`, `range_m`; **no clip**. The model declares what can be driven; the caller decides what happens: `set/on/off/toggle(channel, value, ramp)` for state, `emit(emitter_id, {clip, gain, pitch, loop})` for events.
- Open: what the Reloaded importer expects (names, `extras`, how lights are switched).
- Light emitters get `shape`: `surface` (default) or `point`/`spot` (`position`, `direction`, `cone_deg`, `range_m`, `colour`, `strength`). New `model_type: street_lamp` (parametric prop); placing many lamps belongs to the scenery.
- `credits`: `author`, `created` and `modified` (ISO 8601 UTC; `created` never changes), `licence` (SPDX id of the **model**; empty = all rights reserved), `licence_url`, `sources[]` (`name`, `url`, `licence`, `note`), `generator`. Also stored in the `.mgdot` project; the app gets "Author" and "Default licence" settings. The model licence does not change the licence of source data (photos, orthophoto) – list them in `sources`.
