class_name FxFlicker
extends OmniLight3D
## A light that flickers like a flame: slow breathing plus fast random jitter around the base energy.

@export var base_energy := 2.5
@export var amount := 0.4
@export var speed := 7.0
var _t := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_t = _rng.randf() * 10.0


func _process(delta: float) -> void:
	_t += delta * speed
	var slow := sin(_t * 0.7) * 0.5 + sin(_t * 1.9 + 1.3) * 0.3
	var fast := _rng.randf_range(-1.0, 1.0) * 0.35
	light_energy = maxf(base_energy * (1.0 + amount * (slow * 0.6 + fast)), 0.0)
