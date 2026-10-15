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
	var cells: Array = draft.get("cells",[]).duplicate()
	if cells.is_empty():
		var origin: Array = draft.get("origin",draft.get("cell",[0,0]))
		var size: Array = draft.get("size",[1,1])
		for x: int in range(int(origin[0]),int(origin[0])+int(size[0])):
			for y: int in range(int(origin[1]),int(origin[1])+int(size[1])):
				cells.append([x,y])
	if cells.is_empty():
		return
	var lines: ImmediateMesh = ImmediateMesh.new()
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.no_depth_test = true
	lines.surface_begin(Mesh.PRIMITIVE_LINES,material)
	var color: Color = Color("4d719d") if result.get("ready",false) and result.get("ok",false) else Color("7a7d83")
	if result.get("ready",false) and not result.get("ok",false):
		color = Color("b85550")
	for cell: Array in cells:
		lines.surface_set_color(Color("b85550") if cell in result.get("blocked_cells",[]) else color)
		var x: float = (float(cell[0])-32.0)*HospitalSpace.CELL_METERS
		var z: float = (float(cell[1])-64.0)*HospitalSpace.CELL_METERS
		var d: float = HospitalSpace.CELL_METERS
		var points: Array[Vector3] = [Vector3(x,0.06,z),Vector3(x+d,0.06,z),Vector3(x+d,0.06,z+d),Vector3(x,0.06,z+d)]
		for i: int in 4:
			lines.surface_add_vertex(points[i])
			lines.surface_add_vertex(points[(i+1)%4])
	lines.surface_end()
	mesh = lines
