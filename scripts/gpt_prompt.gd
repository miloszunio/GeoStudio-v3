class_name GptPrompt
extends RefCounted
## Text for ChatGPT that turns reference photos into phototextures of every visible side of the building.
## ChatGPT does what it is good at (rectify, clean, even out the light) and marks each picture with a thin red frame
## and a code; WHERE and HOW BIG the pictures lie on the canvas does not matter - the program cuts them out along the
## frames and lays them out by the real wall sizes itself (PanelFrames, PanelSheet).
##
## info: {
##   "name": String, "place": String,
##   "floors": int, "kind": String (EGiB code or ""), "roof": "gable"|"flat"|"shed",
##   "main": {"len": m (along the ridge / long side), "wid": m, "wall_h": m, "roof_h": m},
##   "annexes": [{"len": m, "wall_h": m}],
## }


## Codes that may appear for this building.
static func codes(info: Dictionary) -> Array:
	return PanelSheet.expected(info).keys()


static func build(info: Dictionary) -> String:
	var main: Dictionary = info.get("main", {})
	var len_m := float(main.get("len", 10.0))
	var wid_m := float(main.get("wid", 6.0))
	var wall_h := float(main.get("wall_h", 3.0))
	var roof_h := float(main.get("roof_h", 0.0))
	var roof_kind := str(info.get("roof", "gable"))
	var annexes: Array = info.get("annexes", [])
	var gable := roof_kind == "gable"
	# one scale for the whole sheet: 112 px/m unless the long wall would not fit its 2048 px sector
	var ppm := floorf(minf(112.0, 2016.0 / maxf(len_m, 1.0)))
	ppm = clampf(ppm, 40.0, 112.0)
	var gable_h := wall_h + (roof_h if gable else 0.0)
	var slope := sqrt(pow(wid_m * 0.5, 2.0) + roof_h * roof_h) if gable else wid_m

	var l: Array[String] = []
	l.append("NIE ZGUB ŻADNEJ ŚCIANY, DOKONAJ TAKIEJ ANALIZY ŻEBY NIC NIE PRZEOCZYĆ")
	l.append("Zrób z załączonych zdjęć JEDEN arkusz tekstur budynku do modelu 3D. Wynik: obraz kwadratowy 4096 × 4096 px.")
	l.append("")
	l.append("BUDYNEK (dane z ewidencji gruntów i budynków)")
	if str(info.get("name", "")) != "":
		l.append("- nazwa projektu: %s" % info["name"])
	if str(info.get("place", "")) != "":
		l.append("- położenie: %s" % info["place"])
	l.append("- obrys głównej bryły: %.1f × %.1f m, wysokość ścian do okapu wg ewidencji %.1f m (bywa zaniżona)%s" % [
		len_m, wid_m, wall_h, (", kondygnacje nadziemne: %d" % int(info["floors"])) if int(info.get("floors", 0)) > 0 else ""])
	match roof_kind:
		"flat":
			l.append("- dach płaski")
		"shed":
			l.append("- dach pulpitowy")
		_:
			l.append("- dach dwuspadowy, wzniesienie kalenicy %.1f m nad okapem, kalenica biegnie wzdłuż boku %.1f m" % [roof_h, len_m])
	l.append("- ściany długie (równoległe do kalenicy) mają ok. %.1f m szerokości, szczytowe ok. %.1f m (długa : szczytowa ≈ %.1f : %.1f)" % [len_m, wid_m, len_m, wid_m])
	if not annexes.is_empty():
		var parts: Array[String] = []
		for a in annexes:
			parts.append("%.1f m" % float(a.get("len", 4.0)))
		l.append("- dobudówki: %d (długości ścian ok. %s)" % [annexes.size(), ", ".join(PackedStringArray(parts))])
	if str(info.get("kind", "")) != "":
		l.append("- rodzaj wg ewidencji (KST): %s" % info["kind"])
	l.append("")
	l.append("UKŁAD ARKUSZA – płótno 4096 × 4096 px podzielone na 8 sektorów po 2048 × 1024 px (2 kolumny, 4 rzędy). W każdym sektorze JEDEN element, nic poza tym. Numeracja: rzędami od lewej do prawej, od góry.")
	l.append("SKALA: w całym arkuszu 1 m rzeczywistej ściany = %d px. Rozmiary elementów w pikselach podano niżej – trzymaj się ich dokładnie, nie dopasowuj elementów do sektora." % int(ppm))
	l.append("- S1 – ściana długa A (frontowa, ze wszystkimi drzwiami i oknami widocznymi na zdjęciach): szerokość %.1f m = %d px, wysokość do linii okapu wg zdjęć (ewidencja %.1f m ≈ %d px, bywa zaniżona); umieść w lewym górnym rogu sektora, 16 px od krawędzi." % [len_m, int(len_m * ppm), wall_h, int(wall_h * ppm)])
	l.append("- S2 – ściana długa B (przeciwna do S1; jeśli nie ma jej zdjęcia, wywnioskuj ją ze S1 według zasady 7 – nie wymyślaj nowego układu okien): szerokość %.1f m = %d px, ta sama wysokość co S1; umieść w lewym górnym rogu sektora, 16 px od krawędzi." % [len_m, int(len_m * ppm)])
	if gable:
		l.append("- S3 – ściana szczytowa A: szerokość %.1f m = %d px, wysokość do kalenicy ok. %.1f m ≈ %d px; umieść w lewym górnym rogu sektora, 16 px od krawędzi. Kontur ściany to prostokąt z trójkątnym szczytem dachu na górze; poza konturem tło." % [wid_m, int(wid_m * ppm), gable_h, int(gable_h * ppm)])
		l.append("- S4 – ściana szczytowa B: jak S3; umieść w lewym górnym rogu sektora, 16 px od krawędzi. Kontur ściany to prostokąt z trójkątnym szczytem dachu na górze; poza konturem tło.")
	else:
		l.append("- S3 – ściana krótka A: szerokość %.1f m = %d px; umieść w lewym górnym rogu sektora, 16 px od krawędzi." % [wid_m, int(wid_m * ppm)])
		l.append("- S4 – ściana krótka B: jak S3; umieść w lewym górnym rogu sektora, 16 px od krawędzi.")
	l.append("- S5 – dach: jedna połać pokrycia dachowego widziana wprost z góry bez kalenicy, bez komina, bez cieni (ok. %.1f m × %.1f m = %d × %d px)." % [len_m, slope, int(len_m * ppm), int(slope * ppm)])
	l.append("- S6 – Ściana której nie umiesz zdefiniować (dobudówka, przybudówka, każda inna widoczna ściana; w skali %d px/m)" % int(ppm))
	l.append("- S7 – Ściana której nie umiesz zdefiniować")
	l.append("- S8 – Ściana której nie umiesz zdefiniować")
	l.append("")
	l.append("ZASADA NADRZĘDNA – to jest fototekstura, nie rysunek")
	l.append("Jeśli na zdjęciu widać CAŁĄ ścianę, POPRAW tę ścianę, zamiast rysować nową: wyprostuj perspektywę, usuń to, co ją zasłania (patrz zasada 4), uzupełnij braki. Okna, drzwi, ich LICZBA i ROZSTAW, kolory, gzymsy, pęknięcia i zabrudzenia mają zostać dokładnie takie, jakie są na zdjęciu. Nie dodawaj okien, nie usuwaj ich i nie przestawiaj. Wymyślaj wyłącznie tam, gdzie zdjęcia ściany brakuje. Nie zmieniaj geometrii ściany zwłaszcza wzdłuż okapów dachowych.")
	l.append("")
	l.append("KROK 0 – SPIS PRZED RYSOWANIEM (napisz go tekstem, zanim wygenerujesz obraz)")
	l.append("Dla każdego zdjęcia podaj: którą ścianę przedstawia (S1…), ile kondygnacji, ile okien w każdym rzędzie (np. „2 rzędy po 4 okna”), ile drzwi, jakie gzymsy, pasy, cokół, ozdoby. Potem rysuj tak, żeby arkusz się z tym spisem zgadzał.")
	l.append("")
	l.append("ZASADY")
	l.append("1. Każdy element to płaskie, frontalne zdjęcie bez perspektywy (jakby zrobione teleobiektywem na wprost, krawędzie pionowe i poziome), bez zbieżności linii.")
	l.append("2. Zachowaj dokładnie podane rozmiary i proporcje – nie rozciągaj ani nie ściskaj. Skala jest jedna dla całego arkusza: te same okna i cegły mają ten sam rozmiar na wszystkich ścianach.")
	l.append("3. Tło poza elementami: jednolity neutralny szary (#808080), bez gradientu, bez cienia. Między elementem a krawędzią sektora zostaw co najmniej 16 px tła.")
	l.append("4. Usuń z elementów: niebo, trawę, ludzi, samochody, drzewa, rynny z cieniem, krzaki przed ścianą, napisy i znaki wodne. Uzupełnij tynk/cegłę tam, gdzie coś zasłaniało. Zostaw okna, drzwi, gzyms, cokół i podobne elementy ściany – nie wydzielaj ich osobno.")
	l.append("5. Nie dodawaj żadnych opisów, numerów sektorów ani legendy na obrazie.")
	l.append("5a. Ściana kończy się na linii okapu: bez paska dachu, bez dachówek, bez nieba nad nią. Cokół i fundament zostają. Szczyt (S3, S4) kończy się na krawędzi dachu.")
	l.append("6. Dach: sama faktura pokrycia, powtarzalna, równomierna, bez śladów kalenicy i krawędzi.")
	l.append("7. Jeśli na zdjęciach brakuje jakiejś ściany to jej nie wymyślaj, zostaw puste pole.")
	l.append("")
	l.append("Wokół każdej gotowej płaszczyzny dodaj prostokąt o szerokości linii 2px")
	return "\n".join(l)
