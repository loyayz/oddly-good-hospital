extends RefCounted

func run() -> Dictionary:
	var checks: Dictionary = {}
	var rectangle: Dictionary = BuildGeometry.shape({"origin":[10,12],"size":[2,3]},[2,3])
	checks.rectangle = rectangle.ok and rectangle.cells.size()==6 and rectangle.origin==[10,12] and rectangle.size==[2,3] and rectangle.wall_edges.size()==4
	checks.rotated_minimum = BuildGeometry.shape({"origin":[10,12],"size":[2,3]},[3,2]).ok
	var elbow: Array = [[0,0],[1,0],[0,1]]
	var original: PackedByteArray = var_to_bytes(elbow)
	var irregular: Dictionary = BuildGeometry.shape({"cells":elbow},[1,1])
	checks.irregular_four_neighbour = irregular.ok and irregular.cells==[[0,0],[1,0],[0,1]] and irregular.size==[2,2]
	checks.minimum_inner_rectangle = not BuildGeometry.shape({"cells":elbow},[2,2]).ok
	checks.diagonal_not_connected = not BuildGeometry.shape({"cells":[[0,0],[1,1]]},[1,1]).ok
	checks.separated_not_connected = not BuildGeometry.shape({"cells":[[0,0],[1,0],[3,0]]},[1,1]).ok
	var ring: Array = [[0,0],[1,0],[2,0],[0,1],[2,1],[0,2],[1,2],[2,2]]
	var hole: Dictionary = BuildGeometry.shape({"cells":ring},[1,1])
	checks.enclosed_hole_rejected = not hole.ok and str(hole.reason).contains("孔洞")
	var open_ring: Array = [[0,0],[1,0],[2,0],[0,1],[2,1],[0,2],[2,2]]
	checks.outside_opening_allowed = BuildGeometry.shape({"cells":open_ring},[1,1]).ok
	var full: Dictionary = BuildGeometry.shape({"origin":[0,0],"size":[96,96]},[96,96])
	# The outside component includes the extra ring at coordinates -1 and 96.
	checks.full_96_floor_and_98_envelope = full.ok and full.cells.size()==9216 and full.origin==[0,0] and full.size==[96,96] and full.wall_edges.size()==4
	var corner: Dictionary = BuildGeometry.shape({"cells":[[95,95]]},[1,1])
	checks.extreme_corner = corner.ok and corner.origin==[95,95] and corner.size==[1,1]
	checks.outside_96_floor_rejected = not BuildGeometry.shape({"cells":[[96,95]]},[1,1]).ok
	checks.duplicate_cell_rejected = not BuildGeometry.shape({"cells":[[0,0],[0,0]]},[1,1]).ok
	checks.input_unchanged = var_to_bytes(elbow)==original
	var accepted: bool = true
	for value: bool in checks.values(): accepted = accepted and value
	return {"ok":accepted,"checks":checks}
