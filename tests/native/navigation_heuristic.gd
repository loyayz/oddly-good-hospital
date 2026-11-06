extends SceneTree
const Old=preload('res://baseline.gd')
const New=preload('res://current.gd')
func _initialize()->void:
	var a=Old.new();var b=New.new()
	var rng=RandomNumberGenerator.new();rng.seed=93721
	var inputs:Array=[]
	for i:int in 200000:
		var x:int=rng.randi_range(0,95);var y:int=rng.randi_range(0,95)
		var u:int=rng.randi_range(0,95);var v:int=rng.randi_range(0,95)
		var f:int=y*96+x;var t:int=v*96+u
		assert(a._estimate_cost(f,t)==float(absi(x-u)+absi(y-v)))
		assert(a._estimate_cost(f,t)==b._estimate_cost(f,t))
		if i<1024:inputs.append([f,t])
	for g:AStar2D in [a,b]:
		g.reserve_space(9216)
		for id:int in 9216:g.add_point(id,Vector2(id%96,id/96))
		for id:int in 9216:
			if id%96<95:g.connect_points(id,id+1)
			if id/96<95:g.connect_points(id,id+96)
		for y:int in range(5,90):
			if y%13:g.set_point_disabled(y*96+42,true)
	for i:int in 200:
		var f:int=inputs[i][0];var t:int=inputs[i][1]
		assert(a.get_id_path(f,t)==b.get_id_path(f,t))
	var windows:Array=[]
	for round:int in 12:
		var old:bool=round%4 in [0,3]
		var g= a if old else b
		var checksum:float=0
		var start:int=Time.get_ticks_usec()
		for n:int in 100:
			for p:Array in inputs:checksum+=g._estimate_cost(p[0],p[1])
		windows.append({'old':old,'us':Time.get_ticks_usec()-start,'checksum':checksum})
	var search_windows:Array=[]
	for round:int in 12:
		var old:bool=round%4 in [0,3]
		var g= a if old else b
		var checksum:int=0
		var start:int=Time.get_ticks_usec()
		for i:int in 200:
			checksum+=g.get_id_path(inputs[i][0],inputs[i][1]).size()
		search_windows.append({'old':old,'us':Time.get_ticks_usec()-start,'checksum':checksum})
	print(JSON.stringify({'checks':200000,'paths':200,'windows':windows,'search_windows':search_windows}))
	quit()
