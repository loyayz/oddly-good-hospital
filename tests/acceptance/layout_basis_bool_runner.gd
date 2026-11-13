extends SceneTree
# Explicit synthetic functional unit, NOT actual-world coverage or microtiming.
func _initialize() -> void: call_deferred("_run")
func _fragment(state: Dictionary, single: bool) -> String:
	var entry: Dictionary=state.entry
	var basis: Array=state.basis
	var moves: Dictionary=state.moves
	var group: Dictionary=state.group
	if single:
		var has_boarding_call: bool=moves[entry.actor_id].has("lift_boarding_call")
		var same_basis: bool=entry.get("layout_basis",[])==basis
		if has_boarding_call and same_basis: return "boarding_continue"
		if not same_basis:
			for id: String in group.leader_ids: moves[id].erase("lift_boarding_call")
			entry.erase("entry_cells")
		if same_basis: return "retain_owner_cells" if entry.has("owner_cells") else "retain_without_owner_cells"
		return "recompute_slots"
	if moves[entry.actor_id].has("lift_boarding_call") and entry.get("layout_basis",[])==basis: return "boarding_continue"
	if entry.get("layout_basis",[])!=basis:
		for id: String in group.leader_ids: moves[id].erase("lift_boarding_call")
		entry.erase("entry_cells")
	if entry.get("layout_basis",[])==basis: return "retain_owner_cells" if entry.has("owner_cells") else "retain_without_owner_cells"
	return "recompute_slots"
func _run() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.is_empty(): quit(2);return
	var rows: Array=[]
	var passed: bool=true
	for has_call: bool in [false,true]:
		for equal: bool in [false,true]:
			for owners: bool in [false,true]:
				var basis: Array=[2,"geometry",["profile"],["body"],[],["a","b"],["a","b"],["connector",1,2,1,[["a",1,2,[4,5]],["b",2,2,[6,5]]]]]
				var old: Array=basis.duplicate(true)
				if not equal: old[1]="old_geometry"
				var state: Dictionary={"basis":basis,"entry":{"actor_id":"a","layout_basis":old,"entry_cells":{"a":[1,2],"b":[2,2]},"untouched":"sentinel"},"moves":{"a":{"untouched":1},"b":{"lift_boarding_call":{"source":"b"},"untouched":2}},"group":{"leader_ids":["a","b"]}}
				if has_call: state.moves.a.lift_boarding_call={"source":"a"}
				if owners: state.entry.owner_cells={"a":[1,2],"b":[2,2]}
				var original: Dictionary=state.duplicate(true)
				var candidate: Dictionary=state.duplicate(true)
				var a: String=_fragment(original,false)
				var b: String=_fragment(candidate,true)
				var expected: String="boarding_continue" if has_call and equal else (("retain_owner_cells" if owners else "retain_without_owner_cells") if equal else "recompute_slots")
				var same: bool=a==b and a==expected and original==candidate and original.entry.keys()==candidate.entry.keys() and original.moves.a.keys()==candidate.moves.a.keys() and original.moves.b.keys()==candidate.moves.b.keys()
				if not equal: same=same and not candidate.entry.has("entry_cells") and not candidate.moves.a.has("lift_boarding_call") and not candidate.moves.b.has("lift_boarding_call")
				else: same=same and candidate==state
				passed=passed and same
				rows.append({"synthetic_unit":true,"has_call":has_call,"equal":equal,"owner_cells":owners,"passed":same,"action":b,"original":original,"candidate":candidate})
	var file:=FileAccess.open(args[0],FileAccess.WRITE)
	if file==null: quit(2);return
	file.store_string(JSON.stringify({"passed":passed,"results":rows,"scope":"Synthetic branch+erase functional equivalence only. No actual-world different-basis coverage, no geometry/body evaluation, no timings; recompute_slots branch is not executed beyond branch selection."},"\t"));file.close()
	quit(0 if passed else 1)
