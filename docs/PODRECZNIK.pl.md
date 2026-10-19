# Photo-to-3D Studio (GeoStudio) v3 – podręcznik użytkownika

*English version: [MANUAL.en.md](MANUAL.en.md)*

Wersja programu: **3.0.1** (Godot 4.6). Dokument opisuje całą ścieżkę „budynek z mapy → model 3D → tekstura z ChatGPT →
dach → kominy → eksport (GLB / glTF / T3D) → plik projektu `.mgdot`” oraz to, co dokładnie sprawdzać podczas testów.

---

## 1. Do czego służy program

> GeoStudio jest narzędziem dedykowanym tworzeniu modeli dla symulatora **MaSzyna**, w szczególności **MaSzyna Reloaded**. Podstawowy eksport to T3D; GLB/glTF jest dodatkowy.

1. Wskazujesz budynek na mapie **Geoportal.gov.pl** (obrys z ewidencji EGiB + ortofotomapa) albo wczytujesz własny obrys GeoJSON.
2. Program buduje bryłę 3D: ściany i **osobną bryłę dachu** (okap, grubość, spód).
3. Generuje **prompt dla ChatGPT**. ChatGPT ze zdjęć budynku robi jedno **płótno** 4096 × 4096 px z ośmioma sektorami
   (S1–S8: ściany, szczyty, dach, dobudówki), każdy obraz wyprostowany, wyczyszczony i w jednej skali.
4. Wskazujesz płótno. Program sam wycina obrazy z sektorów (albo z ramek), nadaje kody S1–S8, układa je w skali
   rzeczywistej i nakłada na ściany i dach. Każdą powierzchnię możesz poprawić ręcznie (edytor UV).
5. W zakładce **Dach** rysujesz profil dachu **na zdjęciu ściany szczytowej** (dwuspadowy, mansardowy, naczółki) i klikasz
   . Generator **kominów** stawia kominy na dachu.
6. Eksport: **GLB** i **glTF** (z metadanymi) oraz **T3D dla symulatora MaSzyna** (modele, tekstury TGA + MAT, plik .inc, wpis do nodebank).
7. Cały stan zapisujesz jako jeden plik **`.mgdot`** (zip pod własnym rozszerzeniem) i otwierasz go później na dowolnym komputerze.

Ręczne przenoszenie plików do/z ChatGPT jest **celowe** – program nie łączy się z API OpenAI.
Dane: © GUGiK / Geoportal.gov.pl – sprawdź warunki usługi, zanim opublikujesz wyniki.

## 2. Wymagania i uruchomienie

- **Gotowy program**: paczka `GeoStudio-windows.zip` (GeoStudio.exe) albo `GeoStudio-linux.zip` (GeoStudio.x86_64). Rozpakuj i uruchom,
  instalacji nie ma. Plik exe nie jest podpisany – SmartScreen może ostrzec przy pierwszym uruchomieniu.
- **Ze źródeł**: Godot **4.6** (standardowy, nie .NET) → Project Manager → **Import** → `project.godot` → **F5**.
- Karta z Vulkan. Bez niej: `godot --rendering-method gl_compatibility`.
- Internet (Geoportal, wyszukiwarka miejsc Nominatim) – tylko do kroku 1; resztę da się robić offline (GeoJSON, projekt `.mgdot`).

Okno startuje na pełnym ekranie; **F11** przełącza pełny ekran.

## 3. Projekt: folder i plik .mgdot

Przy starcie program prosi o **projekt**. Okno startowe ma trzy wejścia: **Wskaż lub utwórz folder…**, **Otwórz plik projektu (.mgdot)…**
oraz listy ostatnich plików (z miniaturą) i folderów.

Praca odbywa się w **folderze projektu** (zapisywany automatycznie), a **plik `.mgdot`** to jego przenośna kopia w jednym pliku.

```
<projekt>/
  project.json         stan: obrysy, ustawienia, tekstura i panele, dach, kominy, korekty UV, pozycja mapy
  geo.txt / geo.json   dane z Geoportalu (atrybuty, obrysy EPSG:2180, usługi, czas)
  geo/ortho.png        wycinek ortofotomapy
  texture/             płótno od GPT, ułożony arkusz <nazwa>_arkusz.jpg, <nazwa>.atlas.json, prompt_gpt.txt, rectified/
  renders/             lastView_<czas>.png z chwili zamknięcia (domyślnie 3 ostatnie)
  exports/             glb, gltf/, t3d/
  project.log          zdarzenia z czasem
```

