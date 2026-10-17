# Photo-to-3D Studio v2 – dokumentacja dla testerów

Wersja: Studio v2 (Godot 4.6). Dokument opisuje, jak uruchomić program, jak przejść całą ścieżkę
„budynek z mapy → model 3D → tekstura z ChatGPT → eksport GLB” oraz co dokładnie sprawdzać podczas testów.

---

## 1. Do czego służy program

1. Wskazujesz budynek na mapie **Geoportal.gov.pl** (obrys z ewidencji EGiB + ortofotomapa).
2. Program buduje z obrysu bryłę 3D: ściany i **osobną bryłę dachu** (z okapem, grubością, spodem).
3. Generuje **prompt dla ChatGPT**, który ze zdjęć budynku robi jeden **arkusz tekstur** 4096 × 4096 (ramki o prawdziwych proporcjach ścian) i opis JSON
   (materiały, okna, drzwi).
4. Wczytujesz arkusz i opis; program tnie arkusz na panele, nakłada je na ściany i dach, pozwala poprawić każdą powierzchnię.
5. Eksportuje **GLB** (glTF) razem z **metadanymi** (kontrakt: `docs/MODEL_META.md`). Siatka to wizualizacja, opis jest w metadanych.

Dane: © GUGiK / Geoportal.gov.pl – sprawdź warunki usługi, zanim opublikujesz wyniki.

## 2. Wymagania i uruchomienie

- Godot **4.6** (standardowy, nie .NET): <https://godotengine.org/download>. Działa też na 4.3+, ale testowane na 4.6.3.
- Karta z Vulkan. Bez niej: `godot --rendering-method gl_compatibility`.
- Dostęp do internetu (Geoportal, wyszukiwarka miejsc Nominatim).

Uruchomienie: Godot → Project Manager → **Import** → `project.godot` → **Import & Edit** → **F5**.
Pierwsze otwarcie trwa chwilę (import grafik). Okno startuje na **pełnym ekranie**; **F11** przełącza pełny ekran.

## 3. Folder projektu

Przy starcie program prosi o **folder projektu** (jeden na budynek albo grupę budynków). Bez niego nie da się zbudować modelu.
W folderze są tylko ścieżki względne, więc można go przenosić i pakować.

```
<projekt>/
  project.json     stan: obrysy, ustawienia, tekstura, pozycja mapy, kamera, korekty powierzchni, opis GPT
  geo.txt / geo.json   dane z Geoportalu (atrybuty, obrysy w EPSG:2180, usługi, czas)
  geo/ortho.png    wycinek ortofotomapy wokół budynku
  texture/         kopia tekstury, <nazwa>.atlas.json (cięcie na regiony), prompt_gpt.txt, rectified/ (wyprostowane zdjęcia)
  renders/         lastView_<czas>.png – zapis widoku przy zamknięciu (domyślnie 3 ostatnie)
  exports/         <projekt>.glb i <projekt>.meta.json
  project.log      zdarzenia z czasem
```

„Projekt…” (góra panelu bocznego) przełącza projekty. Otwarcie projektu przywraca model, ustawienia, teksturę i mapę.
Ustawienia ogólne programu są w `user://photo_to_3d_settings.json`, cache Geoportalu w `user://geo_cache/`.

## 4. Układ ekranu

- Lewy **panel boczny** z pięcioma kartami: **1 Miejsce → 2 Budynek → 3 Tekstury → 4 Widok** oraz **⚙ Opcje**. Ukończony krok ma ✓.
  Karty **Budynek** i **Tekstury** są zablokowane, dopóki nie zbudujesz modelu. Pasek ← / → pod panelem przechodzi między krokami.
- Karta zaczyna się nagłówkiem i jednym zdaniem „co teraz robić”, potem podstawowe ustawienia, a rzadkie są pod przyciskiem
  **⚙ Zaawansowane…** (osobne okno z **Zapisz** / **Anuluj**; Anuluj przywraca wartości sprzed otwarcia okna).
