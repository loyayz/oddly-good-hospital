import pathlib,json,shutil,hashlib,re
R=pathlib.Path(__file__).resolve().parent;D=R/'diagnostic-fine-v2';D.mkdir();S=D/'source';S.mkdir();(D/'evidence').mkdir();m=json.loads((R/'exporter-integration-r2/source-after-integration.json').read_text())
for f in m['files']:
 p=S/f['path'];p.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(R/'source'/f['path'],p);assert hashlib.sha256(p.read_bytes()).hexdigest()==f['sha256']
shutil.copytree(R/'source/.godot',S/'.godot');shutil.copy2(R/'run_engine.py',D/'run_engine.py')
timer='''extends RefCounted
static var active: bool = false
static var stack: Array = []
static var rows: Dictionary = {}
static var errors: Array = []
static func begin() -> void:
	active=true;stack=[];rows={};errors=[]
static func enter(name: String) -> void:
	if not active: return
	stack.append({"name":name,"start":Time.get_ticks_usec(),"children":0})
static func leave(name: String) -> void:
	if not active: return
	var now: int = Time.get_ticks_usec()
	if stack.is_empty() or stack.back().name!=name: errors.append("stack mismatch "+name);return
	var frame: Dictionary = stack.pop_back()
	var elapsed: int = now-int(frame.start)
	var row: Dictionary = rows.get(name,{"calls":0,"inclusive_us":0,"exclusive_us":0,"max_us":0})
	row.calls+=1;row.inclusive_us+=elapsed;row.exclusive_us+=elapsed-int(frame.children);row.max_us=maxi(row.max_us,elapsed);rows[name]=row
	if not stack.is_empty(): stack.back().children+=elapsed
static func finish() -> Dictionary:
	active=false
	if not stack.is_empty(): errors.append("unclosed calls")
	return {"rows":rows.duplicate(true),"errors":errors.duplicate()}
'''
(S/'tools/performance/current/fine_timer_v1.gd').write_text(timer)
targets={'game/building/hospital_movement.gd':['advance','_dispatch_routes','_move_step','_active_route_clear','_yield','_movement_contacts','_unit_sweeps','_convoy_turn_contact','_continue_detour','_replan_goal','_reserve_doors'],'game/building/hospital_space.gd':['static_reason','_dynamic_clear','_ensure_actor_index','_sync_convoys','release_adaptations','reservation_view'],'game/life/waiting_life.gd':['dispatch','_dispatch_public_seat','_seat_candidates_in_query','_wait_safely']};changes=[]
for path,names in targets.items():
 p=S/path;original=p.read_text();t=original;wrappers=[]
 for name in names:
  pat=r'^func '+re.escape(name)+r'\((.*)\) -> ([^\n]+):$';matches=list(re.finditer(pat,t,re.M));assert len(matches)==1,(path,name);ma=matches[0];args=ma[1];ret=ma[2];assert '(' not in args
  argnames=[a.strip().split(':')[0] for a in args.split(',')];header=ma[0];newname='_fine_original_'+name;newheader=header.replace('func '+name+'(', 'func '+newname+'(');t=t[:ma.start()]+newheader+t[ma.end():]
  key=path+':'+name;body=header+'\n\t_FineTimer.enter("'+key+'")\n\t'+('var value: '+ret+' = ' if ret!='void' else '')+newname+'('+','.join(argnames)+')\n\t_FineTimer.leave("'+key+'")\n'+('\treturn value\n' if ret!='void' else '')
  wrappers.append((header,newheader,body))
 prefix='const _FineTimer = preload("res://tools/performance/current/fine_timer_v1.gd")\n';t=t.replace('extends RefCounted\n','extends RefCounted\n'+prefix,1);assert prefix in t
 for _,_,w in wrappers:t+='\n'+w
 # Undo all generated text must recover original bytes: bodies untouched.
 undo=t.replace(prefix,'',1)
 for old,new,w in wrappers:undo=undo.replace('\n'+w,'',1).replace(new,old,1)
 assert undo==original
 p.write_text(t);changes.append({'path':path,'methods':names,'original_sha256':hashlib.sha256(original.encode()).hexdigest(),'diagnostic_sha256':hashlib.sha256(t.encode()).hexdigest(),'marker_removal_exact':True})
t=(R/'diagnostic-root-v1/source/tools/performance/current/diagnostic_v1.gd').read_text();t=t.replace('var output: String','const FineTimer = preload("res://tools/performance/current/fine_timer_v1.gd")\nvar output: String');t=t.replace('var samples: Array = []','var samples: Array = []\n\tvar fine_rows: Array = []');t=t.replace('\t\tvar started: int = Time.get_ticks_usec()','\t\tFineTimer.begin()\n\t\tvar started: int = Time.get_ticks_usec()');t=t.replace('\t\tif observer!=null:\n\t\t\tobserver.end_step', '\t\tvar fine: Dictionary = FineTimer.finish()\n\t\tfine.tick=world.sim_tick;fine_rows.append(fine)\n\t\tif not fine.errors.is_empty(): errors.append("fine timer error");break\n\t\tif observer!=null:\n\t\t\tobserver.end_step');t=t.replace('\tvalidation=world.validate(content)','\twrite_json(output+".fine.json",{"steps":fine_rows})\n\tvalidation=world.validate(content)');(S/'tools/performance/current/fine_driver_v1.gd').write_text(t);(D/'changes.json').write_text(json.dumps({'base_source_aggregate':m['source_aggregate_sha256'],'method_body_unchanged':True,'wrapping_mode':'Normal constructor, same service object identity; method entry wrapper only, body renamed unchanged. Diagnostic only.','files':changes},indent=2));print(D)
