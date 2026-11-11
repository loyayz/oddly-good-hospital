extends "res://tests/acceptance/staff_fixtures.gd"
const Batch=preload("res://game/operations/environment_sample_batch.gd")
class FullBatch extends Batch:
 pass
class BrokenJob extends Batch.SampleJob:
 func run()->void:
  super.run()
  if not results.is_empty():results[0]=null

func fixture()->Dictionary:
 var x:Dictionary=_fixture({"cleaner":"cleaner"})
 preload("res://tests/acceptance/waiting_environment_sample.gd").new().canonical_floors(x.world)
 for i:int in 2:
  var v:Dictionary=_visit(x,"subject_%d"%i,[[40,78],[55,88]][i]);x.world.register_visit(v.id)
 x.e.waiting_life=x.l
 x.world.touch();x.p.ensure(x.world)
 return x

func observations(x:Dictionary,batch:RefCounted)->Dictionary:
 var before:Dictionary=x.world.freeze();var ids:Array=x.world.active_visit_ids()
 x.space.begin_route_query(x.world,{},false);x.e.begin_query(x.world)
 var prepared:bool=batch.prepare(x.world,x.e,ids,4,true)
 var output:Dictionary={};var direct:Dictionary={}
 var coverage_maps:Array=[];var observations_owned:Array=[];var sources_owned:Array=[];var readonly_empty:int=0
 for item:Array in batch._observations.values():
  var observation:Dictionary=item[Batch.ResultSlot.OBSERVATION];var coverage:Dictionary=item[Batch.ResultSlot.COVERAGE]
  if not coverage_maps.any(func(value:Dictionary)->bool:return is_same(value,coverage)):coverage_maps.append(coverage)
  if not observations_owned.any(func(value:Dictionary)->bool:return is_same(value,observation)):observations_owned.append(observation)
  if not sources_owned.any(func(value:Array)->bool:return is_same(value,observation.sources)):sources_owned.append(observation.sources)
  if coverage.is_empty() and coverage.is_read_only():readonly_empty+=1
 if prepared:
  batch.begin_apply()
  for id:String in ids:
   if not batch._observations.has(id):continue
   var a:Dictionary=x.world.facts.actors[x.world.facts.visits[id].actor_id]
   output[id]=batch.consume(x.world,x.e,id,a.id)
   direct[id]=x.e.sample_at(x.world,int(a.location.floor_id),a.location.cell,a.id)
  batch.end_apply(x.e)
 x.e.end_query();x.space.end_route_query()
 var report:Dictionary=batch.report()
 return {"ok":output==direct and before==x.world.freeze() and x.world.validate(_content).is_empty(),"values":output,"direct_equal":output==direct,"readonly":before==x.world.freeze(),"validation":x.world.validate(_content),"main_empty":report.get("last_batch",{}).get("main_empty_observations",0),"jobs":report.get("last_batch",{}).get("jobs",[]).size(),"allocated_jobs":batch._jobs.size(),"containers":{"coverage":coverage_maps.size(),"observations":observations_owned.size(),"sources":sources_owned.size(),"readonly_empty":readonly_empty},"consumed":report.consumed,"closed":x.space._route_queries.is_empty() and x.e._query_depth==0}

