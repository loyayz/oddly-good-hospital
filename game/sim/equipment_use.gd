class_name HospitalEquipmentUse
extends RefCounted

# Read-only handoff between equipment users and maintenance. The users retain
# their reservations; this projection is neither a new lock nor saved state.
static func query(world: WorldState, equipment_id: String, clinical_uses: Variant = null) -> Dictionary:
	var use: Dictionary = HospitalClinic.equipment_use(world,equipment_id) if clinical_uses==null else clinical_uses.get(equipment_id,{"occupied":false,"critical_commitment":false})
	var occupied: bool = bool(use.occupied) or world.facts.adaptations.has(equipment_id)
	var connector: Dictionary = world.facts.connectors.get(equipment_id,{})
	if not connector.is_empty():
		occupied = occupied or connector.phase!="idle" or not connector.riders.is_empty()
	if world.facts.facilities.get(equipment_id,{}).get("definition_id","")=="FUR05":
		occupied = occupied or HospitalClinicalDevelopment.desk_taken(world,equipment_id)
	return {"placed":not world.facts.inventory.get("build_items",{}).has(equipment_id) and (world.facts.facilities.has(equipment_id) or not connector.is_empty()),
		"occupied":occupied,"critical_commitment":bool(use.critical_commitment)}