- Zmienione względem domyślnych ustawienie ma pomarańczowe **↺** (klik = przywróć). Sekcje mają „Przywróć domyślne”.
- Pole **Szukaj ustawienia…** filtruje ustawienia ze wszystkich kart (ukryte w „Zaawansowane” pokazuje jako „⚙ Zaawansowane… (pasuje: n)”).
- Prawa strona: krok 1 pokazuje mapę, pozostałe kroki widok 3D. Na dole z prawej **przyciski widoków**: Góra / Przód / Tył / Lewo / Prawo
  (rzut prostopadły, ortogonalny) i **3D** (powrót do perspektywy).

### Sterowanie

| gest | mapa | widok 3D |
|---|---|---|
| lewy przycisk, przeciąganie | przesuwanie mapy | obrót kamery |
| kółko | zoom | zoom |
| **środkowy przycisk (rolka) przytrzymany** | – | **przesuwanie sceny** |
| klik (bez przeciągania) | wybór budynku (Ctrl/Shift + klik: dodaj/usuń część) | wybór ściany lub połaci dachu |
| `F11` | pełny ekran / okno | |
| `Esc` | zamknij okno / odznacz powierzchnię | |
| `Ctrl+Z`, `Ctrl+Y` | | cofnij / ponów korektę powierzchni |

W prawym dolnym rogu widoku 3D, obok przycisków widoków, są też **Dach…** (okno kąta i okapu dachu), **Kominy…** (generator kominów) i **✕ Zamknij**. Ostatni zapisuje projekt (jeśli jest otwarty: render, korekty, opis, kominy) i zamyka aplikację.

## 5. Krok 1 – Miejsce

Trzy karty:
1. **Szukaj miejsca** – wpisz miejscowość lub adres i Enter (Nominatim). Kliknięcie wyniku przenosi mapę. Historia **30 ostatnich**
   wyszukiwań (bez duplikatów); pusty Enter pokazuje historię.
2. **Współrzędne** – `szerokość, długość` (np. `52.2297, 21.0122`) i **Idź**.
3. **Zaznaczony budynek** – klik w budynek na mapie (obrysy widać od powiększenia ≤ 2 m/px). EGiB często tnie jeden budynek na kilka
   wielokątów: **Ctrl/Shift + klik** dodaje lub usuwa część, **+ Sąsiednie części** dodaje wszystkie stykające się. **Wyczyść** zeruje wybór.

Następnie **Zbuduj model 3D z zaznaczenia →**. Największy wielokąt to bryła główna, pozostałe to przybudówki (niższe ściany, dach
pulpitowy oparty o bryłę główną, wspólne ściany usunięte, drobne szpary sklejone).

Mapa: ortofotomapa i obrysy są cache’owane lokalnie (kafelki 512 px, komórki 400 m), zapytania idą przez kolejkę z ponawianiem przy 429/503.
Ustawienia: Opcje → „Geoportal: cache i limity zapytań”.

## 6. Krok 2 – Budynek

- **Ściany**: wysokość (ręcznie lub z liczby kondygnacji EGiB × wysokość kondygnacji).
- **Dach**: typ (dwuspadowy / płaski), wysokość ponad okap, wysunięcie poza ściany (okap), grubość dachu, kierunek kalenicy (wzdłuż dłuższego / krótszego boku).
- **Części budynku**: lista brył z osobną wysokością ścian, typem i wysokością dachu; ↺ = automat, ✕ = usuń część.
- **Kąt i okap dachu – okno…** – patrz niżej (6.1).
- **Kominy – generator…** – okno z rzutami (6.2).
- ⚙ Zaawansowane: proporcje dobudówek, dach pulpitowy dobudówek, tolerancja sklejania części, wyrównanie obrysu do osi.

### 6.1 Okno „Kąt i okap dachu”

