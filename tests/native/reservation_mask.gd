extends SceneTree
const Before = preload("res://baseline.gd")
const After = preload("res://current.gd")

func empty_mask() -> PackedByteArray:
	var mask: PackedByteArray = PackedByteArray()
	mask.resize(9216)
	mask.fill(0)
	return mask

func expected(size: int, offset: Vector2, reservations: Array, original: PackedByteArray) -> PackedByteArray:
	var mask: PackedByteArray = original.duplicate()
	for y: int in 96:
		for x: int in 96:
			var body: Rect2 = Rect2(Vector2(x,y)+offset,Vector2.ONE*size)
			for reservation: Dictionary in reservations:
				for region: Rect2 in reservation.regions:
					if body.intersects(region,false): mask[y*96+x] = 1
	return mask

func _initialize() -> void:
	var before = Before.new()
	var after = After.new()
	var regions: Array = [[],[Rect2(0,0,1,1)],[Rect2(5.25,7.75,2.5,3.5)],[Rect2(-4,-3,8,8)],[Rect2(95,95,3,3)],[Rect2(1,1,8,8),Rect2(3,3,4,4)],[Rect2(7,7,0,0)]]
	var checks: int = 0
	for size: int in [1,2,3,8]:
		before._size = size
		after._size = size
		for offset: Vector2 in [Vector2.ZERO,Vector2(0.25,-0.5),Vector2(-1,2),Vector2(95.5,95.5)]:
			for values: Array in regions:
				var reservations: Array = [{"regions":values}]
				before._reservations = reservations
				after._reservations = reservations
				for filled: bool in [false,true]:
					var original: PackedByteArray = empty_mask()
					if filled:
						for id: int in range(0,9216,17): original[id] = 1
					var want: PackedByteArray = expected(size,offset,reservations,original)
					assert(before._mark_reservation_mask(original.duplicate(),offset)==want)
					assert(after._mark_reservation_mask(original.duplicate(),offset)==want)
					checks += 9216
	var windows: Array = []
	for extent: int in [0,1,8,32]:
		var reservations: Array = [] if extent==0 else [{"regions":[Rect2(4.25,4.5,extent,extent),Rect2(6.5,7.75,extent,extent)]}]
		before._size = 2
		after._size = 2
		before._reservations = reservations
		after._reservations = reservations
		var original: PackedByteArray = empty_mask()
		for warm in 30:
			before._mark_reservation_mask(original.duplicate(),Vector2(0.25,-0.5))
			after._mark_reservation_mask(original.duplicate(),Vector2(0.25,-0.5))
		for cycle in 3:
			for old: bool in [true,false,false,true]:
				var object = before if old else after
				var start: int = Time.get_ticks_usec()
				var checksum: int = 0
				for repetition in 500:
					var result: PackedByteArray = object._mark_reservation_mask(original.duplicate(),Vector2(0.25,-0.5))
					checksum += result[6*96+6]
				windows.append({"extent":extent,"old":old,"elapsed_us":Time.get_ticks_usec()-start,"checksum":checksum})
	print(JSON.stringify({"cell_checks":checks,"calls_per_window":500,"windows":windows,"scope":"complete production mask helper and exact engine rectangles; not authorization or full navigation"}))
	quit()
