from pathlib import Path
import hashlib,json,difflib
D=Path(__file__).resolve().parent;P=D.parent/'source/tools/performance/fixture.gd'
s=P.read_text();start=s.index('func _next_position(');end=s.index('\nfunc _location(',start);old=s[start:end]
new='''func _next_position(floor_id: int, actor: Dictionary) -> Array:
	var choices: Array = _positions[floor_id]
	var query: RefCounted = preload("res://tools/performance/placement_query.gd").new(_space,world,actor,floor_id)
	while int(_position_next[floor_id])<choices.size():
		var cell: Array = choices[int(_position_next[floor_id])]
		_position_next[floor_id] += 1
		if query.reason(cell).is_empty() and query.dynamic_clear():
			return cell.duplicate()
	errors.append("没有足够合法身体位置："+str(floor_id))
	return [48,91]
'''
g=s[:start]+new+s[end:]
assert g.replace(new,old,1)==s
(D/'fixture.original.gd').write_text(s);(D/'fixture.candidate.gd').write_text(g)
(D/'fixture.patch').write_text(''.join(difflib.unified_diff(s.splitlines(True),g.splitlines(True),fromfile='a/tools/performance/fixture.gd',tofile='b/tools/performance/fixture.gd')))
(D/'static-check.json').write_text(json.dumps({'original_path':str(P),'original_sha256':hashlib.sha256(s.encode()).hexdigest(),'candidate_sha256':hashlib.sha256(g.encode()).hexdigest(),'replacement_scope':'only _next_position; remaining fixture exact','inverse_exact':True,'source_count_and_facilities_unchanged':True,'candidate_order_cursor_and_failure_unchanged':True,'semantic_delta':'Transient candidate locations only on deep copy; returned final location remains committed by unchanged callers; actor-scoped clearance object reused only until return','engine_executed':False,'semantic_equivalence':'pending oracle and independent review; not established'},indent=2)+'\n')
