class_name TickResult
extends RefCounted

var sim_tick: int
var revision: int
var facts: Array[SimEvent]

func _init(tick: int = 0, world_revision: int = 0, events: Array[SimEvent] = []) -> void:
	sim_tick = tick
	revision = world_revision
	facts = events
