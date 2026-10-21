# MODEL_META – profil generatora GeoStudio nad formatem modeli MaSzyna Reloaded (wersja robocza 3)

PL poniżej, angielskie streszczenie na końcu. / Polish below, an English summary at the end.

**Status: kontrakt do przeglądu z zespołem MaSzyna Reloaded; od 3.0.3 eksporter zapisuje ten profil domyślnie** (`model_format_version`, `osm`, `geo`, `semantic_id`, warstwy świateł, `KHR_lights_punctual` + `light_control`, `smoke_source`, `audio_source`, `asset.extras.geostudio`, autorstwo). Dawny format v1 ([MODEL_META_V1.md](MODEL_META_V1.md)) można dopisać opcją „Eksport: dodaj stary układ metadanych (v1)”. *Status: from 3.0.3 the exporter writes this profile by default; v1 is available as an option.*

## 0. Czym jest ten dokument

Zespół MaSzyna Reloaded ma własny format modeli: [MODEL_FORMAT.md](https://github.com/MaSzyna-Reloaded/datapack-specs/blob/main/MODEL_FORMAT.md) (profil 0.4.0, glTF 2.0 + standardowe rozszerzenia + `extras`). **Nie budujemy drugiego języka.** GeoStudio jest *generatorem* modeli, więc ten dokument jest:

1. **mapowaniem** naszych danych na pola ich profilu (co bierzemy od nich),
2. **dodatkiem** w osobnej przestrzeni nazw `geostudio` (dane, których sama symulacja nie potrzebuje, a edytor i regeneracja tak),
3. **listą propozycji** do ich profilu (to, czego u nich brakuje: dźwięk, ogólne cząstki, rampy, autorstwo).

Zasada nadrzędna: **model deklaruje, co ma i co może z siebie wypuścić, a świat (silnik, symulator, scenariusz) decyduje, kiedy i jak to pokazać.** Model niczego nie symuluje i nie zawiera skryptów ani próbek dźwięku.

## 1. Zasady

1. **glTF najpierw.** Co ma standardowe odwzorowanie w glTF (`KHR_lights_punctual`, materiały PBR, `KHR_node_visibility`, `MSFT_lod`), zapisujemy standardem, nie własnymi polami.
2. **Znaczenie tylko z metadanych, nigdy z nazw.** Nazwy węzłów są czytelne dla człowieka; adresuje się przez `semantic_id`.
3. **Opis zamiast cięcia modelu.** Ściany nie są cięte, a podmodele nie są dublowane. Element funkcjonalny (okno, wylot dymu) to dane na powierzchni; jeśli format wymaga geometrii (siatka światła), eksporter **generuje** ją z opisu (cienki quad przed ścianą), a ściana zostaje w całości.
4. **Jedno źródło prawdy.** Autorem danych jest projekt (`.mgdot`); eksport jest ich pochodną i da się go odtworzyć.
5. **Nieznane klucze konsument ignoruje**, brak klucza = wartość domyślna. Zmiany łamiące podnoszą wersję.
6. **Jednostki i osie jak w ich profilu:** metry, sekundy, radiany; +Y w górę, +Z „przód” obiektu, +X w lewo (to standard glTF). *Do sprawdzenia w eksporterze:* kierunek „przodu” budynku względem naszego układu.
7. **Wersje:** `asset.extras.model_format_version` (wersja ich profilu, wymagane) oraz `asset.extras.geostudio.profile_version` (wersja tego dokumentu).

## 2. Nagłówek (`asset`)

| Pole | Wartość z GeoStudio | Skąd |
|---|---|---|
| `asset.generator` | `GeoStudio 3.0.3` | glTF |
| `asset.copyright` | `© 2026 Autor, licencja SPDX` (np. `© 2026 Miłosz "pol102" Mindak, CC-BY-4.0`) | glTF, z ustawień „Autor” i „Domyślna licencja” |
| `asset.extras.model_format_version` | `"0.4.0"` (tyle, ile obsługujemy) | **ich profil, wymagane** |
| `asset.extras.osm` | tagi OSM budynku, tabela niżej | ich profil |
| `asset.extras.geo` | `{lat, lng, elevation?, heading}` WGS84, `heading` = kierunek lokalnego +Z, zgodnie z ruchem wskazówek zegara od północy geograficznej | ich profil |
| `asset.extras.geostudio` | nasze dane (sekcja 7) | nasza przestrzeń nazw |

**Tagi `osm`** (nasze dawne pola są w gruncie rzeczy tagami OSM):

| Nasze pole (v1) | Tag OSM |
|---|---|
| typ obiektu | `building=yes` (lub dokładniejszy rodzaj, gdy go znamy) |
| `floors` | `building:levels` |
| `height` | `height` |
| `roof_shape` (`gabled`/`hipped`/`skillion`/`flat`…) | `roof:shape` |
| `roof_height` | `roof:height` |
| `colour` | `building:colour` |
| `egib_ids` | `ref:egib` (nasz klucz; dopuszczony jako zwykły tag) |

**Położenie.** Ich `geo` jest prostsze i uniwersalne (WGS84), więc to eksportujemy. Nasze `placement` w EPSG:2180 (z osiami lokalnymi, w podwójnej precyzji) zostaje w `geostudio` jako dane dokładniejsze i odtwarzalne. *Eksport `geo` wymaga przeliczenia EPSG:2180 → WGS84; do zrobienia i przetestowania na punktach kontrolnych.*

## 3. Identyfikatory (`semantic_id`)

Ich zasady: segmenty `[a-z0-9_]+` rozdzielone kropką, unikalne w kolekcji i **stabilne przy ponownym eksporcie**, indeksy porządkowe od zera. Nasz profil rezerwuje ścieżki:

| Ścieżka | Co adresuje |
|---|---|
| `building.part_<n>.walls` | siatka ścian bryły `n` (węzeł) |
| `building.part_<n>.roof` | siatka dachu bryły `n` (węzeł) |
| `building.part_<n>.chimney_<k>` | komin `k` (węzeł) |
| `building.part_<n>.wall_<e>` | ściana = krawędź obrysu `e` (powierzchnia w `geostudio.surfaces`) |
| `building.part_<n>.roof_<k>` | połać dachu `k` (powierzchnia) |
| `emitter.<nazwa>` | emiter (węzeł, który go niesie) |
| `material.<nazwa>` | materiał (np. `material.smoke`) |

`semantic_id` węzłów i materiałów trafia do `extras` zgodnie z ich profilem. Powierzchnie (ściana, połać) nie są węzłami glTF, więc ich identyfikatory leżą w `geostudio.surfaces`. Uwaga: numer ściany to indeks krawędzi obrysu, więc zmiana obrysu może go zmienić; emitery trzymamy przy ścianach w tym samym projekcie, a przy zmianie obrysu program ostrzega.

## 4. Emitery

**Emiter to wszystko, co model może z siebie wypuścić optycznie albo akustycznie.** Trzy rodziny; wiatr świadomie pomijamy.

| Rodzina | Rodzaje | Postać w eksporcie |
|---|---|---|
| **Światło** | powierzchnia (okno, szyld), punktowe, reflektor | siatka światła z polami `light_id…` / węzeł `KHR_lights_punctual` |
| **Cząstki** | dym, ogień, woda, para | `smoke_source` (propozycja: nazwa ogólna) |
| **Dźwięk** | dookólny, kierunkowy | `audio_source` – **propozycja do ich profilu** |

Wspólne: każdy emiter ma `semantic_id` `emitter.<nazwa>` i ewentualny **kanał** (sekcja 5), którym steruje go świat.

### 4.1 Światło – powierzchnia (okno, szyld)

W projekcie: prostokąt `rect` na powierzchni (ściana + odległość od początku ściany + wysokość + szerokość/wysokość, w metrach), kolor, jasność.
W eksporcie: eksporter **generuje węzeł z siatką światła** (cienki quad, ok. 4 cm przed ścianą, z materiałem emisyjnym) i zapisuje w jego `extras` pola z ich sekcji „warstwy światła”:

| Pole | Wartość |
|---|---|
| `light_id` | numer niezależnie sterowanej grupy; **po jednym na kanał** (emitery z tym samym kanałem mają ten sam `light_id`) |
| `light_color` | kolor po zapaleniu `[r, g, b]` |
| `light_state` | `"on"` (stan pokazywany przez tę siatkę) |
| `light_threshold` | pomijamy (ich domyślne 0,325 = poziom światła otoczenia, poniżej którego zapala się światło) |

Ściana zostaje w całości. Mapowanie `kanał → light_id` zapisujemy w `geostudio.channels`, żeby świat wiedział, który `light_id` odpowiada któremu kanałowi.

### 4.2 Światło – punktowe i reflektor

Wprost standard: węzeł z `KHR_lights_punctual` (`point` lub `spot`), z kolorem, `intensity` w kandelach, `range`, a dla reflektora `innerConeAngle` i `outerConeAngle` (połówki kątów, radiany); reflektor świeci wzdłuż lokalnego **−Z** węzła, więc kierunek wyrażamy obrotem węzła. Sterowanie kanałem: `light_control { source, default }` (kanał liczbowy w zakresie [0,1] mnoży `intensity`; `default` jest wymagane).
W programie: pozycja, azymut i nachylenie, kąt stożka (rozbijany na wewnętrzny i zewnętrzny), zasięg, kolor, jasność.

### 4.3 Cząstki – dym, ogień, woda, para

Ich `smoke_source` ma wszystko, czego potrzebują cztery rodzaje: `rate`, `max_particles`, `lifetime`, `speed`, `size`, `material`, `cone_angle`, `growth`, `acceleration` (wektor, więc grawitacja), `drag`, `inherit_velocity`, `source` (kanał mnożący `rate`). To ten sam mechanizm z innymi wartościami, więc w programie są **presety**, które użytkownik może poprawić. Wartości startowe (do dostrojenia w symulatorze, **nie sprawdzone**):

| Preset | rate [1/s] | max | lifetime [s] | speed [m/s] | size [m] | cone [rad] | growth [m/s] | acceleration [m/s²] | drag [1/s] |
|---|---|---|---|---|---|---|---|---|---|
| dym | 8 | 60 | 3–6 | 0,4–0,9 | 0,2–0,5 | 0,25 | 0,15 | [0, 0,15, 0] | 0,3 |
| ogień | 40 | 120 | 0,4–0,9 | 0,8–1,6 | 0,15–0,35 | 0,2 | −0,2 | [0, 1,5, 0] | 0,5 |
| woda | 120 | 400 | 1,2–1,8 | 5–7 | 0,04–0,08 | 0,12 | 0 | [0, −9,81, 0] | 0,05 |
| para | 15 | 80 | 1,5–3 | 0,8–1,4 | 0,15–0,35 | 0,35 | 0,25 | [0, 0,4, 0] | 0,8 |

Każdy preset dostaje **materiał** (`material.<nazwa>`, np. `material.smoke`), bo `material` jest u nich wymagany. Dym można przypiąć do komina z generatora (węzeł na szczycie komina). Ogień zwykle powinien też świecić: preset „ogień” może dołożyć obok światło punktowe (4.2).
*Do uzgodnienia:* nazwa `smoke_source` przy ogniu i wodzie jest myląca (propozycja: `particle_source`); ogień potrzebuje mieszania addytywnego, którego standardowy glTF nie ma, więc to sprawa materiału.

### 4.4 Dźwięk (propozycja do ich profilu)

U nich audio nie ma. Propozycja: `audio_source` w `extras` węzła:

| Pole | Typ | Opis |
|---|---|---|
| `pattern` | `"omni"` / `"directional"` | dookólne albo kierunkowe |
| `cone` | `{inner, outer}` (rad) | tylko kierunkowe; dźwięk wzdłuż lokalnego −Z, jak w spocie |
| `range` | liczba, m | maksymalny zasięg słyszalności (brak = domyślny silnika) |
| `source`, `default` | kanał [0,1], liczba | mnoży głośność, jak `light_control` |
| `trigger` | kanał logiczny | zmiana z fałszu na prawdę uruchamia dźwięk (jak w ich `loop`) |
| `clip` | kanał tekstowy (opcjonalnie) | nazwa klipu wybieranego przez świat |

**Model nie niesie żadnego dźwięku ani nazwy klipu**; klip dostarcza świat przez kanał tekstowy. Dzięki temu ten sam dzwonek, kościół czy przepompownia grają różne dźwięki bez przebudowy modelu. To pasuje do ich kontraktu, bo kanał jest wartością, a nie zdarzeniem: wyzwalacz to zbocze kanału logicznego.

## 5. Kanały i sterowanie

Ich model: **kanał** to nazwana wartość dostarczana przez świat per instancja (logiczna, liczba albo tekst); *własność* deklaruje `source` i `default`. Przyjmujemy go bez zmian. Zasada „jeden autor na własność” obowiązuje.

- **Nazewnictwo kanałów** (nasza propozycja, ich dokument definiuje tylko `clock.*`): małe litery, kropki, np. `building.lights`, `building.chimney_1.smoke`.
- **Manifest kanałów** `geostudio.channels` (opcjonalny, dla narzędzi i walidatora): lista kanałów, które model czyta, z typem, wartością domyślną i przypisanym `light_id`. To tylko spis; wiążące są pola własności.
- **Rampy** (narastanie i opadanie, np. czas zapalania żarówki): w ich kontrakcie byłyby „kontrolerem proceduralnym”. Na razie **poza modelem**; zapisujemy je wyłącznie w `geostudio.channels` jako podpowiedź (`ramp_up`, `ramp_down`) i proponujemy ich dodanie do profilu.
- **Polecenia** (`set`, `on`, `off`, `toggle`) to słownik świata, nie część modelu.

## 6. Autorstwo i licencja

`asset.copyright` niesie krótki zapis czytelny dla człowieka; pełne dane w `asset.extras.geostudio.credits`:

| Klucz | Opis |
|---|---|
| `author` | autor modelu |
| `created`, `modified` | ISO 8601 UTC; `created` nie zmienia się przy kolejnych eksportach |
| `licence`, `licence_url` | licencja **modelu**, identyfikator SPDX (`CC-BY-4.0`, `CC0-1.0`, `MIT`…); pusta = wszelkie prawa zastrzeżone |
| `sources[]` | źródła danych z własnymi licencjami: `{name, url, licence, note}` (Geoportal, własne zdjęcia, tekstury zewnętrzne) |

Licencja modelu nie zmienia licencji danych źródłowych (zdjęć, ortofotomapy); wpisujemy je osobno.

## 7. Dane budynku – `asset.extras.geostudio`

Dane potrzebne edytorowi i regeneracji, których symulacja nie czyta:

| Klucz | Opis (jak w v1) |
|---|---|
| `profile_version` | wersja tego dokumentu |
| `model_type` | `building` (później np. `street_lamp`, parametryczna latarnia) |
| `placement` | położenie w EPSG:2180 (v1) |
| `footprints` | obrysy brył w metrach lokalnych |
| `parts`, `part_roofs` | bryły i dach per część (profil, naczółki, kąty) |
| `chimneys` | kominy (położenie, rozmiar, wysokość nad dachem, czapka) |
| `surfaces` | powierzchnie: `id`, `part`, `role` (`wall`/`roof`/`gable`), `facing` (`N`/`E`/`S`/`W`/`up`), `size` [szerokość, wysokość] m, `sector` (S1…S8) |
| `texture` | `file`, `px_per_m` |
| `channels` | manifest kanałów (sekcja 5) |
| `credits` | autorstwo (sekcja 6) |
| `egib_ids`, `source` | pochodzenie danych |

**Układ powierzchni:** `u` biegnie w prawo, patrząc z zewnątrz; `v` w górę od dolnej krawędzi (ściana: od cokołu, połać: od okapu); metry.

## 8. LOD, materiały, T3D

- **LOD:** ich profil używa `MSFT_lod`. T3D ma już LOD0 i LOD1 (bez kominów); w glTF dołożymy to później.
- **Materiały:** standardowy PBR z glTF, bez własnego formatu. Nasza dawna flaga `emissive_light` na całą powierzchnię jest **zastąpiona** światłem (4.1); tekstura emisyjna nie przełącza światła.
- **T3D (MaSzyna, eksport dodatkowy):** światło-powierzchnia może dać podmodel `light_on…`; cząstki dymu z kominów trafiają do `.inc`; dźwięku T3D nie niesie. Nie sprawdzone w symulatorze.

## 9. Walidacja

Dokładamy do `selftest` kontrole zgodne z ich opisem procesu: nagłówek i wersje, unikalność `semantic_id`, typy odwołań, zakres `geo`, zakres i typ kanałów, `light_control` tylko na węźle ze światłem, `smoke_source` z materiałem i dodatnim czasem życia, deklaracja użytych rozszerzeń w `extensionsUsed`. Docelowo także zewnętrzny walidator glTF i walidator ich profilu.

## 10. Migracja z wersji 1

| v1 | Docelowo |
|---|---|
| `extras.meta` w węźle `Building` | `asset.extras` (`osm`, `geo`, `geostudio`) |
| `meta_version` | `model_format_version` + `geostudio.profile_version` |
| `floors`, `height`, `roof_shape`, `roof_height`, `colour` | tagi `osm` |
| `placement` | `geo` (WGS84) + `geostudio.placement` |
| `emissive_light`, węzły `_lit` | światło-powierzchnia (4.1) |
| tymczasowe `emitters[]`/`channels[]` (3.0.2) | emitery wg sekcji 4, kanały wg sekcji 5 |
| plik `<model>.meta.json` | zostaje jako kopia dla narzędzi, które nie czytają `extras` |

**Etapy:**
1. **Tanie:** `model_format_version`, `osm`, `geo`, `semantic_id`, `asset.copyright` i `credits`, `surfaces` (stabilne id).
2. **Światło i cząstki:** quady światła z polami `light_id…`, `KHR_lights_punctual`, `light_control`, presety cząstek z materiałem, edytor rysowania emiterów na ścianie.
3. **Dźwięk, LOD, walidator:** `audio_source` (po uzgodnieniu), `MSFT_lod`, walidatory.

*Technicznie:* trzeba sprawdzić, czy eksporter glTF w Godocie pozwoli wpisać `asset.extras` i rozszerzenia. Jeśli nie, dopisujemy je po zapisie pliku (to zwykły JSON).

## 11. Pytania do zespołu MaSzyna Reloaded

1. **Atlas światła:** ich dokument mówi, że sposób odwołania do niego jest do ustalenia. Czy quady światła z `light_id` wystarczą na start?
2. **Jednostki:** kąty w `smoke_source` i `light_threshold` (poziom światła otoczenia) są bez jednostek. Radiany i skala 0–1?
3. **Cząstki:** `smoke_source` czy ogólne `particle_source`? Jak ogień ma uzyskać mieszanie addytywne?
4. **Dźwięk:** czy przyjmą `audio_source` w proponowanej postaci (wyzwalacz logiczny + klip przez kanał tekstowy)?
5. **Kanały:** czy model ma deklarować, jakich kanałów używa (manifest), i jak nazywać kanały budynków?
6. **Kanał a warstwa światła:** jak kanał ma sterować `light_id` (poza progiem zmierzchu)?
7. **Rampy:** czy kontroler proceduralny z narastaniem i opadaniem trafi do profilu?
8. **Układ osi:** potwierdzenie, że „przód” budynku to +Z, a +X to lewa strona.

---

## English summary

This is a **generator profile on top of the MaSzyna Reloaded model format** ([MODEL_FORMAT.md](https://github.com/MaSzyna-Reloaded/datapack-specs/blob/main/MODEL_FORMAT.md), profile 0.4.0, glTF 2.0 + standard extensions + `extras`), not a second language. The 3.0.2 exporter still writes version 1 ([MODEL_META_V1.md](MODEL_META_V1.md)); this is the target.

- **Principle:** the model declares what it has and can emit; the world decides when and how to show it. glTF first; meaning from metadata, never from names; describe instead of cutting the mesh (where the format needs geometry, the exporter generates a thin quad in front of the wall from the description).
- **Header:** `asset.generator`, `asset.copyright`, `asset.extras.model_format_version` (required), `osm` tags (`building:levels`, `height`, `roof:shape`, …), `geo` (WGS84 lat/lng, heading) – ours `placement` (EPSG:2180) stays in `asset.extras.geostudio`.
- **Ids:** `semantic_id` with dot-separated `[a-z0-9_]+` paths, stable across re-exports (`building.part_0.wall_2`, `emitter.window_1`, `material.smoke`).
- **Emitters = everything the model can emit optically or acoustically** (wind excluded): *light* (surface → generated quad with `light_id`/`light_color`/`light_state`; point and spot → `KHR_lights_punctual` + `light_control`), *particles* (smoke, fire, water, steam as presets of `smoke_source`, with a material; proposal: generic `particle_source`), *audio* (`audio_source` proposal: omni/directional, cone, range, gain channel, logical trigger, clip name via a text channel – the model carries no sound).
- **Channels:** per their model (property declares `source` + `default`); optional manifest `geostudio.channels` for tooling; ramps stay outside the model for now (proposed as a procedural controller).
- **Credits:** `asset.copyright` + `geostudio.credits` (author, created/modified ISO 8601 UTC, SPDX licence, sources with their own licences).
- **Building data** (footprints, parts, roofs, chimneys, surfaces, texture) live in `asset.extras.geostudio`.
- **Phases:** (1) header/osm/geo/ids/credits/surfaces, (2) lights, quads, particle presets, emitter drawing editor, (3) audio, LOD, validators. Open questions to the Reloaded team are listed in section 11.
- **Not verified:** the preset values, the exporter's ability to write `asset.extras`, T3D behaviour in the simulator, and any importer behaviour in MaSzyna Reloaded.