Duże okno: zdjęcie szczytu (jeśli jest) z narysowanym dachem i pola liczbowe.
- **Niebieski uchwyt** na linii okapu (przerywana) – przeciągnij tam, gdzie na zdjęciu dach styka się ze ścianą: dopasowuje wysokość dachu do zdjęcia.
- **Pomarańczowy uchwyt kalenicy** – w górę / w dół zmienia **wysokość kalenicy** (też pole „Wysokość kalenicy nad ziemią”), przy asymetrii także w bok. Dzięki temu można „oszukać oko” dachem, gdy tekstura jest przesunięta.
- **Żółte końce linii dachu** – przeciągnij w bok: **wysunięcie dachu** poza ściany. Z asymetrią osobno lewa i prawa strona.
- **Dach asymetryczny** (checkbox) – odblokowuje pomarańczowy uchwyt **kalenicy** (w bok), przesunięcie kalenicy w metrach i niezależne **kąty lewej i prawej połaci**
  (przy stałej rozpiętości dwa kąty jednoznacznie wyznaczają wysokość i położenie kalenicy). Po odznaczeniu dach wraca do symetrycznego.
- **Okap lewy / prawy** i **wysunięcie przy szczytach** (można połączyć z okapem checkboxem „Szczyty wysunięte tak jak okap”).
- **Z tekstury** – wysokość z nachylenia widocznego na zdjęciu szczytu. **Zeruj asymetrię i okapy** – wartości domyślne.
- Kółko = zoom, środkowy przycisk = przesuwanie. Model za oknem zmienia się na żywo. **Zapisz** zatwierdza, **Anuluj** (lub Esc / ×) cofa wszystko.

Uwaga: trójkąt szczytu narysowany na teksturze zostaje na środku obrazu. Przy asymetrii ustaw kalenicę tak, by pokryła się z kalenicą na zdjęciu.
Ręczna zmiana wysokości wyłącza automatyczny kąt z tekstury (`Kąt dachu z tekstury`).

### 6.2 Okno „Kominy”

Generator kominów (**Budynek → Dach → Kominy – generator…** albo przycisk **Kominy…** przy widokach 3D). Okno ma trzy rzuty tego samego dachu i kominy ustawiane w każdym z nich:

- **Rzut z góry** – obrysy brył, przerywana pomarańczowa linia to kalenica. Kliknij w puste miejsce, żeby **postawić zaznaczony komin** w tym punkcie, albo
  złap go i przeciągnij. Komin automatycznie dostaje bryłę (główną lub dobudówkę), której dach jest pod jego środkiem.
- **Rzut z przodu (oś X poziomo)** i **rzut z boku (oś Z poziomo)** – sylwetka dachu (najwyższy punkt połaci w każdej kolumnie). **Przeciągnij korpus**,
  żeby przesunąć komin po dachu wzdłuż tej osi, albo **okrągły niebieski uchwyt na górze**, żeby zmienić wysokość. Dół komina wchodzi 30 cm pod najniższy punkt dachu
  pod nim, więc po stronie niżej położonej połaci nie ma szpary.
- Wymiary **z palca**: szerokość (oś X), długość (oś Z), **wysokość nad dachem** (liczona od najwyższego punktu połaci pod kominem, czyli od strony kalenicy) oraz
  położenie X i Z. Wysokość trzyma się, kiedy komin przesuwasz po dachu – wierzch podąża za połacią.
- **Betonowa czapka** (płyta 8 cm, wysunięta o 5 cm) – checkbox.
- **Tekstura korpusu**: wybierz obraz (domyślnie ściana długa arkusza, czyli S1) i **przeciągnij prostokąt** na jego podglądzie – ten fragment jest **powielany** na
  czterech ścianach komina. Rozmiar jednego powtórzenia wynika ze skali arkusza (px/m z promptu, bez niej 150 px/m) i suwaka „Wielkość fragmentu”. Wybierz gładki
  fragment cegły bez okna, bo szwy powtórzeń będą widoczne. Bez arkusza komin jest ceglany jednolity.
- Lista po lewej: **Dodaj komin**, **Powiel zaznaczony**, **Usuń zaznaczony**. Kółko myszy = zoom w danym rzucie.
- **Zapisz** zatwierdza, **Anuluj** (Esc, ×) przywraca stan sprzed otwarcia. Model za oknem zmienia się na żywo.

