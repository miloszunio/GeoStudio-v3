class_name RoofCustom
extends RefCounted
## "Własny" roof: every edge of the outline gets a slope angle (the arrow drawn in the top view) or is a gable wall.
## The roof surface is the lower envelope of the planes that rise inward from the eaves line of each sloped edge,
## which is how a hip ("kopertowy"), a gable, a pyramid or a half-hip roof is made from one rule.
## Stored as {"slopes": [deg or -1 per outline edge], "cap": m} (hidden setting `model_roof_custom`).
## Edges that run along a reflex corner (a concave outline) are skipped: a plane from them would cut the roof.

const LETTERS := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
const MAX_DEG := 85.0
const MIN_DEG := 5.0


static func parse(text: String) -> Dictionary:
	var d = JSON.parse_string(text) if text.strip_edges() != "" else null
	if typeof(d) != TYPE_DICTIONARY:
		return {}
	return d


static func orientation(pts: PackedVector2Array) -> float:
	var a := 0.0
	for i in range(pts.size()):
		a += pts[i].cross(pts[(i + 1) % pts.size()])
	return a * 0.5


## Inward unit normal of edge i.
static func inward(pts: PackedVector2Array, i: int) -> Vector2:
	var e := pts[(i + 1) % pts.size()] - pts[i]
	var n := Vector2(-e.y, e.x).normalized()      # left of the direction of travel
	return n if orientation(pts) > 0.0 else -n


## Slope in degrees for each edge: what a plain roof of height `roof_h` over the narrower dimension would have.
static func default_slopes(pts: PackedVector2Array, roof_h: float) -> Array:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for q in pts:
		lo = Vector2(minf(lo.x, q.x), minf(lo.y, q.y))
		hi = Vector2(maxf(hi.x, q.x), maxf(hi.y, q.y))
	var half := maxf(minf(hi.x - lo.x, hi.y - lo.y) * 0.5, 0.5)
	var deg := clampf(rad_to_deg(atan2(maxf(roof_h, 0.1), half)), MIN_DEG, MAX_DEG)
	var out: Array = []
	for i in range(pts.size()):
		out.append(snappedf(deg, 0.5))
	return out


static func _edge_ok(pts: PackedVector2Array, i: int) -> bool:
	var a := pts[i]
	var n := inward(pts, i)
	for q in pts:
		if (q - a).dot(n) < -0.03:
			return false
	return true


## Planes [{"a","b","c","label","end"}] (y = a*x + b*z + c). Empty when no edge has a slope.
static func planes(pts: PackedVector2Array, wall_h: float, cfg: Dictionary) -> Array:
	var slopes: Array = cfg.get("slopes", [])
	var out: Array = []
	for i in range(mini(pts.size(), LETTERS.length() - 1)):
		var deg := float(slopes[i]) if i < slopes.size() else -1.0
		if deg < MIN_DEG or not _edge_ok(pts, i):
			continue
		var m := tan(deg_to_rad(minf(deg, MAX_DEG)))
		var n := inward(pts, i)
		out.append({"a": m * n.x, "b": m * n.y, "c": wall_h - m * pts[i].dot(n), "label": LETTERS[out.size()], "end": false, "edge": i})
	if out.is_empty():
		return out
	var cap := float(cfg.get("cap", 0.0))
	if cap > 0.05:
		out.append({"a": 0.0, "b": 0.0, "c": wall_h + cap, "label": "T", "end": true, "edge": -1})
	return out


## Highest point of the roof above the eaves (sampled), for the info line and the metadata.
static func rise(pts: PackedVector2Array, pl: Array, wall_h: float) -> float:
	if pl.is_empty():
		return 0.0
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for q in pts:
		lo = Vector2(minf(lo.x, q.x), minf(lo.y, q.y))
		hi = Vector2(maxf(hi.x, q.x), maxf(hi.y, q.y))
	var best := 0.0
	for qa in pts:
		best = maxf(best, RoofGen.height_at(pl, qa.x, qa.y) - wall_h)
	var n := 40
	for ix in range(n + 1):
		for iz in range(n + 1):
			var p := Vector2(lerpf(lo.x, hi.x, float(ix) / n), lerpf(lo.y, hi.y, float(iz) / n))
			if Geometry2D.is_point_in_polygon(p, pts):
				best = maxf(best, RoofGen.height_at(pl, p.x, p.y) - wall_h)
	return best


## A hip ("kopertowy") roof as a generated one: the ridge stops short of both gables by half the span.
static func hip_gen(span: float, roof_h: float) -> Dictionary:
	return {"part": 0, "prof": RoofGen.default_profile(span, roof_h), "ra": span * 0.5, "rb": span * 0.5}