### Zapis i otwieranie `.mgdot`

- **Opcje → Projekt → Zapisz projekt (.mgdot)** – pierwszy raz pyta o nazwę, potem zapisuje w to samo miejsce. **Zapisz projekt jako…** pyta zawsze.
- **Opcje → Projekt → Otwórz projekt / zmień folder…** albo okno startowe – wskaż plik `.mgdot` lub wybierz go z listy ostatnich.
  Program rozpakowuje go do folderu `<nazwa>_projekt` obok pliku i otwiera. Jeśli ten folder pochodzi dokładnie z tego zapisu, jest użyty ponownie
  (nic się nie rozpakowuje drugi raz); jeśli plik jest nowszy, powstaje `<nazwa>_projekt_2` itd. – nic nie jest nadpisywane.
- Zapis jest **atomowy**: plik powstaje jako `.tmp` i dopiero gotowy zastępuje stary, więc awaria w trakcie nie niszczy poprzedniej wersji.
- Plik z **nowszej wersji formatu** program odrzuca z komunikatem; uszkodzony lub obcy zip – też.
- Do pliku nie wchodzą `exports/` ani `renders/` (można je odtworzyć); wchodzi miniatura i użyty prompt (`prompt.txt`). Szczegóły: [FORMATS.md](FORMATS.md).

## 4. Układ ekranu i sterowanie

Lewy **panel boczny** ma karty: **1 Miejsce → 2 Budynek → 3 Tekstury → 4 Dach → 5 Widok** oraz **⚙ Opcje**. Ukończony krok ma ✓.
Karty Budynek, Tekstury i Dach są zablokowane do zbudowania modelu. Pole **Szukaj ustawienia…** przeszukuje wszystkie karty.
Zmienione ustawienie ma pomarańczowe **↺** (klik = przywróć). Rzadkie ustawienia leżą w oknie **⚙ Zaawansowane…** (Zapisz / Anuluj).

| gest | mapa | widok 3D |
|---|---|---|
| lewy przycisk, przeciąganie | przesuwanie | obrót kamery |
| kółko | zoom | zoom |
| środkowy przycisk | – | przesuwanie sceny |
| klik | wybór budynku (Ctrl/Shift: dodaj/usuń część) | wybór ściany lub połaci |
| `F11` | pełny ekran | |
| `Esc` | zamyka okno / odznacza powierzchnię | |
| `Ctrl+Z`, `Ctrl+Y` | | cofnij / ponów korektę powierzchni |

Przyciski w prawym dolnym rogu widoku 3D: Góra / Przód / Tył / Lewo / Prawo (rzuty ortogonalne), **3D**, **Dach…**, **Kominy…**, **✕ Zamknij**
(zapisuje projekt i zamyka program).

## 5. Krok 1 – Miejsce

1. **Szukaj miejsca** (miejscowość lub adres + Enter; historia 30 wyszukiwań), albo **Współrzędne** (`52.2297, 21.0122`).
2. Kliknij budynek na mapie (obrysy od powiększenia ≤ 2 m/px). EGiB tnie budynki na wielokąty: **Ctrl/Shift + klik** dodaje/usuwa część,
   **+ Sąsiednie części** dodaje stykające się.
3. **Zbuduj model 3D z zaznaczenia →**. Największy wielokąt to bryła główna, reszta to dobudówki.
4. Alternatywa: sekcja **Obrys z pliku GeoJSON** – import własnego obrysu albo **Załaduj przykładowy budynek (L)**.

Ortofotomapa i obrysy są cache’owane lokalnie; zapytania idą przez kolejkę z ponawianiem przy 429/503 (Opcje → Geoportal).

## 6. Krok 2 – Budynek

- **Ściany**: wysokość ręcznie albo z liczby kondygnacji EGiB × wysokość kondygnacji. Ewidencja często zaniża wysokość – dlatego jest przycisk
  **Dopasuj wysokość ścian do proporcji tekstury** (wysokość = długość ściany / proporcje panelu S1).
- **Części budynku**: osobna wysokość ścian, typ i wysokość dachu każdej bryły; ↺ = automat, ✕ = usuń część.
- ⚙ Zaawansowane: proporcje dobudówek, dach pulpitowy dobudówek, tolerancja sklejania, wyrównanie obrysu do osi.

