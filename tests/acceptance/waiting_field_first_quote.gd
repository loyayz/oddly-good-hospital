extends "res://tests/acceptance/public_entry_field_prune.gd"
func run_focused(content: HospitalContent) -> Dictionary:
	_content=content
	var x: Dictionary=_setup(false,false,true)
	_field_begin(x)
	var warm: Dictionary=_warm(x)
	_field_end(x)
	# The field survives, but the new synchronous selection has no actor context.
	_field_begin(x)
	var before: Dictionary=x.world.freeze()
	var observed: Dictionary=_observe(x)
	var borrows: Array=observed.audit.borrows
	var first_miss_then_ready: bool=borrows.size()>=2 and not borrows[0].ready and borrows[1].ready
	var passed: bool=warm.ok and observed.ok and first_miss_then_ready and observed.real_quotes==1 and before==x.world.freeze()
	_field_end(x)
	passed=passed and x.actual._route_queries.is_empty() and x.original._route_queries.is_empty()
	_field_dispose(x)
	return {"passed":passed,"first_miss_then_ready":first_miss_then_ready,"warm":warm,"observed":observed,"scope":"New query over genuinely warmed resident fields; original full solver remains the result oracle."}
