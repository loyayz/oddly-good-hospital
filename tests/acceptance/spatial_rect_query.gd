extends RefCounted

func _array(rect: Rect2) -> Array:
	return [rect.position.x,rect.position.y,rect.size.x,rect.size.y]

func _paths(index: PlatformSpatialIndex, floor_id: int, rect: Rect2) -> Dictionary:
	var old: Dictionary = index.query(floor_id,_array(rect))
	var old_variant: Dictionary = index.call("query",floor_id,_array(rect))
	var direct: Dictionary = index.query_rect(floor_id,rect)
	var variant: Dictionary = index.call("query_rect",floor_id,rect)
	return {"ok":old==old_variant and old==direct and old==variant,"expected":old,"direct":direct,"variant":variant}

func _closed_overlap(a: Rect2, b: Rect2) -> bool:
	# The broadphase adds promoted components in double precision. Rect2.end
	# would add in binary32 and is deliberately not this calculation oracle.
	var ar: float = float(a.position.x)+float(a.size.x)
	var ab: float = float(a.position.y)+float(a.size.y)
	var br: float = float(b.position.x)+float(b.size.x)
	var bb: float = float(b.position.y)+float(b.size.y)
	return float(a.position.x)<=br and float(b.position.x)<=ar and float(a.position.y)<=bb and float(b.position.y)<=ab

func run() -> Dictionary:
	var native: PlatformSpatialIndex = PlatformSpatialIndex.new()
	var index: BodyIndex = BodyIndex.new()
	var records: Dictionary = {
		"origin":{"floor":1,"rect":Rect2(0,0,1,1)},
		"edge":{"floor":1,"rect":Rect2(1,0,1,1)},
		"negative":{"floor":-3,"rect":Rect2(-3.125,-2.75,0.875,1.125)},
		"fraction":{"floor":1,"rect":Rect2(35.125,76.375,0.6,0.8)},
		"rounded_end":{"floor":1,"rect":Rect2(40.2,80,0.000001,0.5)},
		"zero":{"floor":1,"rect":Rect2(3,3,0,0)},
		"中":{"floor":10000,"rect":Rect2(0,0,1,1)},
		"😀":{"floor":10000,"rect":Rect2(0,0,1,1)}}
	for id: String in records:
		native.update(id,int(records[id].floor),_array(records[id].rect))
		index.update(id,int(records[id].floor),records[id].rect)
	var rows: Array = []
	var correct: bool = true
	for floor_id: int in [1,-3,10000,20000]:
		for rect: Rect2 in [Rect2(0,0,1,1),Rect2(1,0,0,1),Rect2(1,1,0,0),Rect2(-4,-4,4,4),Rect2(-3.125,-2.75,0.875,1.125),Rect2(35.5,76.5,0.125,0.25),Rect2(35.725,76.375,0.25,0.8),Rect2(40.2,80,0.000002,0.5),Rect2(3,3,0,0)]:
			var paths: Dictionary = _paths(native,floor_id,rect)
			var broad: Array = []
			var strict: Array[String] = []
			for id: String in records:
				if int(records[id].floor)!=floor_id: continue
				if _closed_overlap(rect,records[id].rect): broad.append(id)
				if rect.intersects(records[id].rect,false): strict.append(id)
			broad.sort(); strict.sort()
			var actual_broad: Array = paths.direct.get("ids",[]).duplicate()
			actual_broad.sort()
			var actual: Array[String] = index.candidates(floor_id,rect)
			var ignored: Array[String] = index.candidates(floor_id,rect,strict)
			var ok: bool = paths.ok and actual_broad==broad and actual==strict and ignored.is_empty()
			correct = correct and ok
			rows.append({"floor":floor_id,"rect":_array(rect),"ok":ok,"broad_ids":paths.direct.get("ids",[]),"strict_ids":actual})
	var invalid_rows: Array = []
	for item: Array in [["nan_x",Rect2(NAN,0,1,1)],["infinite_y",Rect2(0,INF,1,1)],["infinite_width",Rect2(0,0,INF,1)],["nan_height",Rect2(0,0,1,NAN)],["negative_width",Rect2(0,0,-1,1)],["negative_height",Rect2(0,0,1,-1)]]:
		for floor_id: int in [1,20000]:
			var paths: Dictionary = _paths(native,floor_id,item[1])
			# The original query parses rectangles only on a populated floor.
			var expected_error: bool = floor_id==1
			var ok: bool = paths.ok and paths.direct.has("error")==expected_error
			correct = correct and ok
			invalid_rows.append({"input":item[0],"floor":floor_id,"ok":ok,"output":paths.direct})
	var seed: Rect2 = records.origin.rect
	native.update("origin",-3,_array(seed)); index.update("origin",-3,seed)
	var moved: bool = _paths(native,-3,seed).ok and index.candidates(-3,seed)==["origin"] and not "origin" in index.candidates(1,seed)
	native.remove("origin"); index.remove("origin")
	var removed: bool = _paths(native,-3,seed).ok and index.candidates(-3,seed).is_empty()
	index.begin_boundary(records)
	var empty_generation: bool = index._query(1,seed).is_empty() and index.candidates(1,seed).is_empty()
	index.update("edge",1,records.edge.rect)
	var reactivated: bool = index.candidates(1,records.edge.rect)==["edge"]
	index.expire_boundary()
	empty_generation = empty_generation and index._query(1,records.edge.rect).is_empty()
	index.update("edge",1,records.edge.rect)
	reactivated = reactivated and index.candidates(1,records.edge.rect)==["edge"]
	var compound: Array[Rect2] = [Rect2(10,10,1,1),Rect2(13,10,1,1)]
	index.update_compound("compound",1,compound)
	var compound_gap: bool = not "compound" in index.candidates(1,Rect2(11.5,10,0.5,1)) and "compound" in index.candidates(1,Rect2(13,10,0.5,1))
	index.clear(); native.clear()
	var cleared: bool = index._query(1,seed).is_empty() and _paths(native,1,seed).ok and native.query_rect(1,seed).ids.is_empty()
	return {"ok":correct and moved and removed and empty_generation and reactivated and compound_gap and cleared,"rows":rows,"invalid":invalid_rows,"floor_update":moved,"removed":removed,"empty_generation":empty_generation,"same_rectangle_reactivation":reactivated,"compound_gap":compound_gap,"clear":cleared,"scope":"Typed native calls and Variant.call preserve complete original Dictionary outputs and Boost ordering. Independent double-component closed boxes check broad candidates; strict engine geometry, ignored identities, full compound regions and boundary lifetime remain BodyIndex-owned. No movement or performance claim."}