## 7. Krok 3 – Tekstury (przepływ z ChatGPT)

### 7.1 Prompt dla GPT

**1. Prompt dla GPT → Generuj prompt dla GPT…** otwiera okno z gotowym tekstem i przyciskiem **Kopiuj**; kopia leży też w `texture/prompt_gpt.txt`.
Prompt jest liczony z wymiarów budynku i **nie zawiera JSON-a** (opis okien/drzwi został usunięty – ChatGPT go nie utrzymywał). Zawiera:

- dane z ewidencji (obrys, wysokość do okapu, dach, kondygnacje, dobudówki),
- **układ płótna**: 4096 × 4096 px, **8 sektorów** po 2048 × 1024 px (2 kolumny × 4 rzędy), numeracja rzędami od góry; w każdym sektorze jeden element,
  w lewym górnym rogu, z odstępem 16 px, na szarym tle #808080,
- **jedną skalę** dla całego płótna (domyślnie 112 px/m; mniej, jeśli ściana długa nie mieści się w 2048 px),
- kody: **S1** ściana długa A (frontowa), **S2** długa B, **S3/S4** szczyty (prostokąt z trójkątnym szczytem) albo ściany krótkie, **S5** dach (jedna połać z góry),
  **S6–S8** dobudówki i inne ściany; puste sektory zostają puste,
- „KROK 0 – SPIS PRZED RYSOWANIEM” (liczba okien, drzwi, gzymsów), zasadę nadrzędną „popraw zdjęcie, nie rysuj nowego”, zakaz pomijania elewacji,
  ścianę kończącą się na linii okapu, dach jako sama faktura, czyszczenie (niebo, ludzie, rynny, krzaki).

W ChatGPT wklej prompt, **dołącz zdjęcia budynku** i zapisz wygenerowany obraz.

### 7.2 Płótno od GPT

**2. Płótno od GPT**: wskaż zapisany plik (lub **Wybierz z podglądem…**). Kopia trafia do `texture/`. Program rozpoznaje dwa rodzaje płótna:

- **Płótno sektorowe** (zalecane, to, co daje prompt): 2 × 4 sektory. ChatGPT czasem rysuje jasną ramkę wokół sektora – program ją pomija. Z każdego sektora
  odcina tło i wycina obraz; kod wynika z numeru sektora (S1…S8); pusty sektor jest pomijany.
- **Płótno z czerwonymi ramkami** (starszy sposób): ramki 2 px wokół każdego obrazu, kody z kształtu i położenia (heurystyka).

Potem program **układa obrazy w skali rzeczywistej** (wg wymiarów z EGiB) w arkuszu `texture/<nazwa>_arkusz.jpg` i tnie go na regiony. Arkusz zapisywany jest jako
JPG jakości 97 % (kodowanie PNG 4096² trwało ok. 7 s). Wynik jest **zapamiętany**: ponowne wczytanie tego samego pliku z tymi samymi panelami i wymiarami nie powtarza analizy.
Status mówi, ile paneli znaleziono i których brakuje.

- **Przyporządkuj panele…** – edytor: zmiana kodu panelu, przesunięcie/zmiana ramki, dodanie lub usunięcie panelu. Ręczne poprawki są zapamiętane w projekcie i mają pierwszeństwo.
- **Skala arkusza (px/m)** – informacja o skali ułożonego arkusza; ustawia się sama.
- **Podgląd cięcia na regiony…** – pokazuje regiony i ich nazwy. **Usuń teksturę** – model bez tekstur.
- Teksturowanie działa „jak prostopadłościan bez dachu”: ściany dostają S1–S4, dach osobno (S5, kształt z zakładki Dach).
- **Obraz ściany pokrywa całą ścianę** (bez powtarzania i przycinania). Powtarzanie powstaje tylko z korekty powierzchni (skala < 100 %).

### 7.3 Pozostałe sekcje karty

- **Dobór na ściany i dach** – „Automatycznie” albo konkretne zdjęcie dla każdej ściany; **Następny wariant**, **Losuj tekstury**.
- **Relief** – mapa normalnych z jasności zdjęcia (siła osobno dla ścian i dachu, szczegół, wygładzenie, parallax); **Eksportuj mapy normalnych (PNG)**.
- **Skala i materiał**, **Biblioteka zdjęć** (zwykłe zdjęcia jako osobne tekstury), **Cięcie arkusza (zaawansowane)** – parametry automatycznego cięcia, **Przeanalizuj obraz ponownie**.

