extends "res://game/app/app_root.gd"

# Display-only renderer evidence uses the original controls and legal preset.
# No GameSession is created; this cannot stand in for a business-load capture.
func _ready() -> void:
	_build_ui()
	_content = HospitalContent.new()
	_view_work_budget = ViewWorkBudget.new(int(float(_content.balance.spatial_view.view_build_budget_ms_per_frame)*1000.0))
	var world: WorldState = HospitalFactory.create(HospitalSnapshots.uuid(),"显示边界",true,_content)
	_view = HospitalView.new(_content)
	_view.work_budget = _view_work_budget
	_viewport.add_child(_view)
	_view.bind(world,1,"display-boundary")

func _process(_delta: float) -> void:
	_sync_scene_pixels()
	if _view!=null: _view.update_facts()

func _notification(_what: int) -> void:
	pass
