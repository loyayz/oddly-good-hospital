class_name HospitalExperiencePanel
extends HospitalActionPanel

func build_controls() -> void:
	heading("就诊体验")
	var summary: Dictionary = simulation.services.experience.summary(simulation.world)
	note("医院评价：%s · 样本 %s" % [summary.hospital_rating.status,summary.hospital_rating.samples])
	for reason: Dictionary in summary.reasons.slice(0,8):
		note("%s：%s" % [reason.name,reason.reason])
	action("刷新评价与原因",rebuild)
