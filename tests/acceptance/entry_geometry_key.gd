extends RefCounted
func run(content: HospitalContent, world: WorldState) -> Dictionary:
	var space:=HospitalSpace.new(content)
	var public:=space.public_areas
	public._ensure(world)
	var checks: Array=[]
	var prefixes: Array=[[],[{}, {}, "standing",Vector2.ZERO,Vector2.ONE],[{"id":"门\"雪\\[]"},{"height":1.2345678901234567},"lying",Vector2(-0.25,0.5),Vector2(2,3)]]
	var vectors: Array=[[],[["door",1]],[["门\"雪\\[]",1.2345678901234567],["second",3]],[["door",2]],[["door",1]]]
	for prefix: Array in prefixes:
		for spans: Array in vectors:
			var full: Array=prefix.duplicate(true);full.append(spans)
			var encoded: String=JSON.stringify(prefix,"",true,true)
			# Production has exactly five prefix elements; use representative nonempty prefixes.
			if prefix.is_empty(): continue
			checks.append(encoded.substr(0,encoded.length()-1)+","+JSON.stringify(spans,"",true,true)+"]"==JSON.stringify(full,"",true,true))
	var constraints: Dictionary=public._wait_constraints(world)
	for floor_id: int in constraints.doors:
		var spans: Array=[]
		for door: Dictionary in constraints.doors[floor_id]: spans.append([door.id,door.span])
		var first: Dictionary=public._wait_door_view(world,floor_id,spans)
		var original: String=str(first.span_key)
		checks.append(original==JSON.stringify(spans,"",true,true))
		checks.append(is_same(first,public._wait_door_view(world,floor_id,spans)))
		if not spans.is_empty():
			var changed: Array=spans.duplicate(true);changed[0][1]=float(changed[0][1])+1
			var second: Dictionary=public._wait_door_view(world,floor_id,changed)
			checks.append(is_same(first,second) and first.span_key==JSON.stringify(changed,"",true,true))
			changed[0][1]=999
			checks.append(second.spans[0][1]!=999)
			public._wait_door_view(world,floor_id,spans)
			checks.append(first.span_key==original)
	public.invalidate()
	checks.append(public._revision==-1) # invalidate is intentionally lazy.
	return {"passed":not false in checks,"checks":checks.size()}
