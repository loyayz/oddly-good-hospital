extends SceneTree
const Old = preload("res://baseline.gd")
const New = preload("res://current.gd")
var count: int = 0
func _initialize() -> void:
	var u: Rect2 = Rect2(0,0,1,1)
	for case: Array in [
		[u,u,Rect2(1,0,1,1),Rect2(1,0,1,1),false],
		[u,u,Rect2(0.5,0.5,1,1),Rect2(0.5,0.5,1,1),true],
		[u,Rect2(2,0,1,1),Rect2(2,0,1,1),u,true],
		[u,Rect2(1,0,1,1),Rect2(2,0,1,1),Rect2(2,0,1,1),false],
		[u,Rect2(2,2,1,1),Rect2(0,2,1,1),Rect2(0,2,1,1),false],
		[u,Rect2(2,2,1,1),Rect2(1,1,1,1),Rect2(1,1,1,1),true],
		[u,Rect2(-1,0,1,1),Rect2(1,0,1,1),Rect2(1,0,1,1),false],
		[u,Rect2(0,0,2,1),Rect2(1.5,0,1,1),Rect2(1.5,0,1,1),true],
		[u,Rect2(0,0,0.5,1),Rect2(0.75,0,1,1),Rect2(0.75,0,1,1),true]
	]:
		if Old.intersects(case[0],case[1],case[2],case[3])!=case[4] or New.intersects(case[0],case[1],case[2],case[3])!=case[4]:
			push_error("Explicit boundary expectation failed "+str(case)); quit(1); return
		count+=1
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 742192
	var samples: Array = []
	for i: int in 100000:
		var rects: Array[Rect2] = []
		for r: int in 4:
			var scale: float = 1.0 if i%3 else 0.0001
			rects.append(Rect2(rng.randf_range(-4,4)*scale,rng.randf_range(-4,4)*scale,rng.randf_range(0.01,3)*scale,rng.randf_range(0.01,3)*scale))
		var expected: bool = Old.intersects(rects[0],rects[1],rects[2],rects[3])
		if New.intersects(rects[0],rects[1],rects[2],rects[3])!=expected:
			push_error("Mismatch "+str(rects)); quit(1); return
		count+=1
		if i<1024: samples.append(rects)
	# A stationary pair must agree with Godot's independently implemented
	# strict rectangle predicate, including float32-adjacent edge positions.
	for delta: float in [-0.000001,-0.0000001,0.0,0.0000001,0.000001]:
		for x: int in 96:
			var a: Rect2 = Rect2(x,0,1,1)
			var b: Rect2 = Rect2(x+1.0+delta,0,1,1)
			if New.intersects(a,a,b,b)!=a.intersects(b,false): quit(3); return
			count+=1
	# Every grid combination retains exact edge contact as a distinct case.
	for x: int in range(-3,4):
		for y: int in range(-3,4):
			for dx: int in range(-3,4):
				for dy: int in range(-3,4):
					var a1: Rect2 = Rect2(dx*0.5,dy*0.5,1,1)
					var b: Rect2 = Rect2(x*0.5,y*0.5,1,1)
					if Old.intersects(u,a1,b,b)!=New.intersects(u,a1,b,b): quit(2); return
					count+=1
	for repetition: int in 3:
		for rects: Array in samples:
			Old.intersects(rects[0],rects[1],rects[2],rects[3])
			New.intersects(rects[0],rects[1],rects[2],rects[3])
	var windows: Array = []
	var checksum: int = 0
	for index: int in 12:
		var old: bool = index%4==0 or index%4==3
		var started: int = Time.get_ticks_usec()
		var hits: int = 0
		for repetition: int in 100:
			for rects: Array in samples:
				if Old.intersects(rects[0],rects[1],rects[2],rects[3]) if old else New.intersects(rects[0],rects[1],rects[2],rects[3]): hits+=1
		windows.append({"old":old,"elapsed_us":Time.get_ticks_usec()-started,"hits":hits})
		checksum=hits
	print(JSON.stringify({"checks":count,"windows":windows,"checksum":checksum,"calls_per_window":102400,"scope":"complete production BodySweep helper; not movement or whole-step timing"}))
	quit(0)
