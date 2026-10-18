class_name ViewWorkBudget
extends RefCounted

# One window shares its existing per-frame budget between resource binding and
# the active preview. This is elapsed work, never simulation or saved state.
var limit_usec: int
var _frame: int = -1
var _spent_usec: int = 0
var frames_over_budget: int = 0
var maximum_atomic_usec: int = 0

func _init(limit: int) -> void:
	limit_usec = maxi(1,limit)

func remaining_usec() -> int:
	if _frame!=Engine.get_process_frames():
		_frame = Engine.get_process_frames()
		_spent_usec = 0
	return maxi(0,limit_usec-_spent_usec)

func spend(elapsed_usec: int) -> void:
	remaining_usec()
	if _spent_usec<=limit_usec and _spent_usec+elapsed_usec>limit_usec: frames_over_budget += 1
	maximum_atomic_usec = maxi(maximum_atomic_usec,elapsed_usec)
	_spent_usec += maxi(0,elapsed_usec)

func observation() -> Dictionary:
	return {"frame":_frame,"limit_usec":limit_usec,"spent_usec":_spent_usec,"frames_over_budget":frames_over_budget,"maximum_atomic_usec":maximum_atomic_usec,"scope":"observed new view work; atomic overruns remain ordinary frame cost"}
