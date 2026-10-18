class_name GptPrompt
extends RefCounted
## Builds the text for ChatGPT that turns reference photos into ONE texture sheet for the model.
## The layout is computed from the size of the walls (SheetLayout): every picture gets a frame with the true
## proportions of its wall, all frames share one scale (px per metre) and are packed on the 4096 x 4096 canvas.
## Dimensions come from the EGiB footprint.
##
## info: {
##   "name": String, "place": String,
##   "floors": int, "kind": String (EGiB code or ""), "roof": "gable"|"flat"|"shed",
##   "main": {"len": m (along the ridge / long side), "wid": m, "wall_h": m, "roof_h": m},
##   "annexes": [{"len": m, "wid": m, "wall_h": m}],
## }

const HEADROOM := 1.3     # walls from the register are often too low: the frame is this much taller than the register says


## Elements of the sheet as [code, width m, height m] (register values, no headroom).
static func elements(info: Dictionary) -> Array:
	var main: Dictionary = info.get("main", {})
	var len_m := float(main.get("len", 10.0))
	var wid_m := float(main.get("wid", 6.0))
	var wall_h := float(main.get("wall_h", 3.0))
	var roof_h := float(main.get("roof_h", 0.0))
	var gable_h := wall_h + (roof_h if str(info.get("roof", "gable")) == "gable" else 0.0)
	var out: Array = [["S1", len_m, wall_h], ["S2", len_m, wall_h], ["S3", wid_m, gable_h], ["S4", wid_m, gable_h],
		["S5", len_m, _slope(info)]]
	var idx := 6
	for a in info.get("annexes", []):
		if idx > 8:
			break
		out.append(["S%d" % idx, float(a.get("len", 4.0)), float(a.get("wall_h", 3.0))])
		idx += 1
	return out


## Elements for the layout: [code, width m, frame height m, kind, eave height m].
static func layout_elems(info: Dictionary) -> Array:
	var main: Dictionary = info.get("main", {})
	var len_m := float(main.get("len", 10.0))
	var wid_m := float(main.get("wid", 6.0))
	var wall_h := float(main.get("wall_h", 3.0)) * HEADROOM
	var roof_h := float(main.get("roof_h", 0.0))
	var gable := str(info.get("roof", "gable")) == "gable"
	var out: Array = [["S1", len_m, wall_h, "wall"], ["S2", len_m, wall_h, "wall"]]
	if gable:
		out.append(["S3", wid_m, wall_h + roof_h, "gable", wall_h])
		out.append(["S4", wid_m, wall_h + roof_h, "gable", wall_h])
	else:
		out.append(["S3", wid_m, wall_h, "wall"])
		out.append(["S4", wid_m, wall_h, "wall"])
	out.append(["S5", len_m, _slope(info), "roof"])
	var idx := 6
	for a in info.get("annexes", []):
		if idx > 8:
			break
		out.append(["S%d" % idx, float(a.get("len", 4.0)), float(a.get("wall_h", 3.0)) * HEADROOM, "wall"])
		idx += 1
	return out


static func layout(info: Dictionary) -> Dictionary:
	return SheetLayout.compute(layout_elems(info))


static func _slope(info: Dictionary) -> float:
	var main: Dictionary = info.get("main", {})
	var wid_m := float(main.get("wid", 6.0))
	if str(info.get("roof", "gable")) != "gable":
		return wid_m
	return sqrt(pow(wid_m * 0.5, 2.0) + pow(float(main.get("roof_h", 0.0)), 2.0))


## One scale for the whole sheet: the largest whole number of px per metre at which all frames still fit the canvas.
static func scale_px_per_m(info: Dictionary) -> int:
	return maxi(int(layout(info)["ppm"]), 1)


static func _frame_line(code: String, title: String, lay: Dictionary, extra := "") -> String:
	var f: Array = lay["pictures"][code]
	return "- %s – ramka %s – %s: szerokość obrazu w ramce DOKŁADNIE %d px, wysokość najwyżej %d px.%s" % [
		code, TagSheet.TAG_NAMES.get(code, "?"), title, int(f[2]), int(f[3]), extra]


