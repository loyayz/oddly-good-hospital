extends SceneTree
const Before = preload("res://baseline.gd")
const After = preload("res://current.gd")
const World = preload("res://world.gd")
class LayoutInput:
	extends RefCounted
	var footprint: Array = [1,1]
	var calls: int = 0
	func facility_layout(_world: RefCounted, id: String) -> Dictionary:
		assert(id=="facility")
		calls += 1
		return {"footprint":footprint}

func expected(cell: Array, size: Array, coverage: Dictionary) -> bool:
	for key: String in coverage:
		var parts: PackedStringArray = key.split(":")
		var x: int = int(parts[0])
		var y: int = int(parts[1])
		if x>=int(cell[0]) and x<int(cell[0])+int(size[0]) and y>=int(cell[1]) and y<int(cell[1])+int(size[1]): return true
	return false

func _initialize() -> void:
	var before = Before.new()
	var after = After.new()
	var adapter: LayoutInput = LayoutInput.new()
	before.space = adapter
	after.space = adapter
	var world = World.new()
	var checks: int = 0
	for size: Array in [[0,0],[0,3],[3,0],[1,1],[1,4],[2,3],[3,3],[4,4],[8,8]]:
		adapter.footprint = size
		for cell: Array in [[0,0],[-3,-5],[95,95],[4.9,5.1],[-2.9,-3.1]]:
			var f: Dictionary = {"id":"facility","cell":cell,"footprint":[99,99]}
			for dx: int in range(-1,10):
				for dy: int in range(-1,10):
					var coverage: Dictionary = {}
					coverage["%d:%d"%[int(cell[0])+dx,int(cell[1])+dy]] = false
					var original: Dictionary = f.duplicate(true)
					var want: bool = expected(cell,size,coverage)
					assert(before._facility_in_coverage(world,f,coverage)==want)
					assert(after._facility_in_coverage(world,f,coverage)==want)
					assert(f==original)
					checks += 1
			assert(not before._facility_in_coverage(world,f,{}))
			assert(not after._facility_in_coverage(world,f,{}))
			checks += 1
	var windows: Array = []
	var f: Dictionary = {"id":"facility","cell":[4,5]}
	var cases: Array = [{},{"4:5":true},{"6:7":true},{"7:7":true}]
	for size: Array in [[1,1],[3,3],[8,8]]:
		adapter.footprint = size
		for warm in 100:
			for c: Dictionary in cases:
				before._facility_in_coverage(world,f,c)
				after._facility_in_coverage(world,f,c)
		for cycle in 3:
			for old: bool in [true,false,false,true]:
				var object = before if old else after
				var start: int = Time.get_ticks_usec()
				var checksum: int = 0
				for repetition in 3000:
					for c: Dictionary in cases:
						checksum += int(object._facility_in_coverage(world,f,c))
				windows.append({"size":size.duplicate(),"old":old,"elapsed_us":Time.get_ticks_usec()-start,"checksum":checksum})
	print(JSON.stringify({"checks":checks,"calls_per_window":12000,"windows":windows,"scope":"real footprint membership function; explicit facility-layout input adapter; no full-game claim"}))
	quit()