Własny atlas JSON (`textures/atlas_wroniawy.json` jako wzór) nadal działa jako źródło.

## 8. Krok 4 – Dach i kominy

### 8.1 Typ dachu i sekcja „Dach”
**Typ dachu**: *Dwuspadowy*, *Kopertowy (4 połacie)*, *Własny – kierunki spadków*, *Płaski*. Do tego wysokość ponad okap, wysunięcie poza ściany, grubość i kierunek kalenicy.
**Wysokość dachu działa zawsze**: także na dachu narysowanym (profil jest skalowany) i na dachu własnym (spadki są skalowane). Zmiana typu zastępuje wcześniej narysowany dach.
Pola z ↺ mają stałe miejsce – układ panelu nie skacze, gdy zmieniasz wartość.

### 8.2 „Dach dwuspadowy – profil na zdjęciu szczytu…”

![Edytor dachu](img/roof-gen.png)

Okno ma **rzut boczny** (u góry) i **rzut z góry**. Rzut boczny pokazuje **prawdziwe zdjęcie ściany szczytowej** (panel S3 lub S4) w rzeczywistej skali – dach rysujesz
na nim, nie „na oko”. Program mierzy na zdjęciu linię okapu (różowa) i kalenicę. Bez zdjęcia szczytu (płótno bez S3/S4 albo bez wczytanej tekstury) tło jest szare z podpisem „brak zdjęcia szczytu”.

- **Wierzchołki profilu** (pomarańczowe, do 7): przeciągaj; dwuklik na linii dodaje załamanie (mansarda); prawy przycisk usuwa.
- **Niebieskie kropki na okapie**: w górę/w dół dopasowują wysokość dachu do zdjęcia. **Żółte końce** – wysunięcie dachu; pola: okap lewy/prawy, wysunięcie przy szczytach.
- **Rzut z góry**: przeciągnij kalenicę w bok albo jej końce (naczółki/walmy).
- **Kąt ze zdjęcia szczytu**, **Wysokość ścian ze zdjęcia**, **Zeruj do zwykłego dwuspadowego**.
- **Zmiany stosują się na modelu od razu** (z krótkim opóźnieniem po ostatniej zmianie) – nie ma przycisku „generuj”. `Esc` / × zamyka okno i **przywraca dach sprzed otwarcia**; **Zamknij** zostawia zmiany.

### 8.2a Dach kopertowy i własny

![Dach własny](img/roof-custom.png)

- **Kopertowy**: cztery połacie schodzące do okapu; wysokość z pola „Wysokość dachu”.
- **Własny – kierunki spadków** (przycisk „Dach własny – rzut z góry, kierunki spadków…”): okno z rzutem budynku z góry. Przy każdej krawędzi jest **strzałka**
  pokazująca, w którą stronę opada jej połać, z kątem w stopniach. Kliknij krawędź (żółta = zaznaczona), ustaw **spadek** albo zaznacz **Ścianę szczytową** (krawędź bez połaci).
  Pomarańczowe kropki pokazują wyliczone kalenice i narożniki. **Ścięcie szczytu** robi płaski wierzch na podanej wysokości. **Ten sam spadek na wszystkich** / **Zeruj do kopertowego** przyspieszają pracę.
  Zasada: połać każdej krawędzi rośnie od jej linii okapu do środka, dach to dolna obwiednia wszystkich połaci (tak powstaje kopertowy, dwuspadowy, piramidalny, półwalmowy).
  Krawędzie przy wklęsłych narożnikach (obrys w kształcie L) są pomijane. Zmiany widać na modelu od razu; `Esc` / **Anuluj** przywraca poprzedni dach.

### 8.3 Kominy – generator
Okno z rzutem z góry i dwoma rzutami bocznymi: **Dodaj / Powiel / Usuń** komin, wymiary z palca (szerokość, długość, wysokość nad dachem, położenie X i Z),
przeciąganie po dachu i uchwyt wysokości, **betonowa czapka**, **tekstura korpusu** (zaznacz prostokąt na obrazie ściany – fragment jest powielany; wybierz gładką cegłę bez okna).
Dół komina wchodzi 30 cm pod dach. **Zapisz** zatwierdza, **Anuluj** przywraca. Kominy są zapisane w projekcie i trafiają do eksportów (GLB: węzły `chimney_<n>`; T3D: źródła dymu).

