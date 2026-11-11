extends RefCounted

# Completed history for cases whose operation starts after diagnosis. The
# original room may have been removed; its identity still belongs to the Visit.
# This input does not stand in for any arrival, examination or work under test.
static func diagnosed(doctor_id: String, facility_id: String, insufficient_bp: int = 4000) -> Dictionary:
	return {"state":"diagnosed","gp_completed":true,"exam_kind":"","exam_completed":false,"review_completed":false,
		"doctor_id":doctor_id,"facility_id":facility_id,"insufficient":false,"insufficient_bp":insufficient_bp}

static func insufficient(doctor_id: String, facility_id: String, insufficient_bp: int = 4000) -> Dictionary:
	var value: Dictionary=diagnosed(doctor_id,facility_id,insufficient_bp)
	value.state="insufficient"
	value.insufficient=true
	return value