static func build(info: Dictionary) -> String:
	var main: Dictionary = info.get("main", {})
	var len_m := float(main.get("len", 10.0))
	var wid_m := float(main.get("wid", 6.0))
	var wall_h := float(main.get("wall_h", 3.0))
	var roof_h := float(main.get("roof_h", 0.0))
	var roof_kind := str(info.get("roof", "gable"))
	var annexes: Array = info.get("annexes", [])
	var lay := layout(info)
	var ppm := int(lay["ppm"])

	var l: Array[String] = []
	l.append("Zrób z załączonych zdjęć JEDEN arkusz tekstur budynku do modelu 3D. Wynik: obraz kwadratowy 4096 × 4096 px, każdy element w kolorowej ramce-tagu.")
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
			l.append("- dach dwuspadowy, wzniesienie kalenicy %.1f m nad okapem, kalenica wzdłuż boku %.1f m (ściany równoległe do kalenicy = „długie”)" % [roof_h, len_m])
	if not annexes.is_empty():
		l.append("- dobudówki: %d" % annexes.size())
	if str(info.get("kind", "")) != "":
		l.append("- rodzaj wg ewidencji (KST): %s" % info["kind"])
	l.append("")
	l.append("UKŁAD ARKUSZA – RAMKI-TAGI (najważniejsze)")
	l.append("Płótno 4096 × 4096 px, tło jednolity szary #808080. Obrazy mogą leżeć w DOWOLNYM miejscu, w dowolnej kolejności – program sam je wytnie i ułoży. Ale KAŻDY obraz musi mieć wokół siebie ramkę-tag: ciągłą, jednolitą linię o grubości 16 px, w przypisanym mu kolorze, ułożoną dokładnie na krawędziach prostokątnego kadru obrazu (cały prostokąt, także przy szczycie z szarymi rogami). Kolor mówi, CO to za obraz, ramka mówi, GDZIE jest. Kolory są czyste, bez gradientu, cienia i wygładzania (#FF0000 itd.), nie używaj ich nigdzie indziej na obrazie. Wewnątrz ramki jest tylko obraz, bez opisów i numerów. Obrazy nie nachodzą na siebie i nie dotykają się (zostaw min. 40 px odstępu).")
	l.append("SKALA: cały arkusz ma JEDNĄ skalę – 1 m rzeczywistej ściany = %d px. Szerokości w ramkach podano w pikselach tej skali. Wysokość to tylko maksimum (ewidencja zaniża wysokość ścian): rysuj ścianę w jej prawdziwych proporcjach ze zdjęcia, od ziemi do okapu, i NIE rozciągaj obrazu. Ramka obejmuje dokładnie obraz ściany, bez zapasu." % ppm)
	l.append(_frame_line("S1", "ściana długa A (frontowa, ze wszystkimi drzwiami i oknami widocznymi na zdjęciach)", lay))
	l.append(_frame_line("S2", "ściana długa B (przeciwna do S1; jeśli nie ma jej zdjęcia, wywnioskuj ją według zasady 8)", lay))
	var gable_extra := ""
	if roof_kind == "gable":
		var eave_px := int(lay["eave_px"].get("S3", 0))
		gable_extra = " Ramka obejmuje cały prostokąt kadru. Kontur ma kształt „domku”: prostokąt ściany (do okapu, ok. %d px od dołu) i trójkąt szczytu nad nim aż do wierzchołka na środku. Dwa rogi obok trójkąta zostaw szare (tło). Bez komina i bez kawałka połaci dachu poza krawędzią." % eave_px
	l.append(_frame_line("S3", "ściana szczytowa A", lay, gable_extra))
	l.append(_frame_line("S4", "ściana szczytowa B", lay, gable_extra))
	var slope := _slope(info)
	l.append(_frame_line("S5", "dach (jedna połać pokrycia widziana wprost z góry, %.1f m wzdłuż kalenicy × %.1f m w dół połaci; sama faktura, bez kalenicy, komina i cieni)" % [len_m, slope], lay))
	var idx := 6
	for a in annexes:
		if idx > 8:
			break
		l.append(_frame_line("S%d" % idx, "ściana dobudówki", lay))
		idx += 1
	l.append("Pozostałe miejsce na płótnie zostaw szare. Każdy z obrazów S1…S%d ma pojawić się dokładnie raz, w swojej ramce." % (5 + mini(annexes.size(), 3)))
	l.append("")
	l.append("ZADANIE – to jest fototekstura, nie rysunek")
	l.append("Jeśli na zdjęciu widać CAŁĄ ścianę, POPRAW tę ścianę, zamiast rysować nową: wyprostuj perspektywę, usuń to, co ją zasłania, uzupełnij braki. Okna, drzwi, ich LICZBA i ROZSTAW, kolory, gzymsy, pęknięcia i zabrudzenia mają zostać takie, jakie są na zdjęciu. Wymyślaj wyłącznie tam, gdzie zdjęcia ściany brakuje.")
	l.append("")
	l.append("SKALA OKIEN I DETALI – najważniejsza zasada")
	l.append("Ta sama stolarka ma tę samą wielkość w pikselach na WSZYSTKICH ścianach: okno na szczycie ma tyle samo pikseli co takie samo okno na ścianie długiej, cegła tyle samo co cegła. Wspólną miarą jest odcinek od górnej krawędzi cokołu (jeśli jest) do pierwszego poziomego pasa z cegły lub gzymsu – na każdej ścianie ma mieć tyle samo pikseli. NIGDY nie skaluj okien ani cegieł według wysokości całego szczytu, kalenicy ani wysokości ramki. Trójkąt szczytu to osobny kształt nad okapem i nie ma wpływu na skalę okien.")
	l.append("")
	l.append("KROK 0 – SPIS PRZED RYSOWANIEM (napisz go tekstem, zanim wygenerujesz obraz)")
	l.append("Dla każdego zdjęcia podaj: którą ścianę przedstawia (S1…), ile kondygnacji, ile okien w każdym rzędzie (np. „2 rzędy po 4 okna”), ile drzwi, jakie gzymsy, pasy z cegły (na jakiej wysokości od ziemi), cokół, narożniki. Dla S1 i dla szczytu podaj też w pikselach arkusza: wysokość okna, odcinek cokół → pierwszy pas (jeśli są) – na obu ścianach mają się zgadzać. Jeśli nie da się ich ustalić albo nie umiesz zachować liczby i rozstawu okien, napisz to wprost zamiast cicho zgadywać. Potem rysuj tak, żeby arkusz zgadzał się ze spisem.")
	l.append("")
	l.append("ZASADY")
	l.append("1. Każdy obraz to płaskie, frontalne zdjęcie bez perspektywy (jakby zrobione teleobiektywem na wprost), krawędzie pionowe i poziome.")
	l.append("2. Tło poza obrazami: jednolity szary #808080, bez gradientu i cienia. Ramki-tagi są jedynym kolorowym elementem poza zdjęciami.")
	l.append("3. Usuń: niebo, trawę, ludzi, samochody, drzewa, krzaki przed ścianą, napisy i znaki wodne. Uzupełnij tynk lub cegłę tam, gdzie coś zasłaniało. Okna, drzwi, gzyms i cokół zostają w ścianie – nie wydzielaj ich.")
	l.append("4. Ściana kończy się na linii okapu: BEZ dachu, dachówek, kominów, rynien, rur spustowych i nieba nad nią (S1, S2, dobudówki). Cokół zostaje. Szczyt kończy się na krawędzi dachu.")
	l.append("5. Poza ramkami-tagami nie dodawaj żadnych opisów, numerów, strzałek ani legendy.")
	l.append("6. Elementy, które SĄ na zdjęciu (pas z cegły, gzyms, cokół, narożniki), przeprowadź przez całą szerokość ściany bez przerw, na tej samej wysokości i o tej samej grubości. NIGDY nie dodawaj tego, czego nie ma na zdjęciu: nowych pasów, wiązań, podziałów pól ani okien.")
	l.append("7. Dach (S5): sama faktura pokrycia, powtarzalna, równomierna.")
	l.append("8. Jeśli brakuje zdjęcia jakiejś ściany, wywnioskuj ją ze stylu pozostałych, ale TYLKO materiał, kolor i ogólny charakter. Okna dodaj tam, gdzie wynikają z reszty budynku, i oznacz sektor w JSON jako „inferred”.")
	var used: Array = []
	for e in elements(info):
		used.append(e[0])
	l.append("9. Odpowiedź ma CZTERY części w tej kolejności: (0) spis przed rysowaniem, (1) obraz arkusza, (2) krótka lista odstępstw od zdjęć (albo „brak”), (3) opis JSON tego obrazu (niżej). Wszystko w jednej wiadomości.")
	l.append(GptDescribe.prompt_section(used))
	return "\n".join(l)
