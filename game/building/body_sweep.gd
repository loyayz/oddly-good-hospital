class_name BodySweep
extends RefCounted

# Exact overlap interval for two linearly moving axis-aligned envelopes.
# Broadphase rectangles only identify candidates; touching edges remain legal.
static func intersects(a0: Rect2, a1: Rect2, b0: Rect2, b1: Rect2) -> bool:
	# Keep scalar float arithmetic and the original half-space order. Vector4
	# would narrow these differences to float32; temporary Arrays cost each pair.
	var enter: float = 0.0
	var leave: float = 1.0
	var initial: float
	var change: float
	var boundary: float
	initial = a0.position.x-b0.end.x
	change = a1.position.x-b1.end.x-initial
	if change==0.0:
		if initial>=0.0: return false
	else:
		boundary = -initial/change
		if change>0.0: leave = minf(leave,boundary)
		else: enter = maxf(enter,boundary)
		if enter>=leave: return false
	initial = b0.position.x-a0.end.x
	change = b1.position.x-a1.end.x-initial
	if change==0.0:
		if initial>=0.0: return false
	else:
		boundary = -initial/change
		if change>0.0: leave = minf(leave,boundary)
		else: enter = maxf(enter,boundary)
		if enter>=leave: return false
	initial = a0.position.y-b0.end.y
	change = a1.position.y-b1.end.y-initial
	if change==0.0:
		if initial>=0.0: return false
	else:
		boundary = -initial/change
		if change>0.0: leave = minf(leave,boundary)
		else: enter = maxf(enter,boundary)
		if enter>=leave: return false
	initial = b0.position.y-a0.end.y
	change = b1.position.y-a1.end.y-initial
	if change==0.0:
		if initial>=0.0: return false
	else:
		boundary = -initial/change
		if change>0.0: leave = minf(leave,boundary)
		else: enter = maxf(enter,boundary)
		if enter>=leave: return false
	return enter<leave