Kominy są zapisane w projekcie, widoczne razem z dachem (przełącznik „Pokaż dach”) i trafiają do GLB jako osobne węzły `chimney_<n>` z opisem w `extras.meta`
(`layer: "chimney"`, rozmiar, położenie, wysokość, patrz `docs/MODEL_META.md`). Komina nie da się kliknąć w widoku 3D jak ściany (korekty powierzchni go nie dotyczą).

![Okno kominów](img/chimney-editor.png)

## 7. Krok 3 – Tekstury

### 7.1 Przepływ pracy z ChatGPT (zalecany)

1. **0. Przygotuj arkusz tekstur (GPT) → Generuj prompt dla GPT…** Okno z pełnym promptem i przyciskiem **Kopiuj**; tekst zapisuje się też w
   `texture/prompt_gpt.txt`. Prompt zawiera dane budynku (obrys, wysokość ścian, dach), układ arkusza, wspólną skalę px/m i zasady.
2. W ChatGPT wklej prompt i **dołącz zdjęcia budynku** (każda ściana osobno, jeśli masz).
3. GPT odpowiada czterema częściami: spis przed rysowaniem, **obraz arkusza**, lista odstępstw, **blok JSON**.
4. Zapisz obraz, w programie wskaż go w **1. Źródło tekstury** (kopiuje się do projektu).
5. **Wklej opis od GPT (JSON)…** – okno z polem tekstowym (licznik znaków, „Wklej ze schowka”). Wklejasz całą odpowiedź albo sam blok JSON;
   program znajduje blok sam, sprawdza go i pokazuje wynik oraz ostrzeżenia w oknie.

**Układ arkusza** (kwadrat 4096 × 4096, liczony z wymiarów ścian budynku, nie stały):

| ramka | zawartość |
|---|---|
| S1, S2 | ściana długa A (frontowa) i B |
| S3, S4 | szczyt A i B (prostokąt do okapu + trójkąt szczytu, w rogach obok trójkąta szare tło) |
| S5 | dach – jedna połać widziana z góry |
| S6–S8 | ściany dobudówek (jeśli są) |

Program liczy dla każdej ściany ramkę o jej **prawdziwych proporcjach** (szerokość × wysokość w metrach razy jedna wspólna skala px/m), pakuje
ramki ciasno na płótnie (MaxRects) i wybiera **największe możliwe px/m**, przy którym wszystko się mieści – nic nie jest rozciągane, a puste miejsce
zamienia się w rozdzielczość. Szczyt dostaje prawie kwadratową ramkę, a nie sektor 2:1. Prompt podaje współrzędne i rozmiary ramek, a program rysuje też
**obraz-szablon** (`texture/szablon_arkusza.png`, przycisk „Pokaż obraz-szablon” w oknie promptu): czerwone ramki z numerami i kontur „domku” na szczytach.
Dołącz go do wiadomości dla GPT razem ze zdjęciami (na wyniku ramek nie może być). Układ zapisuje się w projekcie i po wczytaniu arkusz jest cięty po tych
ramkach; stary stały układ 2 × 4 sektory (2048 × 1024) nadal działa dla starych arkuszy.

Tło poza obrazami: neutralny szary #808080. Skala jest wspólna dla całego arkusza (px/m wpisana w prompcie).

**Opis JSON** (`geo3d_describe_v1`): dla S1–S5 `source` (`photo` / `inferred`), `photo_counts` (okna/drzwi na zdjęciu źródłowym), klasa materiału,
stan, kolor, lista `elements` (okno/drzwi/brama/witryna/kratka z prostokątem w ułamkach obrazu ściany i flagą `lit`). Program:
waliduje klasy (nieznane → `other`), pomija zepsute elementy z uwagą, **porównuje liczbę okien na zdjęciu z liczbą na arkuszu i ostrzega**, dociąga
prostokąty do krawędzi na obrazie, ustawia chropowatość/metaliczność/połysk z własnej tabeli klas.

### 7.2 Jak program nakłada arkusz

