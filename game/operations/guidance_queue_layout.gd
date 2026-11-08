extends RefCounted

# Immutable grid plan only. No people, reservations or future occupancy claims.
# Right is the patient's right while facing the desk. The wall-side two cells
# and one cell between columns never belong to queue slots.
static func plan(facility: Dictionary, walls: Array, floor_bounds: Rect2i, body_cells: int = 1) -> Dictionary:
	var turn: int=posmod(int(facility.get("rotation",0)),4)
	var front: Vector2i=[Vector2i.DOWN,Vector2i.LEFT,Vector2i.UP,Vector2i.RIGHT][turn]
	var right: Vector2i=Vector2i(front.y,-front.x)
	var origin: Vector2i=Vector2i(int(facility.cell[0]),int(facility.cell[1]))
	var size: Vector2i=Vector2i(int(facility.footprint[0]),int(facility.footprint[1]))
	var base_width: int=size.x if front.x==0 else size.y
	var span: int=maxi(1,body_cells)
	var column_count: int=(base_width+1)/2
	var width: int=column_count*span+maxi(0,column_count-1)
	var extension: int=width-base_width
	var edge: Vector2i
	match turn:
		0: edge=origin+Vector2i(size.x-1,size.y)
		1: edge=origin+Vector2i(-1,size.y-1)
		2: edge=origin+Vector2i(0,-1)
		3: edge=origin+Vector2i(size.x,0)
	edge+=right*ceili(float(extension)/2.0)
	var columns: Array=[]
	var minimum_gap: int=2147483647
	# Inspect the entire desk frontage, not just planned columns: a nearby
	# partial wall cannot evade the three-cell placement rule.
	var gaps: Array[int]=[]
	for lateral: int in range(width):
		var start: Vector2i=edge-right*lateral
		var gap: int=0
		while floor_bounds.has_point(start+front*gap):
			var point: Vector2i=start+front*gap
			var boundary: int=point.y if front.y>0 else point.y+1 if front.y<0 else point.x if front.x>0 else point.x+1
			var cross_axis: int=point.x if front.x==0 else point.y
			var stopped: bool=false
			for wall: Dictionary in walls:
				if str(wall.axis)!=("x" if front.x==0 else "y"): continue
				if int(wall.line)==boundary and cross_axis>=int(wall.low) and cross_axis<int(wall.high):
					stopped=true
					break
			if stopped: break
			gap+=1
		gaps.append(gap)
		minimum_gap=mini(minimum_gap,gap)
	for lateral: int in range(0,maxi(0,width-span+1),span+1):
		var gap: int=2147483647
		for stripe: int in range(lateral,lateral+span): gap=mini(gap,gaps[stripe])
		var slots: Array=[]
		for depth: int in range(0,maxi(0,gap-2-span+1),span):
			var corner: Vector2i=edge-right*lateral+front*depth
			var opposite: Vector2i=corner-right*(span-1)+front*(span-1)
			var low: Vector2i=corner.min(opposite)
			slots.append([low.x,low.y])
		if not slots.is_empty(): columns.append(slots)
	var ordered: Array=[]
	for column: Array in columns: ordered.append_array(column)
	return {"placement_ok":minimum_gap>=3,"minimum_front_gap":minimum_gap,"columns":columns,"slots":ordered,"body_cells":span,"front":[front.x,front.y],"right":[right.x,right.y]}

# Pure packing of actual members only. A pending visitor belongs in probe(),
# never in spans. Every member keeps its own footprint/depth, not max(spans).
# validator(index, cell) may reject fixed geometry but must be read-only.
# walls is borrowed from an immutable geometry context. Caller must discard
# this packing when that context changes; neither pack nor probe writes walls.
static func pack(facility: Dictionary, walls: Array, floor_bounds: Rect2i, spans: Array, validator: Callable = Callable()) -> Dictionary:
	var turn: int=posmod(int(facility.get("rotation",0)),4)
	var front: Vector2i=[Vector2i.DOWN,Vector2i.LEFT,Vector2i.UP,Vector2i.RIGHT][turn]
	var right: Vector2i=Vector2i(front.y,-front.x)
	var origin: Vector2i=Vector2i(facility.cell[0],facility.cell[1])
	var size: Vector2i=Vector2i(facility.footprint[0],facility.footprint[1])
	var width: int=size.x if front.x==0 else size.y
	var edge: Vector2i
	match turn:
		0:edge=origin+Vector2i(size.x-1,size.y)
		1:edge=origin+Vector2i(-1,size.y-1)
		2:edge=origin+Vector2i(0,-1)
		3:edge=origin+Vector2i(size.x,0)
	var depths: Array=[]
	for column: int in range(int((width+1)/2)):depths.append(0)
	var result: Dictionary={"placements":[],"spans":[],"columns":[],"complete":true,"front":front,"right":right,"edge":edge,"depths":depths,"walls":walls,"bounds":floor_bounds,"rects":[]}
	for raw_span: Variant in spans:
		var span: int=int(raw_span)
		if not result.complete:
			result.placements.append([])
			result.spans.append(span)
			result.columns.append(-1)
			continue
		var candidate: Dictionary=_pack_next(result,span,validator)
		if not candidate.ok:
			result.complete=false
			result.placements.append([])
			result.spans.append(span)
			result.columns.append(-1)
			continue
		result.placements.append(candidate.cell)
		result.spans.append(span)
		result.columns.append(candidate.column)
		result.rects.append({"rect":candidate.rect,"column":candidate.column})
		result.depths[candidate.column]=int(result.depths[candidate.column])+span
	return result

