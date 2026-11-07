from pathlib import Path
import hashlib,json,difflib
D=Path(__file__).resolve().parent
S=D.parent/'source/tools/performance/fixture.gd'
raw=S.read_bytes();original=raw.decode();tag=' # diagnostic640-marker'
def marked(s):return '\n'.join(x+tag for x in s.split('\n'))+'\n'
out=[]
for line in original.splitlines(keepends=True):
 t=line.strip();indent=line[:len(line)-len(line.lstrip())]
 if t.startswith('var world:'):
  out.append(marked('var _d640_started: int = Time.get_ticks_usec()\nvar _d640_sync_us: int = 0\nvar _d640_sync_calls: int = 0\nvar _d640_exhausted: bool = false'))
 before=[];after=[]
 if t.startswith('world = HospitalFactory.create('):before=['_d640_mark("factory_enter")'];after=['_d640_mark("factory_exit")']
 if t=='_build_floor(floor_id,64 if floors.size()==1 else 16,1200/floors.size())':before=['_d640_mark("floor_enter",{"floor":floor_id})'];after=['_d640_mark("floor_exit",{"floor":floor_id})']
 if t=='_space = HospitalSpace.new(content)':before=['_d640_mark("space_enter")'];after=['_d640_mark("space_exit")']
 if t=='for index: int in staff_count:':before=['_d640_mark("staff_enter")'];after=['\tif index%16==0: _d640_mark("staff_progress",{"index":index})']
 if t=='var visitors: int = count/20':before=['_d640_mark("staff_exit")']
 if t=='for index: int in count-staff_count-visitors:':before=['_d640_mark("patients_enter")'];after=['\tif index%16==0: _d640_mark("patient_progress",{"index":index})']
 if t=='for index: int in visitors:':before=['_d640_mark("patients_exit")','_d640_mark("visitors_enter")'];after=['\tif index%16==0: _d640_mark("visitor_progress",{"index":index})']
 if t=='world.touch()':before=['_d640_mark("visitors_exit")'];after=['_d640_mark("fixture_exit",{"errors":errors.duplicate(),"actors":world.facts.actors.size(),"rooms":world.facts.rooms.size(),"facilities":world.facts.facilities.size()})']
 if t=='for index: int in room_count:':before=['_d640_mark("rooms_enter",{"floor":floor_id,"requested":room_count})']
 if t=='var placed: int = 0':before=['_d640_mark("rooms_exit",{"floor":floor_id})','_d640_mark("props_enter",{"floor":floor_id,"requested":props})']
 if t=='if placed>=props: return':before=['if placed>=props: _d640_mark("props_exit",{"floor":floor_id,"placed":placed})']
 if t=='_space.sync_actor(world,id)':
  before=['var _d640_sync_start: int = Time.get_ticks_usec()'];after=['_d640_sync_us += Time.get_ticks_usec()-_d640_sync_start','_d640_sync_calls += 1']
 if t=='var choices: Array = _positions[floor_id]':after=['if int(_position_next[floor_id])%32==0: _d640_mark("placement_actor",{"actor":actor.id,"floor":floor_id,"cursor":_position_next[floor_id],"choices":choices.size()})']
 if t=='var cell: Array = choices[int(_position_next[floor_id])]':before=['if int(_position_next[floor_id])%32==0: _d640_mark("candidate",{"actor":actor.id,"floor":floor_id,"cursor":_position_next[floor_id],"choices":choices.size()})']
 if t.startswith('errors.append("没有足够合法身体位置'):
  before=['if not _d640_exhausted:','\t_d640_exhausted = true','\t_d640_mark("first_placement_exhaustion",{"actor":actor.id,"floor":floor_id,"cursor":_position_next[floor_id],"choices":choices.size()})']
 if before:out.append(marked('\n'.join(indent+x for x in before)))
 out.append(line)
 if after:out.append(marked('\n'.join(indent+x for x in after)))
out.append(marked('\nfunc _d640_mark(stage: String, detail: Dictionary = {}) -> void:\n\tprint("DIAGNOSTIC640="+JSON.stringify({"stage":stage,"elapsed_us":Time.get_ticks_usec()-_d640_started,"sync_calls":_d640_sync_calls,"sync_us":_d640_sync_us,"detail":detail}))'))
generated=''.join(out)
restored=''.join(x for x in generated.splitlines(keepends=True) if not x.rstrip('\n').endswith(tag))
assert restored==original
for needle,count in [('_space.static_reason(',1),('_space._dynamic_clear(',1),('_space.sync_actor(world,id)',3),('return [48,91]',1)]:assert generated.count(needle)==original.count(needle)==count
(D/'fixture.original.gd').write_bytes(raw);(D/'fixture.diagnostic.gd').write_text(generated)
(D/'fixture.patch').write_text(''.join(difflib.unified_diff(original.splitlines(True),generated.splitlines(True),fromfile='a/tools/performance/fixture.gd',tofile='b/tools/performance/fixture.gd')))
(D/'static-check.json').write_text(json.dumps({'original_path':str(S),'original_sha256':hashlib.sha256(raw).hexdigest(),'diagnostic_sha256':hashlib.sha256(generated.encode()).hexdigest(),'marker_stripping_restores_exact_original':True,'all_original_lines_preserved_in_order':True,'static_dynamic_short_circuit_unchanged':True,'original_calls_not_removed_or_repeated':True,'engine_or_compile_test_run':False,'limits':'Timing and console IO add overhead; syntax and runtime dispatch not yet engine-validated; raw construction result is not a legal business input'},indent=2)+'\n')