- Arkusz jest **cięty automatycznie** na panele (analiza kolorów + rozdzielanie paneli, które się stykają). Tryb: Tekstury → ⚙ Cięcie arkusza →
  *Automatycznie / Szablon 4096 (ramki S1–S8) / Zawsze tnij na panele / Jedna tekstura*. Podgląd: **Podgląd cięcia na regiony…**; wynik w `<nazwa>.atlas.json`
  (można poprawić ręcznie, **Przeanalizuj obraz ponownie** robi cięcie od nowa).
- Z każdego panelu odcinane są piksele z brzegów (4 px przy arkuszu ~1250 px, 7 px przy 4096) – to rozmyty styk z szarym tłem, który dawał szwy.
- **Wysokość ścian z zdjęcia** (Tekstury → Dach ze zdjęcia szczytu → „Wysokość ścian z proporcji zdjęcia”, domyślnie włączone dla arkusza z szablonu): wysokość = długość ściany / proporcje panelu S1. Ewidencja zna tylko przybliżoną liczbę kondygnacji i często zaniża wysokość. Ręczna zmiana wysokości ścian wyłącza opcję; przycisk „Dopasuj wysokość ścian do proporcji tekstury” (Budynek) włącza ją ponownie.
- **Prompt a proporcje**: prompt podaje GPT dokładne *szerokości* paneli, a *wysokości* tylko orientacyjnie – proporcje ma wziąć ze zdjęcia ściany. Ramki mają 30 % zapasu na wyższą ścianę; wysokość w ramce to maksimum, a niewykorzystane miejsce zostaje szare.
- **Skala okien**: prompt wymaga, by to samo okno miało tyle samo pikseli na wszystkich ścianach (wspólna miara: odcinek od górnej krawędzi cokołu do pierwszego pasa cegły) i zabrania skalowania okien według wysokości szczytu lub kalenicy.
- **Obraz ściany pokrywa całą ścianę** (cały panel na całą ścianę, bez ukrytego powtarzania i przycinania). Powtarzanie powstaje tylko z korekty powierzchni
  (skala poniżej 100 %) albo gdy w trybie zwykłej biblioteki włączysz „Zachowaj proporcje”.
- **Dach z S5** jest kładziony raz na całą połać; obraz zaczyna się na zewnętrznej krawędzi okapu, więc leży dokładnie na 0–100% (wcześniej pas wysunięcia dachu zawijał górną część obrazu). Inny panel dachu (nie z szablonu) też jest kładziony raz, jeśli przy skali arkusza (px/m) obejmuje co najmniej połowę połaci; mały wycinek dachówek jest powielany z szerokością kafla dachu. Przy zwykłym zdjęciu dachu (nie z arkusza) dachówka kafelkuje w proporcjach obrazu (Szerokość kafla dachu, obrót 90°).
- Skala px/m (Tekstury → Źródło) jest informacją dla promptu, metadanych i kafelkowania dachu; ściany jej nie używają.

### 7.3 Inne źródła tekstur

- Zwykłe zdjęcie → jedna tekstura. Własny atlas: skopiuj `textures/atlas_wroniawy.json` i opisz regiony (`role`, `rect`).
- **Biblioteka zdjęć**: każde zdjęcie (PNG/JPG/WebP) w folderze biblioteki to osobna tekstura (rola z nazwy: dach/szczyt/drzwi/okno, inaczej elewacja);
  „Dodaj zdjęcia do biblioteki…”, „Jedna tekstura na wszystkie ściany”, „Losuj tekstury”.
- **Wybierz z podglądem…** – własna przeglądarka plików z miniaturami.
- **Dobór na ściany i dach**: osobno długa A/B, szczyt A/B, dach, wariant.
- **Relief**: mapa normalnych (opcjonalnie parallax) z jasności zdjęcia; siła osobno dla ścian i dachu, wielkość detalu, wygładzenie, odwrócenie.
  Chropowatość materiału: Tekstury → Materiał. *Eksportuj mapy normalnych* zapisuje albedo + normal PNG.

## 8. Korekta pojedynczej powierzchni

W widoku 3D **kliknij ścianę lub połać dachu** (bez przeciągania). Zaznaczenie: żółty obrys + błękitna nakładka; po prawej otwiera się panel
(w nagłówku podgląd – które miejsce zdjęcia leży na tej ścianie, z zaznaczonymi oknami/drzwiami z opisu GPT). Wszystko działa na żywo i zapisuje się w projekcie.

