class_name BodySweep
extends RefCounted

# Exact overlap interval for two linearly moving axis-aligned envelopes.
# Broadphase rectangles only identify candidates; touching edges remain legal.
static func intersects(a0: Rect2, a1: Rect2, b0: Rect2, b1: Rect2) -> bool:
	var initial: Array[float] = [a0.position.x-b0.end.x,b0.position.x-a0.end.x,a0.position.y-b0.end.y,b0.position.y-a0.end.y]
	var final: Array[float] = [a1.position.x-b1.end.x,b1.position.x-a1.end.x,a1.position.y-b1.end.y,b1.position.y-a1.end.y]
	var enter: float = 0.0
	var leave: float = 1.0
	for index: int in 4:
		var change: float = final[index]-initial[index]
		if change==0.0:
			if initial[index]>=0.0:
				return false
			continue
		var boundary: float = -initial[index]/change
		if change>0.0:
			leave = minf(leave,boundary)
		else:
			enter = maxf(enter,boundary)
		if enter>=leave:
			return false
	return enter<leave