![Okno kominów](img/chimney-editor.png)

## 9. Korekta pojedynczej powierzchni (edytor UV)

Kliknij ścianę lub połać w widoku 3D. Panel po prawej: **Mapowanie** (przesunięcie, skala, obrót, odbicia), **Kawałek** (inny panel lub wycięty fragment powielany na powierzchni),
**Materiał** (kolor, chropowatość, połysk, metaliczność, relief, pole **Świeci**), **Bryła** (podniesienie okapu, kalenicy).

![Panel powierzchni](img/face-panel.png)

**Edytor mapowania – całe okno** działa jak „Unwrap UVW”: tryb **Wycinek** (ramka na obrazie) i **Prostowanie zdjęcia** (cztery narożniki na prawdziwym zdjęciu → płaski obraz zapisany w `texture/rectified/`).
`Ctrl+Z`/`Ctrl+Y` cofają i ponawiają. Korekty należą do konkretnego obrysu i są zerowane po zbudowaniu innego budynku.

## 10. Krok 5 – Widok i eksport

### Eksport modelu

| przycisk | wynik |
|---|---|
| **Eksportuj model do GLB** | `exports/<nazwa>.glb` + `<nazwa>.meta.json` (Y w górę, metry) |
| **Eksportuj model do glTF** | `exports/gltf/<nazwa>/<nazwa>.gltf` + plik `.bin` + tekstury (PNG) + `.meta.json` |
| **Eksportuj model do T3D (MaSzyna)** | `exports/t3d/<nazwa>/` – patrz [FORMATS.md](FORMATS.md) |
| **Otwórz folder eksportów** | |

Pole **Eksport jako paczka ZIP** (nad przyciskami): po każdym eksporcie obok plików powstaje też archiwum `.zip` (GLB: `<nazwa>.zip` z GLB i meta; glTF i T3D: zip całego folderu). Luźne pliki zostają.

Opcje T3D (nad przyciskiem lub w wyszukiwarce ustawień): podfolder (np. `mieszkalne`), największy bok tekstury (512–4096, domyślnie 2048), źródła dymu na kominach,
submodel świateł nocnych. Opis metadanych: [MODEL_META.md](MODEL_META.md).

### Podgląd krawędzi i wierzchołków (jak „Edged Faces” w 3ds Max)

![Krawędzie i wierzchołki](img/wireframe.png)

- **Krawędzie siatki** – model cieniowany z narysowanymi krawędziami. Krawędzie są prawdziwą geometrią rysowaną w przestrzeni ekranu, więc mają **grubość w pikselach**
  (domyślnie 1,6 px), dowolny **kolor** i **nieprzezroczystość**. Krawędzie widoczne są mocne, **zasłonięte bledsze** (suwak „Widoczność krawędzi zasłoniętych”, 0 = ukryte).
- **Pokaż wierzchołki** – punkty o stałej wielkości na ekranie z obwódką. Kolor zależy od rodzaju: zielony – obrys przy gruncie, pomarańczowy – górne narożniki ścian,
  czerwony – dach i kominy. Wielkość, grubość i kolor obwódki oraz kolory ustawisz w sekcji **Krawędzie i wierzchołki**.
- **Pokaż przekątne trójkątów** – domyślnie ukryte (widać krawędzie ścian i połaci, nie podział na trójkąty).

Dalej: **Co pokazać** (elewacje, dach, podłoże, siatka pomocnicza), **Światło i tło**, **Kamera**, **Podłoże i siatka**.

## 11. Opcje

**Projekt** (zapis/otwieranie `.mgdot`, render, folder projektu), **Program** (czcionka, pełny ekran, reset ustawień), **Połączenie z Geoportalem** (adresy usług, **Testuj usługi**), **Cache** (ważność, rozmiar, równoległość).

## 12. Scenariusz testowy (ok. 25 minut)

1. Start: okno startowe projektu; wskaż nowy folder.
2. **Załaduj przykładowy budynek (L)** (Miejsce → Obrys z pliku) albo wskaż budynek na mapie. Zbuduj model. Karty się odblokowały.
3. Tekstury → **Generuj prompt** → sprawdź, że jest 8 sektorów S1–S8, skala px/m, brak JSON-a. Wykonaj płótno w ChatGPT, zapisz, wskaż w **2. Płótno od GPT**.
   Sprawdź status („Płótno od GPT: n paneli”), **Przyporządkuj panele…**, **Podgląd cięcia**. Ponowne wczytanie tego samego pliku ma być natychmiastowe.
