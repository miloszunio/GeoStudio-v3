# Roadmapa / Roadmap

*PL + EN. Kolejność = priorytet; to plan, nie obietnica. / Order = priority; a plan, not a promise.*

## 1. Teraz / Now

| PL | EN |
|---|---|
| **Sekcja metadanych** – przepracować i dokończyć `model_meta` (dane per część, położenie, odczyt po stronie symulatora), [MODEL_META.md](MODEL_META.md). | **Metadata section** – rework and finish `model_meta` (per-part data, placement, reading on the simulator side), [MODEL_META.md](MODEL_META.md). |
| **Wycinanki na panelu pod elementy udające świecenie** (podświetlone okna, lampy, `light_on`): wycinanie, oznaczanie, maska, eksport do T3D (dziś neutralne `light_on00` bez maski). | **Panel cut-outs for lighting-imitating elements** (lit windows, lamps, `light_on`): cutting, marking, mask, T3D export (today a neutral `light_on00` without a mask). |

## 2. Dalej / Next

| PL | EN |
|---|---|
| **Weryfikacja T3D w MaSzynie / MaSzyna Reloaded**: oś V tekstury, nazwy źródeł dymu przy wielu kominach, `light_on00`, mapy neutralne. Poprawki eksportera wg wyniku. | **T3D verification in MaSzyna / MaSzyna Reloaded**: texture V axis, smoke-source names with several chimneys, `light_on00`, neutral maps. Exporter fixes based on the result. |
| Test na **Windows** (ścieżki, eksport, `.mgdot`) i **żywych usług** Geoportalu i Nominatim. | Testing on **Windows** (paths, export, `.mgdot`) and the **live** Geoportal and Nominatim services. |
| **Dach własny** dla obrysów z wklęsłymi narożnikami (np. kształt L) – dziś pomijane krawędzie. | **Custom roof** for outlines with reflex corners (e.g. L-shaped) – such edges are skipped today. |
| Brak tła szczytu, gdy brak tekstury lub płótno bez S3/S4 – czytelny komunikat lub zapas. | Missing gable backdrop when there is no texture or the canvas lacks S3/S4 – a clear message or a fallback. |

## 3. Później / Later

| PL | EN |
|---|---|
| **Okna i drzwi** jako osobna geometria (dziś tylko tekstura). | **Windows and doors** as separate geometry (texture only today). |
| **Kominy**: skośne połączenia z dachem, brak szwów powtarzanego fragmentu ściany. | **Chimneys**: slanted joints to the roof, no seams on the repeated wall fragment. |
| Więcej **LOD** i opcje optymalizacji siatki dla symulatora. | More **LODs** and mesh optimisation options for the simulator. |
| Import/test **GLB/glTF** w Blenderze i innych silnikach. | **GLB/glTF** import and testing in Blender and other engines. |
| Podpisanie aplikacji, wydania z automatycznych buildów. | App signing, releases from automated builds. |

## 4. Poza zakresem (na razie) / Out of scope (for now)

- Pełny model **LoD2** dachu / A full **LoD2** roof model.
- Bezpośrednia integracja z API OpenAI – ręczne przenoszenie plików do ChatGPT jest **celowe** / Direct OpenAI API integration – moving files to ChatGPT by hand is **intentional**.