static func probe(packing: Dictionary, span: int, validator: Callable = Callable()) -> Dictionary:
	if not packing.get("complete",false):return {"ok":false,"cell":[],"column":-1}
	# Neither the temporary calculation nor a visitor can reserve a slot or
	# rewrite an already admitted member's footprint/position. _pack_next only
	# reads this context; its Rect2i values and returned cell Array are local.
	return _pack_next(packing,span,validator)

static func _pack_next(packing: Dictionary, span: int, validator: Callable) -> Dictionary:
	var none: Dictionary={"ok":false,"cell":[],"column":-1}
	if span<1:return none
	var front: Vector2i=packing.front
	var right: Vector2i=packing.right
	for column: int in range(packing.depths.size()):
		var edge: Vector2i=packing.edge-right*column*2+front*int(packing.depths[column])+right*int((span-1)/2)
		var opposite: Vector2i=edge-right*(span-1)+front*(span-1)
		var low: Vector2i=edge.min(opposite)
		var rect: Rect2i=Rect2i(low,Vector2i.ONE*span)
		# Keep exactly one or more free cells between different columns. Move
		# only this candidate laterally; earlier placements never move for it.
		var lower: int=-2147483647
		var upper: int=2147483647
		var lateral: Vector2i=_pack_interval(rect,right)
		var longitudinal: Vector2i=_pack_interval(rect,front)
		for placed: Dictionary in packing.rects:
			if int(placed.column)==column:continue
			var other_depth: Vector2i=_pack_interval(placed.rect,front)
			if longitudinal.y<=other_depth.x or other_depth.y<=longitudinal.x:continue
			var other_side: Vector2i=_pack_interval(placed.rect,right)
			if int(placed.column)<column:upper=mini(upper,other_side.x-1-lateral.y)
			else:lower=maxi(lower,other_side.y+1-lateral.x)
		if lower>upper:continue
		var shift: int=clampi(0,lower,upper)
		rect.position+=right*shift
		if not _pack_fixed_space(rect,front,packing.walls,packing.bounds):continue
		var cell: Array=[rect.position.x,rect.position.y]
		if validator.is_valid() and not validator.call(packing.placements.size(),cell):continue
		return {"ok":true,"cell":cell,"column":column,"rect":rect}
	return none

static func _pack_interval(rect: Rect2i, direction: Vector2i) -> Vector2i:
	var a: int=rect.position.x*direction.x+rect.position.y*direction.y
	var b: int=rect.end.x*direction.x+rect.end.y*direction.y
	return Vector2i(mini(a,b),maxi(a,b))

static func _pack_fixed_space(rect: Rect2i, front: Vector2i, walls: Array, floor_bounds: Rect2i) -> bool:
	# The candidate and two full cells in front of its rear end must fit.
	var corridor: Rect2i=rect.merge(Rect2i(rect.position+front*2,rect.size))
	if not floor_bounds.encloses(corridor):return false
	for wall: Dictionary in walls:
		var horizontal: bool=str(wall.axis)=="x"
		var line: int=int(wall.line)
		var low: int=corridor.position.y if horizontal else corridor.position.x
		var high: int=corridor.end.y if horizontal else corridor.end.x
		var across_low: int=corridor.position.x if horizontal else corridor.position.y
		var across_high: int=corridor.end.x if horizontal else corridor.end.y
		var crosses: bool=line>low and line<high
		# A wall immediately across the candidate's desk-facing edge gives
		# zero front clearance, unlike a wall at the far end of the two-cell
		# passage. Parallel walls merely touching a side remain legal.
		var perpendicular: bool=horizontal==(front.y!=0)
		var near: int=(rect.position.y if horizontal else rect.position.x) if front.x+front.y>0 else (rect.end.y if horizontal else rect.end.x)
		if perpendicular and line==near:crosses=true
		if crosses and int(wall.low)<across_high and int(wall.high)>across_low:return false
	return true