Karty panelu:
- **Mapowanie** – przesunięcie (m), skala szerokości/wysokości (razem lub osobno), obrót, odbicia, „Zeruj mapowanie tej powierzchni”.
  Strzałki ◀ ▶ = stały krok, z Shiftem 10×.
- **Kawałek** – inny panel z arkusza albo wycięty z niego kawałek, który powiela się na powierzchni.
- **Materiał** – kolor (mnoży się ze zdjęciem), chropowatość, połysk, metaliczność, siła reliefu, pole **Świeci** (flaga `emissive_light`).
- **Bryła** – podniesienie/opuszczenie okapu razem z dachem, zmiana samej kalenicy, przesunięcie okapu przy stałej kalenicy (krok 1 dm, Shift = 5 dm).
- **Edytor mapowania – całe okno…** – patrz niżej.

`Esc` lub klik w puste miejsce odznacza. `Ctrl+Z` / `Ctrl+Y` cofają i ponawiają. Po zbudowaniu innego budynku korekty są zerowane (należą do konkretnego obrysu).
Identyfikatory: `p<bryła>:w<krawędź>` (ściana), `p<bryła>:roofA|roofB` (połać).

### 8.1 Edytor mapowania (całe okno)

Jak „Unwrap UVW” w 3ds Max, dla jednej powierzchni. Lista **Obraz** wybiera panel z arkusza.
- **Wycinek** – cały obraz jest widoczny, ramka to fragment kładziony na powierzchnię. Przeciągasz narożniki, krawędzie albo całą ramkę. „Cały obraz”, „Dopasuj widok”.
- **Prostowanie zdjęcia** – cztery narożniki stawiasz na prawdziwym zdjęciu ściany w perspektywie; „Prostuj” wycina płaski obraz (zapis w `texture/rectified/`) i używa go na powierzchni.
- Kółko = zoom, środkowy przycisk = przesuwanie widoku. **Zapisz** zachowuje, **Anuluj** przywraca stan sprzed otwarcia.

## 9. Krok 4 – Widok i eksport

- **Co pokazać**: elewacje, dach, podłoże, siatka pomocnicza, siatka krawędzi (diagnostyka).
- **Światło i tło**: wysokość i kierunek słońca, jasność (domyślnie 1,0), światło otoczenia (domyślnie 0,5), kolor tła. **Kamera**: obrót, odległość, widoki.
- **Eksport modelu do GLB**: `exports/<projekt>.glb` (Y w górę, metry) + `<projekt>.meta.json`. **Otwórz folder eksportów**.
  Siatka niesie wizualizację, opis (typ, piętra, wysokość, dach, położenie w EPSG:2180, części świecące, materiały, otwory, przy asymetrii `ridge_shift` i `roof_angles`)
  jest w `extras.meta` węzłów. Szczegóły: `docs/MODEL_META.md` (wersja robocza do przeglądu przez zespół). T3D/E3D powstają z GLB w osobnym potoku.

## 10. Opcje

Rozmiar czcionki, start na pełnym ekranie, zapis/reset ustawień, adresy usług Geoportalu i Nominatim, **Testuj usługi**, cache (ważność, rozmiar, równoległość,
odstęp, „Wyczyść cache”), **Zapisz render teraz**, **Otwórz folder projektu**. Źródło GeoJSON: import własnego obrysu (`properties.wall_height` / `roof_height` opcjonalne;
próbki w `samples/`).

## 11. Scenariusz testowy (około 20 minut)

