extends RefCounted
const Layout=preload("res://game/operations/guidance_queue_layout.gd")

func run_packing() -> Dictionary:
	var checks: Dictionary={}
	var bounds: Rect2i=Rect2i(0,0,96,96)
	var desk: Dictionary={"cell":[50,73],"footprint":[2,1],"rotation":0}
	var walls: Array=[{"axis":"x","line":79,"low":0,"high":96}]
	var ordinary: Dictionary=Layout.pack(desk,walls,bounds,[1,1,1])
	var before: Dictionary=ordinary.duplicate(true)
	var big: Dictionary=Layout.probe(ordinary,3)
	checks.three_small=ordinary.complete and ordinary.placements==[[51,74],[51,75],[51,76]]
	checks.borrowed_immutable_walls=is_same(ordinary.walls,walls)
	checks.wall_input_unchanged=walls==[{"axis":"x","line":79,"low":0,"high":96}]
	var detached: Dictionary=Layout.pack(desk,walls,bounds,[1])
	var detached_before: Dictionary=detached.duplicate(true)
	var temporary: Dictionary=Layout.probe(detached,1)
	temporary.cell[0]=-99
	checks.probe_output_does_not_alias_members=detached==detached_before

	checks.remote_big_no_place=not big.ok and ordinary==before
	var two: Dictionary=Layout.pack(desk,walls,bounds,[1,1])
	var two_before: Dictionary=two.duplicate(true)
	checks.two_small_unchanged=not Layout.probe(two,3).ok and two==two_before and two.placements==[[51,74],[51,75]]
	var empty: Dictionary=Layout.pack(desk,walls,bounds,[])
	checks.empty_accepts_big=Layout.probe(empty,3).ok
	var only_big: Dictionary=Layout.pack(desk,walls,bounds,[3])
	checks.big_fills_depth=only_big.complete and not Layout.probe(only_big,1).ok
	var deeper: Array=[{"axis":"x","line":81,"low":0,"high":96}]
	var mixed: Dictionary=Layout.pack(desk,deeper,bounds,[1,2,1])
	checks.mixed_actual_depth=mixed.complete and mixed.placements==[[51,74],[50,75],[51,77]]
	checks.mixed_remaining_one=Layout.probe(mixed,1).ok and not Layout.probe(mixed,2).ok
	var departed: Dictionary=Layout.pack(desk,deeper,bounds,[2,1])
	checks.departure_compresses=departed.complete and departed.placements==[[50,74],[51,76]]
	var too_many: Dictionary=Layout.pack(desk,walls,bounds,[3,1,1])
	checks.no_skip_failed_member=not too_many.complete and too_many.placements[1]==[] and too_many.placements[2]==[] and not Layout.probe(too_many,1).ok
	for turn: int in 4:
		var d: Dictionary={"cell":[40,40],"footprint":[2,1] if turn%2==0 else [1,2],"rotation":turn}
		var front: Vector2i=[Vector2i.DOWN,Vector2i.LEFT,Vector2i.UP,Vector2i.RIGHT][turn]
		var packed: Dictionary=Layout.pack(d,[],bounds,[1,2,1])
		var a: Vector2i=Vector2i(packed.placements[0][0],packed.placements[0][1])
		var b: Vector2i=Vector2i(packed.placements[1][0],packed.placements[1][1])
		var c: Vector2i=Vector2i(packed.placements[2][0],packed.placements[2][1])
		# Use projected occupied intervals, not raw low corners, for reverse facings.
		var ia: Vector2i=Layout._pack_interval(Rect2i(a,Vector2i.ONE),front)
		var ib: Vector2i=Layout._pack_interval(Rect2i(b,Vector2i.ONE*2),front)
		var ic: Vector2i=Layout._pack_interval(Rect2i(c,Vector2i.ONE),front)
		checks["rotation_"+str(turn)]=packed.complete and ia.y==ib.x and ib.y==ic.x
		var near: int=(a.y if front.y!=0 else a.x)+(1 if front.x+front.y<0 else 0)
		for gap: int in [0,1,2,3]:
			var barrier: Array=[{"axis":"x" if front.y!=0 else "y","line":near+(front.x+front.y)*gap,"low":0,"high":96}]
			checks["wall_rotation_"+str(turn)+"_"+str(gap)]=Layout.pack(d,barrier,bounds,[1]).complete==(gap==3)

		var deny: Callable=func(_index: int,_cell: Array)->bool:return false
		checks["validator_reject_"+str(turn)]=not Layout.pack(d,[],bounds,[1],deny).complete
	var wide: Dictionary={"cell":[40,40],"footprint":[4,1],"rotation":0}
	var short_wall: Array=[{"axis":"x","line":46,"low":0,"high":96}]
	var multi: Dictionary=Layout.pack(wide,short_wall,bounds,[3,2])
	checks.multicolumn=multi.complete and multi.columns==[0,1]
	var ra: Rect2i=multi.rects[0].rect
	var rb: Rect2i=multi.rects[1].rect
	checks.multicolumn_one_gap=rb.end.x+1<=ra.position.x
	checks.multicolumn_keeps_first=multi.placements[0]==Layout.pack(wide,short_wall,bounds,[3]).placements[0]
	var wall_hit: Array=[{"axis":"x","line":75,"low":0,"high":96}]
	checks.wall_preserves_two=not Layout.pack(desk,wall_hit,bounds,[1]).complete
	var seen: Array=[]
	var inspect: Callable=func(index: int,cell: Array)->bool:seen.append([index,cell.duplicate()]);return true
	var checked: Dictionary=Layout.pack(desk,walls,bounds,[1,1],inspect)
	Layout.probe(checked,1,inspect)
	checks.validator_indices=seen==[[0,[51,74]],[1,[51,75]],[2,[51,76]]]
	var passed: bool=true
	for value: bool in checks.values():passed=passed and value
	return {"passed":passed,"checks":checks,"scope":"pure actual-member packing; no actual movement or dynamic occupancy proof"}