func matrix(modes:Array=[])->Dictionary:
 var rows:Array=[]
 if modes.is_empty():modes=["empty","mixed_light","floor_finish","dirt","fractional","upper_floor","legacy","custom_batch","closed","non_floor"]
 for mode:String in modes:
  var x:Dictionary=fixture();var expected:int=2
  var a:Dictionary=x.world.facts.actors.patient_subject_0
  if mode in ["range_outside","range_upgraded"]:
   _facility(x,"light","FUR19",[41,78]);a.location.cell=[41+int(_content.balance.environment.range_cells)+1,78]
   if mode=="range_upgraded":x.world.facts.research.append("R15");expected=1
  if mode=="mixed_light":_facility(x,"light","FUR19",[41,78]);expected=1
  if mode=="floor_finish":
   var m:Dictionary=_content.definition("renovation_materials","MAT01")
   var key:String=x.e._surface_key(1,a.location.cell,"floor")
   x.world.facts.environment.surfaces[key]={"floor_id":1,"cell":a.location.cell.duplicate(),"surface":"floor","edge":"","material_id":"MAT01","paid_cost":int(m.unit_price),"order_id":""};expected=1
  if mode=="dirt":x.e.spawn_dirt(x.world,"CL01","empty_batch","empty_batch:1",1,a.location.cell);expected=1
  if mode=="fractional":a.location.cell=[40.75,78.25]
  if mode=="upper_floor":
   x.world.facts.floors.height_intervals[0].last=2
   x.world.facts.floors.overrides["2"]={"plots":[[1,2]],"blocked":[],"doors":[],"paths":[]}
   x.world.facts.floors.completed_top_floor["1:2"]=2;a.location.floor_id=2
  if mode=="legacy":x.world.facts.floors.erase("completed_top_floor");expected=0
  if mode=="custom_batch":expected=0
  if mode=="closed":x.world.facts.patient_experience.experience.subject_0.closed_tick=0;expected=1
  if mode=="non_floor":a.location={"kind":"outside"};expected=1
  x.world.touch()
  var row:Dictionary=observations(x,FullBatch.new() if mode=="custom_batch" else Batch.new());row.case=mode
  row.ok=row.ok and row.closed and row.main_empty==expected
  if mode=="mixed_light":row.ok=row.ok and row.values.subject_0.light and not row.values.subject_1.light and row.jobs==1
  if mode in ["range_outside","range_upgraded"]:row.ok=row.ok and row.values.subject_0.light==(mode=="range_upgraded")
  if mode=="dirt":row.ok=row.ok and not row.values.subject_0.clean and row.values.subject_1.clean
  rows.append(row);x.e.waiting_life=null;x.l.environment=null
 return {"ok":rows.all(func(r:Dictionary)->bool:return r.ok),"rows":rows}

# These are observation coordinates, not actor relocations. The real input
# world remains valid; an outside point cannot occur as a valid live patient.
func guards()->Dictionary:
 var x:Dictionary=fixture();var rows:Array=[]
 _facility(x,"far_light","FUR19",[60,90]);x.world.touch();var before:Dictionary=x.world.freeze()
 x.e.begin_query(x.world);x.e._prepare_facility_sources(x.world);x.e._prepare_sample_sources(x.world)
 var bounds:Variant=x.e._prepare_observation_bounds(x.world,[1]);x.e._coverage_edges(x.world,1)
 for mode:String in ["outside_owned","out_of_grid","negative","missing_floor_bound","unknown_bounds","different_world"]:
  var point:Array=[40,78];var floor_id:int=1;var passed_bounds:Variant=bounds;var w:WorldState=x.world
  if mode=="outside_owned":point=[10,10]
  if mode=="out_of_grid":point=[96,78]
  if mode=="negative":point=[-1,78]
  if mode=="missing_floor_bound":floor_id=2
  if mode=="unknown_bounds":passed_bounds=null
  if mode=="different_world":w=WorldState.new(x.world.freeze())
  var batch:RefCounted=Batch.new();var requests:Array=[["subject_0","patient_subject_0",floor_id,point]]
  var pending:Array=batch._prepare_empty_samples(w,x.e,requests,passed_bounds)
  var row:Dictionary={"case":mode,"pending_unchanged":pending==requests,"no_direct_result":batch._observations.is_empty(),"world_legal":x.world.validate(_content),"readonly":before==x.world.freeze()}
  row.ok=row.pending_unchanged and row.no_direct_result and row.world_legal.is_empty() and row.readonly;rows.append(row)
 x.e.end_query();x.e.waiting_life=null;x.l.environment=null
 return {"ok":rows.all(func(r:Dictionary)->bool:return r.ok),"rows":rows,"scope":"Conservative helper guards on legal world and explicit calculation coordinates. No patient movement or outside-hospital body is fabricated."}

func live()->Dictionary:
 var x:Dictionary=fixture();var batch:RefCounted=Batch.new();var rows:Array=[]
 for state:String in ["empty","add_light","failed_light","remove_light","facts_replace","new_world"]:
  if state=="add_light":_facility(x,"light","FUR19",[41,78])
  if state=="failed_light":x.world.facts.facilities.light.failed=true
  if state=="remove_light":x.world.facts.facilities.erase("light");x.world.invalidate_geometry()
  if state=="facts_replace":x.world.facts=x.world.freeze()
  if state=="new_world":
   x.e.waiting_life=null;x.l.environment=null
   x=_bind(WorldState.new(x.world.freeze()));x.e.waiting_life=x.l
  var row:Dictionary=observations(x,batch);row.state=state
  row.ok=row.ok and row.closed and row.values.subject_0.light==(state=="add_light") and row.main_empty==(1 if state in ["add_light","failed_light"] else 2)
  rows.append(row)
 x.e.waiting_life=null;x.l.environment=null
 return {"ok":rows.all(func(r:Dictionary)->bool:return r.ok),"rows":rows}

