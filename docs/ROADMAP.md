# Roadmapa / Roadmap

*PL + EN. Kolejność = priorytet; to plan, nie obietnica. / Order = priority; a plan, not a promise.*

## 1. Teraz / Now

| PL | EN |
|---|---|
| **Uzgodnienie metadanych z zespołem MaSzyna Reloaded** – nasz zapis (profil 0.4.0 + `geostudio`) jest już domyślny od 3.0.3; do ustalenia: czy `particle_fx`, `weather_source` i `audio_source` trafią do ich profilu, [MODEL_META.md](MODEL_META.md) sekcja 11. | **Agreeing the metadata with the MaSzyna Reloaded team** – our output (profile 0.4.0 + `geostudio`) has been the default since 3.0.3; to settle: whether `particle_fx`, `weather_source` and `audio_source` enter their profile, [MODEL_META.md](MODEL_META.md) section 11. |
| **Metadane: profil nad formatem MaSzyna Reloaded** ([MODEL_META.md](MODEL_META.md)). Zrobione (3.0.3–3.0.4): `model_format_version`, `osm`, `geo`, `semantic_id`, `credits`, `surfaces`, quady światła, `KHR_lights_punctual`, cząstki (dym, ogień, woda, para) z warstwami i `particle_fx`, deszcz z odpływem po dachu, `audio_source`, karta Emitery. Zostaje: weryfikacja w Reloaded, nazwa pliku klipu dźwięku, LOD (`MSFT_lod`), walidatory. | **Metadata: a profile on top of the MaSzyna Reloaded format** ([MODEL_META.md](MODEL_META.md)). Done (3.0.3–3.0.4): `model_format_version`, `osm`, `geo`, `semantic_id`, `credits`, `surfaces`, light quads, `KHR_lights_punctual`, particles (smoke, fire, water, steam) with layers and `particle_fx`, rain with roof runoff, `audio_source`, the Emitery tab. Left: verification in Reloaded, audio clip naming, LOD (`MSFT_lod`), validators. |
| **Wycinanki na panelu pod elementy udające świecenie** (podświetlone okna, lampy, `light_on`): wycinanie, oznaczanie, maska, eksport do T3D (dziś neutralne `light_on00` bez maski). | **Panel cut-outs for lighting-imitating elements** (lit windows, lamps, `light_on`): cutting, marking, mask, T3D export (today a neutral `light_on00` without a mask). |

## 2. Dalej / Next

| PL | EN |
|---|---|
| **Ręczne wrysowywanie powierzchni świecących** (emiterów) na ścianie/połaci bezpośrednio w programie – edytor własny, obok wycinania z panelu. | **Hand-drawing light-emitting surfaces** (emitters) on a wall/roof directly in the app – our own editor, alongside cutting from the panel. |
| **Efekty: weryfikacja i rozwój** – obejrzeć w Reloaded, dostroić presety, więcej gotowych sytuacji (komin, ognisko, para z wywietrznika, fontanna), mgła, śnieg, mokre ściany, licencja tekstur efektów. | **Effects: verification and growth** – check in Reloaded, tune the presets, more ready situations (chimney, bonfire, vent steam, fountain), fog, snow, wet walls, licence of the effect textures. |
| **Weryfikacja T3D w MaSzynie / MaSzyna Reloaded**: oś V tekstury, nazwy źródeł dymu przy wielu kominach, `light_on00`, mapy neutralne. Poprawki eksportera wg wyniku. | **T3D verification in MaSzyna / MaSzyna Reloaded**: texture V axis, smoke-source names with several chimneys, `light_on00`, neutral maps. Exporter fixes based on the result. |
| Test na **Windows** (ścieżki, eksport, `.mgdot`) i **żywych usług** Geoportalu i Nominatim. | Testing on **Windows** (paths, export, `.mgdot`) and the **live** Geoportal and Nominatim services. |
| **Dach własny** dla obrysów z wklęsłymi narożnikami (np. kształt L) – dziś pomijane krawędzie. | **Custom roof** for outlines with reflex corners (e.g. L-shaped) – such edges are skipped today. |
| Brak tła szczytu, gdy brak tekstury lub płótno bez S3/S4 – czytelny komunikat lub zapas. | Missing gable backdrop when there is no texture or the canvas lacks S3/S4 – a clear message or a fallback. |

## 3. Później / Later

| PL | EN |
|---|---|
| **Latarnie uliczne**: `model_type: street_lamp`, generator parametryczny, źródła światła `point`/`spot`. | **Street lamps**: `model_type: street_lamp`, parametric generator, `point`/`spot` light sources. |
| **Okna i drzwi** jako osobna geometria (dziś tylko tekstura). | **Windows and doors** as separate geometry (texture only today). |
| **Kominy**: skośne połączenia z dachem, brak szwów powtarzanego fragmentu ściany. | **Chimneys**: slanted joints to the roof, no seams on the repeated wall fragment. |
| Więcej **LOD** i opcje optymalizacji siatki dla symulatora. | More **LODs** and mesh optimisation options for the simulator. |
| Import/test **GLB/glTF** w Blenderze i innych silnikach. | **GLB/glTF** import and testing in Blender and other engines. |
| Podpisanie aplikacji, wydania z automatycznych buildów. | App signing, releases from automated builds. |

## 4. Poza zakresem (na razie) / Out of scope (for now)

- Pełny model **LoD2** dachu / A full **LoD2** roof model.
- Bezpośrednia integracja z API OpenAI – ręczne przenoszenie plików do ChatGPT jest **celowe** / Direct OpenAI API integration – moving files to ChatGPT by hand is **intentional**.
