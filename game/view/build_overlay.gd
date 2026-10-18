class_name HospitalBuildOverlay
extends MeshInstance3D

var _basis: Dictionary = {}

func show_preview(draft: Dictionary, result: Dictionary, floor_id: int) -> void:
	var basis: Dictionary = {"draft":draft,"ready":result.get("ready",false),"ok":result.get("ok",false),"blocked":result.get("blocked_cells",[]),"floor_id":floor_id}
	if basis==_basis:
		return
	_basis = basis.duplicate(true)
	mesh = null
	if draft.is_empty() or int(draft.get("floor_id",floor_id))!=floor_id:
		return
	var cells: Array = draft.get("cells",[])
	var origin: Array = draft.get("origin",draft.get("cell",[0,0]))
	var size: Array = draft.get("size",[1,1])
	if cells.is_empty() and (int(size[0])<=0 or int(size[1])<=0): return
	var lines: ImmediateMesh = ImmediateMesh.new()
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.no_depth_test = true
	lines.surface_begin(Mesh.PRIMITIVE_LINES,material)
	var color: Color = Color("4d719d") if result.get("ready",false) and result.get("ok",false) else Color("7a7d83")
	if result.get("ready",false) and not result.get("ok",false):
		color = Color("b85550")
	if cells.is_empty():
		# The same rectangular cell grid needs one line per row/column, rather
		# than drawing every shared edge twice and uploading 8 vertices/cell.
		var low: Vector3 = _point(origin)
		var high: Vector3 = _point([int(origin[0])+int(size[0]),int(origin[1])+int(size[1])])
		lines.surface_set_color(color)
		for x: int in range(int(size[0])+1):
			var at: float = low.x+x*HospitalSpace.CELL_METERS
			lines.surface_add_vertex(Vector3(at,0.06,low.z))
			lines.surface_add_vertex(Vector3(at,0.06,high.z))
		for y: int in range(int(size[1])+1):
			var at: float = low.z+y*HospitalSpace.CELL_METERS
			lines.surface_add_vertex(Vector3(low.x,0.06,at))
			lines.surface_add_vertex(Vector3(high.x,0.06,at))
		for blocked: Array in result.get("blocked_cells",[]):
			if int(blocked[0])>=int(origin[0]) and int(blocked[0])<int(origin[0])+int(size[0]) and int(blocked[1])>=int(origin[1]) and int(blocked[1])<int(origin[1])+int(size[1]):
				_cell(lines,blocked,Color("b85550"))
	else:
		for cell: Array in cells: _cell(lines,cell,Color("b85550") if cell in result.get("blocked_cells",[]) else color)
	lines.surface_end()
	mesh = lines

func _point(cell: Array) -> Vector3:
	return Vector3((float(cell[0])-32.0)*HospitalSpace.CELL_METERS,0.06,(float(cell[1])-64.0)*HospitalSpace.CELL_METERS)

func _cell(lines: ImmediateMesh, cell: Array, color: Color) -> void:
	lines.surface_set_color(color)
	var point: Vector3 = _point(cell)
	var d: float = HospitalSpace.CELL_METERS
	var points: Array[Vector3] = [point,point+Vector3(d,0,0),point+Vector3(d,0,d),point+Vector3(0,0,d)]
	for index: int in 4:
		lines.surface_add_vertex(points[index])
		lines.surface_add_vertex(points[(index+1)%4])
