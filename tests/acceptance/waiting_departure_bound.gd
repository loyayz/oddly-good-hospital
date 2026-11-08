extends "res://tests/acceptance/public_waiting_cost_field.gd"
class Probe extends HospitalPublicAreas:
	var landing_calls: int=0
	func _entry_landings(world: WorldState, actor_id: String, floor_id: int) -> Dictionary:
		landing_calls+=1
		return super._entry_landings(world,actor_id,floor_id)
func run_focused(content: HospitalContent) -> Dictionary:
	_content=content
	var cases: Array=[]
	for fractional: bool in [false,true]:
		for multiple: bool in [false,true]:
			var x: Dictionary=_field_fixture(true,fractional,false,multiple)
			var probe:=Probe.new(x.actual);x.actual.public_areas=probe
			var actor: Dictionary=x.world.facts.actors[ACTOR]
			var lower: int=probe._first_connector_lower_ticks(x.world,actor)
			var before: Dictionary=x.world.freeze()
			_field_begin(x)
			var below: Dictionary=_compare_wait(x,lower-1)
			var below_calls: int=probe.landing_calls
			_field_end(x)
			_field_begin(x)
			var equal: Dictionary=_compare_wait(x,lower)
			var equal_calls: int=probe.landing_calls-below_calls
			var full: Dictionary=_compare_wait(x)
			var quote: Dictionary=x.original.travel_quote(x.world,ACTOR,1,x.world.facts.connectors.lift.anchor)
			_field_end(x)
			var proxy: Dictionary=actor.duplicate(true);proxy._convoy_size=2
			var proxy_body: Dictionary=actor.duplicate(true);proxy_body._convoy_body={}
			var checks: Dictionary={"valid_input":x.world.validate(_content).is_empty(),"positive_bound":lower>0,"below_prunes_before_quote":below.ok and below.actual.is_empty() and below_calls==0,"equality_still_quotes":equal.ok and equal_calls==1,"full_result_matches_original":full.ok,"bound_not_above_actual_journey":not quote.ok or lower<=int(quote.travel_ticks),"proxy_falls_back":probe._first_connector_lower_ticks(x.world,proxy)==0 and probe._first_connector_lower_ticks(x.world,proxy_body)==0,"facts_unchanged":before==x.world.freeze(),"scopes_closed":x.actual._route_queries.is_empty() and x.original._route_queries.is_empty()}
			cases.append({"fractional":fractional,"multiple_connectors":multiple,"passed":not checks.values().has(false),"checks":checks,"lower_ticks":lower,"actual_journey":quote.get("travel_ticks",-1)})
			_field_dispose(x)
	return {"passed":cases.all(func(row: Dictionary)->bool:return row.passed),"cases":cases}