func department_pair(broken:bool)->Dictionary:
 var input:Dictionary=fixture();_facility(input,"light","FUR19",[41,78]);input.world.touch()
 var a:Dictionary=_bind(WorldState.new(input.world.freeze()));var b:Dictionary=_bind(WorldState.new(input.world.freeze()))
 for x:Dictionary in [a,b]:
  x.e.waiting_life=x.l
  for id:String in x.world.active_visit_ids():x.world.facts.patient_experience.experience[id].next_anger_tick=0
 a.p.sample_workers_enabled=false
 b.p.sample_worker_tasks=1
 if broken:
  var batch:RefCounted=Batch.new();batch._content=_content;batch._jobs=[BrokenJob.new(_content)];b.p._worker_sample_batch=batch
 var before:Dictionary=a.world.freeze()
 a.p.sample(a.world);b.p.sample(b.world)
 var report:Dictionary=b.p.sample_worker_report()
 var result:Dictionary={"broken":broken,"complete_facts_equal":a.world.freeze()==b.world.freeze(),"rng_unchanged":before.rng==b.world.facts.rng,"main_empty":report.last_batch.main_empty_observations,"failed_batches":report.failed_batches,"consumed":report.consumed,"validation":b.world.validate(_content),"closed":b.space._route_queries.is_empty() and b.e._query_depth==0}
 result.ok=result.complete_facts_equal and result.rng_unchanged and result.validation.is_empty() and result.closed and result.main_empty==1 and result.failed_batches==int(broken) and result.consumed==(0 if broken else 2)
 for x:Dictionary in [input,a,b]:x.e.waiting_life=null;x.l.environment=null
 return result

func preparation_reuse()->Dictionary:
 var x:Dictionary=fixture();var batch:RefCounted=Batch.new();var rows:Array=[];var worker_id:int=0
 for state:String in ["empty_cold","mixed","empty_warm","mixed_again"]:
  if state in ["mixed","mixed_again"]:_facility(x,"light","FUR19",[41,78])
  if state=="empty_warm":x.world.facts.facilities.erase("light");x.world.invalidate_geometry()
  var row:Dictionary=observations(x,batch);row.state=state
  var empty:bool=state in ["empty_cold","empty_warm"]
  row.ok=row.ok and row.closed and row.main_empty==(2 if empty else 1) and row.jobs==(0 if empty else 1)
  row.ok=row.ok and row.allocated_jobs==(0 if state=="empty_cold" else 1) and row.containers.observations==2 and row.containers.sources==2
  if empty:row.ok=row.ok and row.containers.coverage==1 and row.containers.readonly_empty==2
  if state=="mixed":worker_id=batch._jobs[0].get_instance_id()
  if state in ["empty_warm","mixed_again"]:row.ok=row.ok and batch._jobs[0].get_instance_id()==worker_id
  rows.append(row)
 x.e.waiting_life=null;x.l.environment=null
 return {"ok":rows.all(func(r:Dictionary)->bool:return r.ok),"rows":rows,"scope":"All observations equal native sample_at; empty batches retain independent observations/sources and share only immutable empty coverage. Native workers are created only for actual requests and reused across empty batches."}

func run_selected(c:HospitalContent,selected:Array)->Dictionary:
 _content=c;var cases:Dictionary={}
 for id:String in selected:
  if id=="ENV-EMPTY-MATRIX":cases[id]=matrix()
  elif id=="ENV-EMPTY-RANGE":cases[id]=matrix(["range_outside","range_upgraded"])
  elif id=="ENV-EMPTY-GUARDS":cases[id]=guards()
  elif id=="ENV-EMPTY-LIVE":cases[id]=live()
  elif id=="ENV-EMPTY-DEPARTMENT":
   var rows:Array=[department_pair(false),department_pair(true)];cases[id]={"ok":rows.all(func(r:Dictionary)->bool:return r.ok),"rows":rows}
  elif id=="ENV-EMPTY-PREPARATION":cases[id]=preparation_reuse()
  else:return {"ok":false,"unknown_case":id}
 return {"ok":not cases.is_empty() and cases.values().all(func(r:Dictionary)->bool:return r.ok),"cases":cases}
