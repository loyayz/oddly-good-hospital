from pathlib import Path
import hashlib,json,ast
D=Path(__file__).resolve().parent;V=D.parent/'diagnostic640-v1'
s=(V/'fixture.diagnostic.gd').read_text()
old='_space.static_reason(world,actor,floor_id,Vector2i(int(cell[0]),int(cell[1]))).is_empty() and _space._dynamic_clear(world,actor.id,floor_id,_space.body_rectangle(actor))'
new='_d640_static(actor,floor_id,Vector2i(int(cell[0]),int(cell[1]))).is_empty() and _d640_dynamic(actor,floor_id)'
assert s.count(old)==1
vars='''var _d640_static_calls: int = 0
var _d640_static_us: int = 0
var _d640_dynamic_calls: int = 0
var _d640_dynamic_us: int = 0
var _d640_static_rejections: int = 0
var _d640_dynamic_rejections: int = 0
'''
helpers='''
func _d640_detail(stage: String, detail: Dictionary = {}) -> void:
	print("DIAGNOSTIC640_DETAIL="+JSON.stringify({"stage":stage,"elapsed_us":Time.get_ticks_usec()-_d640_started,"static_calls":_d640_static_calls,"static_us":_d640_static_us,"dynamic_calls":_d640_dynamic_calls,"dynamic_us":_d640_dynamic_us,"static_rejections":_d640_static_rejections,"dynamic_rejections":_d640_dynamic_rejections,"query_counts":_space.query_counts.duplicate(),"detail":detail}))

func _d640_static(actor: Dictionary, floor_id: int, origin: Vector2i) -> String:
	if _d640_static_calls>0 and _d640_static_calls%32==0: _d640_detail("completed_candidate_block",{"completed_candidates":_d640_static_calls})
	_d640_static_calls += 1
	if _d640_static_calls<=4: _d640_detail("static_enter",{"candidate":_d640_static_calls,"actor":actor.id,"origin":[origin.x,origin.y]})
	var started: int = Time.get_ticks_usec()
	var reason: String = _space.static_reason(world,actor,floor_id,origin)
	_d640_static_us += Time.get_ticks_usec()-started
	if not reason.is_empty(): _d640_static_rejections += 1
	if _d640_static_calls<=4: _d640_detail("static_exit",{"candidate":_d640_static_calls,"reason":reason})
	return reason

func _d640_dynamic(actor: Dictionary, floor_id: int) -> bool:
	_d640_dynamic_calls += 1
	if _d640_static_calls<=4: _d640_detail("dynamic_enter",{"candidate":_d640_static_calls,"actor":actor.id})
	var started: int = Time.get_ticks_usec()
	var clear: bool = _space._dynamic_clear(world,actor.id,floor_id,_space.body_rectangle(actor))
	_d640_dynamic_us += Time.get_ticks_usec()-started
	if not clear: _d640_dynamic_rejections += 1
	if _d640_static_calls<=4: _d640_detail("dynamic_exit",{"candidate":_d640_static_calls,"clear":clear})
	return clear
'''
generated=s.replace('var world: WorldState',vars+'var world: WorldState',1).replace(old,new)+helpers
# One extra final summary, outside measured calls; first-exhaustion coarse marker remains.
anchor='\t\treturn cell.duplicate()'
assert generated.count(anchor)==1
# Summaries before candidate33/65 report completed blocks including dynamic call of prior candidate.
final='\t_d640_mark("fixture_exit",'
pos=generated.find(final);assert pos>=0
generated=generated[:pos]+'\t_d640_detail("fixture_return")\n'+generated[pos:]
restored=generated.replace(vars,'',1).replace(new,old,1).removesuffix(helpers).replace('\t_d640_detail("fixture_return")\n','',1)
assert restored==s
(D/'fixture.diagnostic.gd').write_text(generated)
(D/'static-check.json').write_text(json.dumps({'original_sha256':hashlib.sha256((V/'fixture.original.gd').read_bytes()).hexdigest(),'v1_fixture_sha256':hashlib.sha256(s.encode()).hexdigest(),'diagnostic_sha256':hashlib.sha256(generated.encode()).hexdigest(),'inverse_exact_v1':True,'short_circuit_and_preserved':True,'static_query_called_exactly_once_per_candidate':True,'dynamic_query_only_after_static_success':True,'body_rectangle_evaluated_once_only_on_dynamic_path':True,'query_counts_read_only_duplicate':True,'engine_run':False,'scope':'Diagnostic attribution only; no legal input or performance pass'},indent=2)+'\n')
for n in ['driver.gd','install.py','run.py']:(D/n).write_bytes((V/n).read_bytes().replace(b'diagnostic640-v1',b'diagnostic640-v2'))
for p in D.glob('*.py'):ast.parse(p.read_text())
