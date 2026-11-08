extends RefCounted

# Optional single-column local geometry, not occupancy, priority or a reservation.
# slots must be the complete front-to-tail plan for this common body span, not
# actor-filtered slots. Caller verifies floor/desk identity and actually routes to
# the first entry hint; this helper never assumes a straight remote approach.
# Points omit the final destination. No hint means use the ordinary movement.
static func hints(slots: Array, span: int, rotation: int, start: Vector2, goal: Vector2, service_cell: Vector2, entering: bool, fixed: RouteClearance) -> Array:
	if slots.is_empty() or span<1 or fixed==null: return []
	if not start.is_finite() or not goal.is_finite() or not service_cell.is_finite(): return []
	var front: Vector2=[Vector2.DOWN,Vector2.LEFT,Vector2.UP,Vector2.RIGHT][posmod(rotation,4)]
	var right: Vector2=Vector2(front.y,-front.x)
	var points: Array[Vector2]=[]
	for cell: Variant in slots:
		if not cell is Array or cell.size()!=2: return []
		var point: Vector2=Vector2(float(cell[0]),float(cell[1]))
		if not point.is_finite(): return []
		if not points.is_empty() and point!=points.back()+front*span: return []
		points.append(point)
	# The caller must supply the actual actor envelope's structural query.
	# A larger common slot span is fine; a smaller one cannot prove an aisle.
	if fixed._size>span: return []
	var head: Vector2=points[0]
	var tail: Vector2=points.back()+front*span
	var right_tail: Vector2=tail+right*span
	var left_tail: Vector2=tail-right*span
	# Prove both side aisles and the rear cross-aisle using real fixed geometry.
	# In particular a large body does not inherit the one-cell proof.
	if not fixed.sweep_reason(head+right*span,right_tail).is_empty(): return []
	if not fixed.sweep_reason(head-right*span,left_tail).is_empty(): return []
	if not fixed.sweep_reason(left_tail,right_tail).is_empty(): return []
	if entering:
		var target_known: bool=false
		for point: Vector2 in points:
			if goal.distance_to(point)<0.001: target_known=true; break
		if not target_known: return []
		var beside: Vector2=goal+right*span
		if not fixed.sweep_reason(beside,goal).is_empty(): return []
		return _compact([beside],start)
	var origin_known: bool=start.distance_to(service_cell)<0.001 or bounds(slots,span).encloses(Rect2(start,Vector2.ONE*fixed._size))
	for point: Vector2 in points:
		if start.distance_to(point)<0.001: origin_known=true; break
	if not origin_known: return []
	# Service cells may lie beside the head. Connect to the same left aisle,
	# without moving backwards through a queue or crossing the desk body.
	var depth: float=(start-head).dot(front)
	if depth < -0.001 or depth > (points.back()-head).dot(front)+0.001: return []
	var beside: Vector2=head-right*span+front*depth
	if not fixed.sweep_reason(start,beside).is_empty(): return []
	if not fixed.sweep_reason(beside,left_tail).is_empty(): return []
	return _compact([beside,left_tail],start)

static func _compact(points: Array, start: Vector2) -> Array:
	var result: Array=[]
	var previous: Vector2=start
	for point: Vector2 in points:
		if previous.distance_to(point)>=0.001: result.append(point)
		previous=point
	return result

# Occupied slot footprint only: never includes the circulation aisles.
static func bounds(slots: Array, span: int) -> Rect2:
	if slots.is_empty() or span<1: return Rect2()
	var result: Rect2=Rect2()
	var first: bool=true
	for cell: Variant in slots:
		if not cell is Array or cell.size()!=2: return Rect2()
		var point: Vector2=Vector2(float(cell[0]),float(cell[1]))
		if not point.is_finite(): return Rect2()
		var rect: Rect2=Rect2(point,Vector2.ONE*span)
		result=rect if first else result.merge(rect)
		first=false
	return result

# First-leg contract is explicit. "remote" needs ordinary static routing to
# points[0] with the queue excluded; "local" has every leg proved here.
# "direct" leaves the existing head-to-service route unchanged. "none" falls
# back; it is not permission to cross an occupied slot.
static func service_approach(slots: Array, span: int, rotation: int, start: Vector2, service_cell: Vector2, fixed: RouteClearance) -> Dictionary:
	var none: Dictionary={"mode":"none","points":[]}
	if slots.is_empty() or span<1 or fixed==null: return none
	if not start.is_finite() or not service_cell.is_finite(): return none
	var front: Vector2=[Vector2.DOWN,Vector2.LEFT,Vector2.UP,Vector2.RIGHT][posmod(rotation,4)]
	var right: Vector2=Vector2(front.y,-front.x)
	var points: Array[Vector2]=[]
	for cell: Variant in slots:
		if not cell is Array or cell.size()!=2: return none
		var point: Vector2=Vector2(float(cell[0]),float(cell[1]))
		if not point.is_finite(): return none
		if not points.is_empty() and point!=points.back()+front*span: return none
		points.append(point)
	if fixed._size>span: return none
	var head: Vector2=points[0]
	if start.distance_to(head)<0.001:
		return {"mode":"direct","points":[]}
	if start.distance_to(service_cell)<0.001:
		return {"mode":"direct","points":[]}
	# Only a head-adjacent service point can be connected without crossing the
	# queue longitudinally. More exotic facility layouts use ordinary routing.
	if absf((service_cell-head).dot(front))>0.001: return none
	var left_head: Vector2=head-right*span
	var left_tail: Vector2=points.back()+front*span-right*span
	if not fixed.sweep_reason(left_head,left_tail).is_empty(): return none
	if not fixed.sweep_reason(left_head,service_cell).is_empty(): return none
	# A service point on the far/right side would cross the head slot. Do not
	# claim that a static-only proof has made that future crossing permissible.
	if (service_cell-head).dot(right)>0.001: return none
	for point: Vector2 in points:
		if start.distance_to(point)<0.001:
			var beside: Vector2=point-right*span
			if not fixed.sweep_reason(start,beside).is_empty(): return none
			return {"mode":"local","points":_compact([beside,left_head],start)}
	return {"mode":"remote","points":_compact([left_tail,left_head],start)}
