# Język opisu modeli (warstwa metadanych) — wersja robocza 1

**Status: szkic do przeglądu przez zespół.** Dokument opisuje *kontrakt* między eksporterem
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
5. Jednostki: metry, oś Y w górę (glTF). Współrzędne świata: EPSG:2180.

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

| `surfaces` | object[] | (gdy wczytano opis GPT) `{face, sector, material, condition, source}` — klasa materiału każdej powierzchni; `source` = `photo` (poprawione zdjęcie tej ściany) lub `inferred` (ściana wywnioskowana, bez zdjęcia) |
| `openings` | object[] | (gdy wczytano opis GPT) okna/drzwi, patrz niżej |
| `described_building` | object | podpowiedzi z opisu GPT (`roof_shape`, `floors`, `colour`) — informacyjnie, **nie** zastępują pól nadrzędnych |

## Klasy materiałów (`surfaces[].material`)

`plaster`, `brick`, `stone`, `concrete`, `wood`, `metal_sheet`, `roof_tile`, `roofing_felt`, `thatch`, `glass`, `other`.
Stan (`condition`): `new`, `good`, `worn`, `dirty`. Liczby (chropowatość, metaliczność, połysk) wynikają z tabeli
w programie i trafiają do materiałów glTF; w meta zostaje sama klasa, żeby potok końcowy mógł użyć własnych wartości.

## Otwory (`openings`)

```
{ "id": "okno_1", "type": "window|door|gate|shopfront|vent", "sector": "S1",
  "texture_rect": [x0, y0, x1, y1],            // ułamki obrazu ściany w sektorze, (0,0) = lewy górny róg
  "texture_quad": [A, B, C, D],                // A lewy górny, B prawy górny, C prawy dolny, D lewy dolny
  "emissive_light": true,                       // tylko gdy okno świeci
  "on_walls": [ { "face": "p0:w0", "wall_rect_m": [x0, y0, x1, y1] } ] }   // metry od lewego dolnego rogu ściany; tylko gdy obraz występuje na ścianie raz
```

Pozycje podaje GPT, a program dociąga je do najsilniejszych krawędzi na obrazie (dokładność kilku pikseli).
`wall_rect_m` jest przybliżone (zakłada, że obraz ściany leży na niej bez korekt mapowania).

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
Obecnie oznaczana jest cała ściana/połać; światło tylko w oknach wymaga osobnej geometrii okien (do zrobienia).

## Czego format nie niesie

- LOD-ów, speculara (core glTF go nie ma) — do ustalenia, czy potrzebne jako meta.
- Szczegółów korekt mapowania (są w pliku projektu, nie w eksporcie).

## Pytania do zespołu

- Czy `roof_shape` w nazwach OSM wystarcza, czy potrzebujecie własnego słownika?
- Czy `emissive_light` ma być bool, czy poziom (`emissive_strength`) / kolor?
- Czy potrzebne dodatkowe typy `model_type` (kapliczka, wiata, ogrodzenie)?

### Dach asymetryczny (opcjonalne pola części)
Dla `roof_kind == "gable"` z asymetryczną kalenicą część ma dodatkowo:
- `ridge_shift` – przesunięcie kalenicy od środka rozpiętości w metrach (dodatnie = w stronę strony A, czyli t > 0 osi poprzecznej do kalenicy),
- `roof_angles` – `[kąt połaci A, kąt połaci B]` w stopniach.
Brak pól = dach symetryczny. Wysunięcie dachu poza ściany jest już zawarte w bryle dachu (mesh), meta go nie powtarza.

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