4. Dach: **Dach – rysuj i generuj…** – zdjęcie szczytu w skali; przeciągnij wierzchołki, dodaj załamanie, walm; ; sprawdź model 3D.
5. **Kominy – generator…**: dodaj komin, ustaw w rzucie z góry i z boku, wybierz fragment ściany, Zapisz.
6. Kliknij ścianę: przesuń/skaluj, zmień panel, Prostowanie zdjęcia, Ctrl+Z/Y.
7. Widok: włącz **Krawędzie siatki** i **Pokaż wierzchołki**; zmień grubość i kolory.
8. Eksport: GLB (Blender), glTF (`.gltf` + `.bin`), T3D (struktura katalogów, wpis do nodebank). Opcjonalnie wczytaj T3D w symulatorze.
9. **Zapisz projekt (.mgdot)**, zamknij program, uruchom, otwórz plik z listy ostatnich: model, tekstura, dach, kominy i korekty wracają.

**Co zgłaszać**: kroki do odtworzenia, zrzut ekranu, `project.log`, płótno od GPT (jeśli problem dotyczy cięcia lub tekstury).

## 13. Znane ograniczenia i to, czego nie sprawdzono

- **Do dopracowania w następnej kolejności:** (1) cała **sekcja metadanych** (`model_meta`, dane per część, [MODEL_META.md](MODEL_META.md)); (2) **wycinanki na panelu** pod kątem elementów udających świecenie (podświetlone okna, lampy, powierzchnie `light_on`) – wycinanie, oznaczanie i eksport T3D (obecnie neutralne `light_on00` bez maski).
- **Eksport T3D nie był sprawdzony w samym symulatorze MaSzyna.** Format odtworzono z paczki przykładowej (domki, latarnie) i z kontroli automatycznych (kolejność wierzchołków,
  normalne, tangenty, układ plików). Do potwierdzenia w symulatorze: kierunek osi V tekstury, nazwy źródeł dymu przy kilku kominach, działanie `light_on00` bez maski okien, shader `normalmap_specgloss` z neutralnymi mapami.
- Połączenie z **żywym** Geoportalem i Nominatim było rozwijane na atrapie serwera; jeśli mapa jest pusta: Opcje → Testuj usługi.
- EGiB daje obrys i czasem liczbę kondygnacji; dach to uproszczony model (profil z generatora), nie LoD2.
- **ChatGPT nie gwarantuje** liczby okien, rozmiaru obrazu ani proporcji. Program wycina i skaluje to, co dostał; obraz ściany jest rozciągany na całą ścianę.
- Okna i drzwi nie są osobną geometrią (JSON z opisem otworów usunięto); światło (`emissive`, `light_on00`) dotyczy całej powierzchni.
- Kominy: prostopadłościany osiowe, bez ukośnych przejść z dachem; powielany fragment ściany ma widoczne szwy.
- Nie sprawdzono: import GLB/glTF w Blenderze i innych silnikach, działanie na Windows (ścieżki), zespoły z więcej niż 6 części.
- Współrzędne mapy to 32-bitowe `Vector2` (ok. 6 cm przy wartościach EPSG:2180); pozycjonowanie w metadanych liczone w podwójnej precyzji.

## 14. Testy automatyczne

```
godot --headless --path . --import
godot --headless --path . --script res://tools/selftest.gd      # 326 sprawdzeń, kod wyjścia 0 = OK
```
Obejmują m.in.: projekcję, ustawienia, wykrywanie ramek i sektorów, układ arkusza, generator promptu, profil dachu, dachy kopertowy i własny, kominy, eksport GLB/glTF, **eksport T3D**
(kolejność wierzchołków, normalne, LOD-y, TGA), **format `.mgdot`** (pakowanie, rozpakowanie, ochrona przed `../`, wersje formatu), nakładkę krawędzi. Atrapa Geoportalu: `tools/mock_geoportal.py` + `tools/e2e_mock.gd`.
Skrypty `tools/*_shot.gd` robią zrzuty ekranu (`SHOT_DIR=...`). Architektura: [ARCHITECTURE.md](ARCHITECTURE.md).
