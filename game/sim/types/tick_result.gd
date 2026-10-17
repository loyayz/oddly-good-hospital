class_name TickResult
extends RefCounted

var sim_tick: int
var revision: int
var facts: Array[SimEvent]
var elapsed_us: int = 0
var main_elapsed_us: int = 0
var started_engine_us: int = 0
var completed_engine_us: int = 0

func _init(tick: int = 0, world_revision: int = 0, events: Array[SimEvent] = []) -> void:
	sim_tick = tick
	revision = world_revision
	facts = events