1. Start: okno pełnoekranowe, brak modelu, karty Budynek i Tekstury zablokowane, F11 działa.
2. Wskaż folder projektu. Wyszukaj miejsce (np. „Wolsztyn”), potwierdź wpis w historii.
3. Przybliż mapę, kliknij budynek, dodaj sąsiednie części. Zbuduj model. Sprawdź, że karty się odblokowały.
4. Obróć model, zoomuj, **przesuń scenę środkowym przyciskiem**, użyj przycisków widoków (Góra, Przód…) i „3D”.
5. Budynek: zmień wysokość ścian i dachu, okap; otwórz **Kąt i okap dachu**, przeciągnij uchwyty, włącz asymetrię, Anuluj (wraca), potem Zapisz.
5a. Kominy: otwórz **Kominy – generator**, dodaj komin, wpisz wymiary, ustaw go w rzucie z góry, przesuń w rzucie z boku, zmień wysokość uchwytem, wybierz fragment ściany, Anuluj (wraca), Zapisz.
6. Tekstury: wygeneruj prompt, skopiuj, sprawdź `texture/prompt_gpt.txt`. Wykonaj arkusz w ChatGPT, wczytaj, sprawdź **Podgląd cięcia** (S1–S5 rozpoznane).
7. Wklej JSON: sprawdź komunikaty (liczba okien, ostrzeżenia), działa też dla pustego pola i uszkodzonego JSON.
8. Kliknij ścianę: przesuń/skaluj, zmień panel, otwórz edytor mapowania (Wycinek, Prostowanie), Ctrl+Z/Y.
9. Eksport GLB: otwórz w Blenderze (oś Y w górę), zajrzyj w `extras.meta` i `.meta.json`.
10. Zamknij aplikację przyciskiem **✕ Zamknij** w widoku 3D i otwórz projekt ponownie: model, tekstura, korekty, kominy i widok wracają.

**Co zgłaszać**: kroki do odtworzenia, zrzut ekranu, `project.log` z folderu projektu, plik arkusza, jeśli problem dotyczy cięcia lub nakładania tekstury.

## 12. Znane ograniczenia

- Połączenie z **żywym** Geoportalem i Nominatim nie było testowane w środowisku, w którym powstawał program (tylko atrapa serwera). Jeśli mapa zostaje pusta:
  Opcje → Testuj usługi i popraw nazwy warstw / typów. Klient próbuje obu kolejności osi EPSG:2180.
- EGiB daje obrys i czasem liczbę kondygnacji, więc dach to uproszczony dwuspadowy lub płaski, nie LoD2.
- **ChatGPT nie gwarantuje** liczby okien ani ich rozmieszczenia, rozmiaru obrazu (często oddaje 1254 px zamiast 4096) ani proporcji paneli. Program ostrzega o rozjechaniu
  liczby okien, ale tego nie naprawia; obraz ściany jest rozciągany na całą ścianę.
- Czarny pasek dachu narysowany przez GPT na szczytach S3/S4 zostaje w teksturze.
- Światło (`emissive_light`) jest oznaczane na całą powierzchnię, nie na samo okno; osobna geometria okien nie jest zrobiona.
- Okna i drzwi z opisu GPT są w metadanych i w podglądzie panelu, nie jako osobna geometria. `wall_rect_m` jest przybliżone.
- Trójkąt szczytu w teksturze nie podąża za przesuniętą kalenicą dachu asymetrycznego.
- Kominy: prostopadłościany ustawione osiowo (bez obrotu), bez ukośnych przejść z dachem i bez kołnierzy z blachy; powielany fragment ściany ma widoczne szwy powtórzeń.
- Nie sprawdzono: import GLB w Blenderze i programie świata, działanie na Windows (ścieżki), duże zespoły brył (> 6 części).
- Współrzędne mapy to 32-bitowe `Vector2` (ok. 6 cm przy wartościach EPSG:2180) – wystarcza do obrysów; pozycjonowanie w meta liczone w podwójnej precyzji.

## 13. Testy automatyczne (dla developerów)

```
godot --headless --path . --import
godot --headless --path . --script res://tools/selftest.gd          # 265 sprawdzenia, kod wyjścia 0 = OK
python3 tools/mock_geoportal.py &                                    # atrapa WMS/WFS na :8765
xvfb-run -a godot --path . --rendering-method gl_compatibility --script res://tools/e2e_mock.gd
```
Skrypty `tools/*_shot.gd` robią zrzuty ekranu (`SHOT_DIR=...`). Architektura: `docs/ARCHITECTURE.md`.
