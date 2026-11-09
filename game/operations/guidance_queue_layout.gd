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

# Actual-body snake. Shapes are the engine's four cardinal _actor_rect values
# at cell zero; their offsets are retained when converting back to actor cells.
# No wall-depth capacity, column gap, rear passage or occupancy is planned here.
static func snake(facility: Dictionary, bodies: Array) -> Dictionary:
	var turn: int=posmod(int(facility.get("rotation",0)),4)
	var front: Vector2=[Vector2.DOWN,Vector2.LEFT,Vector2.UP,Vector2.RIGHT][turn]
	var right:=Vector2(front.y,-front.x)
	var origin:=Vector2(float(facility.cell[0]),float(facility.cell[1]))
	var size:=Vector2(float(facility.footprint[0]),float(facility.footprint[1]))
	var edge: Vector2=origin
	match turn:
		0:edge+=Vector2(size.x*0.5,size.y)
		1:edge+=Vector2(0,size.y*0.5)
		2:edge+=Vector2(size.x*0.5,0)
		3:edge+=Vector2(size.x,size.y*0.5)
	var width: float=size.x if front.x==0 else size.y
	var result: Dictionary={"placements":[],"front":front,"right":right,"edge":edge,"width":width,"row":0,"row_top":0.0,"bottom":0.0,"single":false,"front_anchor":facility.get("queue_front_cell",[]).duplicate()}
	for body: Dictionary in bodies:
		var placement: Dictionary=snake_append(result,body)
		if placement.is_empty():return {}
		snake_accept(result,placement)
	return result

# Read-only probe: a walking visitor must not alter the accepted queue.
static func snake_append(packing: Dictionary, body: Dictionary) -> Dictionary:
	if packing.is_empty() or body.get("shapes",[]).size()!=4:return {}
	var front: Vector2=packing.front
	var right: Vector2=packing.right
	var rows: Array=packing.placements
	var row: int=int(packing.row)
	var row_top: float=float(packing.row_top)
	var single: bool=bool(packing.single)
	var direction: float=1.0 if row%2==0 else -1.0
	var facing: float=atan2(-front.x,-front.y)
	var shape: Rect2=_snake_shape(body,facing)
	var size: Vector2=_snake_size(shape,right,front)
	var local: Rect2
	if rows.is_empty():
		# The existing service anchor is a cell-envelope origin, not a body
		# edge. Borrow only its normal coordinate; the actual body remains
		# centered on the desk and retains its own engine shape offset.
		var anchor: Array=packing.get("front_anchor",[])
		if anchor.size()==2:
			var anchor_point:=Vector2(float(anchor[0]),float(anchor[1]))
			var shape_front: float=shape.position.dot(front)+minf(0.0,shape.size.x*front.x)+minf(0.0,shape.size.y*front.y)
			row_top=anchor_point.dot(front)-Vector2(packing.edge).dot(front)+shape_front
		local=Rect2(Vector2(-size.x*0.5,row_top),size)
	else:
		var previous: Rect2=rows.back().local_rect
		var lateral_facing: float=atan2(-right.x*direction,-right.y*direction)
		var lateral_shape: Rect2=_snake_shape(body,lateral_facing)
		var lateral_size: Vector2=_snake_size(lateral_shape,right,front)
		# A desk too narrow for two actual adjacent bodies is a single
		# file, left aligned with its predecessor rather than edge zigzags.
		if rows.size()==1 and previous.size.x+lateral_size.x>float(packing.width)+0.000001:single=true
		if single:
			local=Rect2(Vector2(previous.position.x,previous.end.y),size)
		else:
			facing=lateral_facing
			shape=lateral_shape
			size=lateral_size
			var x: float=previous.end.x if direction>0 else previous.position.x-size.x
			# Left edge in the patient's facing frame: bottom for left-facing
			# people, top for right-facing people. Large bodies use real depth.
			var y: float=previous.end.y-size.y if direction>0 else previous.position.y
			local=Rect2(Vector2(x,maxf(row_top,y)),size)
			if local.end.x>float(packing.width)*0.5+0.000001 or local.position.x< -float(packing.width)*0.5-0.000001:
				row+=1
				row_top=float(packing.bottom)
				facing=atan2(-front.x,-front.y)
				shape=_snake_shape(body,facing)
				size=_snake_size(shape,right,front)
				# Alternating rows begin at the actual desk edge. An oversized
				# body may extend beyond it, never shrink to a nominal grid cell.
				x=float(packing.width)*0.5-size.x if row%2==1 else -float(packing.width)*0.5
				local=Rect2(Vector2(x,row_top),size)
	var a: Vector2=packing.edge+right*local.position.x+front*local.position.y
	var b: Vector2=packing.edge+right*local.end.x+front*local.end.y
	var rect:=Rect2(a.min(b),(a-b).abs())
	var cell: Vector2=rect.position-shape.position
	return {"cell":[cell.x,cell.y],"facing":facing,"rect":rect,"row":row,"local_rect":local,"row_top":row_top,"single":single}

# Only an actual accepted queue member is appended. This is deliberately
# separate from snake_append, which is safe to use for a destination probe.
static func snake_accept(packing: Dictionary, placement: Dictionary) -> void:
	packing.placements.append(placement)
	packing.row=int(placement.row)
	packing.row_top=float(placement.row_top)
	packing.single=bool(placement.single)
	packing.bottom=maxf(float(packing.bottom),float(placement.local_rect.end.y))

static func snake_next(facility: Dictionary, bodies: Array, body: Dictionary) -> Dictionary:
	return snake_append(snake(facility,bodies),body)

static func _snake_shape(body: Dictionary, facing: float) -> Rect2:
	return body.shapes[posmod(roundi(facing/(PI*0.5)),4)]

static func _snake_size(shape: Rect2, right: Vector2, front: Vector2) -> Vector2:
	return Vector2(absf(right.x)*shape.size.x+absf(right.y)*shape.size.y,absf(front.x)*shape.size.x+absf(front.y)*shape.size.y)
