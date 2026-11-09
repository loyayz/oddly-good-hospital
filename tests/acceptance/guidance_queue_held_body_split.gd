extends "res://tests/acceptance/guidance_queue_entry_boundary.gd"
func run_checks()->Dictionary:
 _content=HospitalContent.new();var x:Dictionary=_entry_fixture()
 var probe:Dictionary=_visit(x,"probe",[40,85]);var person:Dictionary=_visit(x,"person",[51,76]);_visit(x,"fixed_a",[51,74]);_visit(x,"fixed_b",[51,75])
 # Two fixed bodies leave one slot. A third body or held member fills it.
 var failures:Array=[];var cases:int=0
 for phase:String in ["seek","desk_queue","to_counter","working","ready","destination"]:
  for has_number:bool in [false,true]:
   for attending:bool in [false,true]:
    for visit_phase:String in ["gp","leaving","departed"]:
     for inside:bool in [false,true]:
      var row:Dictionary={"visit_id":person.id,"desk_id":"guide","guide_floor":1,"phase":phase,"request_key":"test","queue_attending":attending,"queue_bank_key":x.g._queue_bank_key(x.world,"guide"),"queue_cell":[51,76]}
      if has_number:row.queue_seq=1
      x.world.facts.floor_guidance.visits[person.id]=row;person.phase=visit_phase;x.world.facts.actors[person.actor_id].location.cell=[51,76] if inside else [60,85];x.world.touch(false)
      var before=x.world.freeze();var expected:bool=not (inside or (visit_phase=="gp" and has_number and (phase in ["to_counter","working"] or phase=="desk_queue" and attending)));var fresh:bool=Entry.capacity_available(x.space,x.world,x.g,probe.actor_id,"guide")
      if expected!=fresh or before!=x.world.freeze():failures.append([phase,has_number,attending,visit_phase,inside,expected,fresh])
      cases+=1
 _dispose(x);return {"cases":cases,"failures":failures,"ok":failures.is_empty()}
