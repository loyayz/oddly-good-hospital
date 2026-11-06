extends SceneTree
const Current = preload("res://game/view/skinned_pose_batch.gd")
const Baseline = preload("res://game/view/baseline_pose_batch.gd")
const BOUNDS = AABB(Vector3(-10,-10,-10),Vector3(100,100,100))
var failures: Array = []
func _initialize() -> void: call_deferred("_run")
func _check(value: bool, label: String) -> void:
	if not value: failures.append(label)
func _fixture(script: Script, count: int, bones: int) -> Dictionary:
	var holder = Node3D.new()
	root.add_child(holder)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.UP])
	arrays[Mesh.ARRAY_BONES] = PackedInt32Array([0,0,0,0,0,0,0,0,0,0,0,0])
	arrays[Mesh.ARRAY_WEIGHTS] = PackedFloat32Array([1,0,0,0,1,0,0,0,1,0,0,0])
	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	mesh.surface_set_material(0,StandardMaterial3D.new())
	var skin = Skin.new()
	for bone in bones: skin.add_bind(bone,Transform3D.IDENTITY)
	var sources: Array[MeshInstance3D] = []
	var skeletons: Array[Skeleton3D] = []
	for row in count:
		var wrapper = Node3D.new()
		holder.add_child(wrapper)
		wrapper.position = Vector3(row,0,0)
		var skeleton = Skeleton3D.new()
		skeleton.name = "Skeleton"
		for bone in bones:
			skeleton.add_bone("b"+str(bone))
			skeleton.set_bone_pose_position(bone, Vector3(0,float(bone)*0.01,0))
		wrapper.add_child(skeleton)
		var source = MeshInstance3D.new()
		source.mesh = mesh
		source.skin = skin
		source.skeleton = NodePath("../Skeleton")
		wrapper.add_child(source)
		sources.append(source)
		skeletons.append(skeleton)
	var batch = script.new()
	holder.add_child(batch)
	_check(batch.bind_sources(sources,skeletons).is_empty(),"bind")
	return {"holder":holder,"batch":batch,"sources":sources,"skeletons":skeletons}
func _same(a: Dictionary, b: Dictionary, label: String) -> void:
	_check(a.batch._current_page==b.batch._current_page,label+" page")
	var index: int = a.batch._current_page
	_check(a.batch._images[index].get_data()==b.batch._images[index].get_data(),label+" pixels")
	_check(a.batch.resource_usage()==b.batch.resource_usage(),label+" resources")
	_check(a.batch._instances.visible==b.batch._instances.visible,label+" visible")
	_check(a.batch._instances.custom_aabb==b.batch._instances.custom_aabb,label+" bounds")
	_check(b.batch._instances.custom_aabb==BOUNDS,label+" expected bounds")
	for row in a.sources.size():
		_check(a.sources[row].visible==b.sources[row].visible,label+" original visibility")
		_check(not b.sources[row].visible,label+" original hidden")
	# The headless dummy RenderingServer does not retain instance buffers.
	# Do not mistake equal default getter values for a successful readback.
	var image: Image = b.batch._images[index]
	_check(image.get_pixel(0,0).is_equal_approx(Color(1,0,0,0)),label+" actual matrix basis")
	for row: int in image.get_height():
		for column: int in image.get_width():
			if row>=b.sources.size() or column>=b.batch._bone_count*3:
				_check(image.get_pixel(column,row)==Color(0,0,0,0),label+" zero padding")

func _run() -> void:
	for shape in [[1,1],[3,21],[64,40]]:
		var a = _fixture(Baseline,shape[0],shape[1])
		var b = _fixture(Current,shape[0],shape[1])
		for iteration in 6:
			for f in [a,b]:
				f.batch.position = Vector3(iteration*0.25,iteration*0.1,1)
				f.sources[0].get_parent().rotation.y = iteration*0.02
				f.skeletons[0].set_bone_pose_position(0,Vector3(0,iteration*0.05,0))
			_check(a.batch.publish(BOUNDS) and b.batch.publish(BOUNDS),"publish")
			_same(a,b,"frame "+str(iteration))
		# Fail after some rows were written, then fully overwrite the page.
		for f in [a,b]: f.sources[-1].scale = Vector3(2,1,1)
		_check(not a.batch.publish(BOUNDS) and not b.batch.publish(BOUNDS),"suspend scaled")
		for f in [a,b]: f.sources[-1].scale = Vector3.ONE
		_check(a.batch.publish(BOUNDS) and b.batch.publish(BOUNDS),"recover scaled")
		_same(a,b,"recover")
		_check(not a.batch.publish(AABB()) and not b.batch.publish(AABB()),"empty bounds")
		_check(a.batch.publish(BOUNDS) and b.batch.publish(BOUNDS),"recover bounds")
		_same(a,b,"bounds recovery")
		for f in [a,b]:
			var rebound_meshes: Array[MeshInstance3D] = [f.sources[0]]
			var rebound_skeletons: Array[Skeleton3D] = [f.skeletons[0]]
			_check(f.batch.bind_sources(rebound_meshes,rebound_skeletons).is_empty(),"rebind")
			f.sources = [f.sources[0]]
		_check(a.batch.publish(BOUNDS) and b.batch.publish(BOUNDS),"publish rebound")
		_same(a,b,"rebound")
		a.holder.free()
		b.holder.free()
	print(JSON.stringify({"functional_ok":failures.is_empty(),"failures":failures,"multimesh_server_readback_verified":false,"readback_limit":"headless dummy RenderingServer returns default instance values; CPU Image matrices and node state only"}))
	if not failures.is_empty(): quit(1); return
	var a = _fixture(Baseline,64,21)
	var b = _fixture(Current,64,21)
	for f in [a,b]:
		for repeat in 30: f.batch.publish(BOUNDS)
	var windows: Array = []
	for index in 12:
		var current: bool = (index%4) in [1,2]
		var f: Dictionary = b if current else a
		var started = Time.get_ticks_usec()
		for repeat in 200:
			if not f.batch.publish(BOUNDS): failures.append("benchmark publication failed")
		var elapsed = Time.get_ticks_usec()-started
		windows.append({"index":index,"variant":"current" if current else "baseline","publications":200,"elapsed_us":elapsed})
	print(JSON.stringify({"benchmark_scope":"Linux Godot 4.6.3 headless CPU publication; no visible render/GPU/FPS claim","rows":64,"bones":21,"windows":windows,"functional_ok":failures.is_empty()}))
	a.holder.free()
	b.holder.free()
	quit(0 if failures.is_empty() else 1)
