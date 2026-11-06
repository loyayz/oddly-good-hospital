extends SceneTree

func _initialize() -> void:
	var space: HospitalSpace = HospitalSpace.new()
	var rows: Array = []
	var ok: bool = true
	for rotation: int in 4:
		for specimen: Dictionary in [{"size":1,"count":1,"connector":"VC02"},{"size":1,"count":2,"connector":"VC02"},{"size":2,"count":2,"connector":"VC03"}]:
			var world: WorldState = WorldState.new()
			var size: int = specimen.size
			var members: Array = ["leader"] if specimen.count==1 else ["leader","follower"]
			var centers: Dictionary = {"leader":[0,0]}
			if specimen.count==2: centers.follower=[0,0]
			var convoy: Dictionary = {"size":size,"spacing":2.0*size,"shift":0.0,"height":1.75,"centers":centers,"points":[[40,80]],"floor_id":1}
			world.facts.actors.leader = {"clearance":size}
			var definition: Dictionary = space.content.definition("vertical_connectors",specimen.connector)
			var connection: Dictionary = {"definition_id":specimen.connector,"rotation":rotation,"cell":[40,72],"footprint":definition.footprint,"phase":"boarding"}
			var before: Dictionary = convoy.duplicate(true)
			var plan: Dictionary = ConvoyPortal.plan(space,world,connection,"leader",members,convoy)
			var safe: bool = plan.ok and convoy==before
			var ticks: Array = []
			var compound_steps: int = 0
			if plan.ok:
				var head: Vector2 = ConvoyTrail.point(plan.entry)
				var tail: Vector2 = head-ConvoyTrail.point(plan.inward)*float(convoy.spacing)*(members.size()-1)
				convoy.points = [[tail.x,tail.y],[head.x,head.y]] if members.size()>1 else [[head.x,head.y]]
				for targets: Array in [plan.boarding,plan.alighting]:
					var cursor: int = 0
					var steps: int = 0
					while cursor<targets.size() and steps<400:
						var old: Dictionary = convoy.duplicate(true)
						var proposal: Dictionary = ConvoyPortal.propose_step(convoy,targets,cursor,space.walking_speed(world.facts.actors.leader)*WorldState.TICK_SECONDS)
						safe = safe and convoy==old
						if not proposal.ok: safe=false; break
						convoy.points = proposal.points
						cursor = int(proposal.cursor)
						steps += 1
						compound_steps += 1 if int(proposal.segment_count)>1 else 0
						safe = safe and ConvoyTrail._trail_separation_error(convoy).is_empty() and float(proposal.distance)<=space.walking_speed(world.facts.actors.leader)*WorldState.TICK_SECONDS+0.0001
						var poses: Dictionary = ConvoyTrail.positions(convoy,members)
						if members.size()>1:
							safe = safe and not Rect2(ConvoyTrail.point(poses.leader.cell),Vector2.ONE*size).intersects(Rect2(ConvoyTrail.point(poses.follower.cell),Vector2.ONE*size),false)
					ticks.append(maxi(steps,HospitalTransit._boarding(definition) if ticks.is_empty() else HospitalTransit._alighting(definition)))
					safe = safe and cursor==targets.size()
				var predicted: Dictionary = ConvoyPortal.predict(convoy,plan,2)
				safe = safe and ConvoyTrail.point(convoy.points[-1]).distance_to(ConvoyTrail.point(predicted.points[-1]))<0.001 and ConvoyTrail.point(convoy.points[0]).distance_to(ConvoyTrail.point(predicted.points[0]))<0.001
			var tick_match: bool = plan.ok and ticks==[plan.boarding_ticks,plan.alighting_ticks]
			var passed: bool = safe and tick_match
			ok = ok and passed
			rows.append({"ok":passed,"rotation":rotation,"size":size,"count":members.size(),"plan_ok":plan.ok,"reason":plan.reason,"safe":safe,"ticks":ticks,"tick_match":tick_match,"compound_steps":compound_steps})
	for rejected: Dictionary in [{"name":"narrow_cabin","size":2,"count":2,"connector":"VC02","spacing":4.0},{"name":"stairs_pair","size":1,"count":2,"connector":"VC01","spacing":2.0},{"name":"capacity","size":1,"count":3,"connector":"VC03","spacing":2.0},{"name":"tail_outside_cabin","size":1,"count":2,"connector":"VC02","spacing":10.0}]:
		var world: WorldState=WorldState.new()
		world.facts.actors.leader={"clearance":int(rejected.size)}
		var members: Array=["leader"]
		var centers: Dictionary={"leader":[0,0]}
		for index: int in range(1,int(rejected.count)):
			var id: String="member_%d"%index
			members.append(id)
			centers[id]=[0,0]
		var convoy: Dictionary={"size":rejected.size,"spacing":rejected.spacing,"shift":0.0,"height":1.75,"centers":centers,"points":[[40,80]],"floor_id":1}
		var definition: Dictionary=space.content.definition("vertical_connectors",rejected.connector)
		var connection: Dictionary={"definition_id":rejected.connector,"rotation":0,"cell":[40,72],"footprint":definition.footprint,"phase":"boarding"}
		var before: Dictionary=convoy.duplicate(true)
		var plan: Dictionary=ConvoyPortal.plan(space,world,connection,"leader",members,convoy)
		var passed: bool=not plan.ok and not str(plan.reason).is_empty() and convoy==before
		ok=ok and passed
		rows.append({"ok":passed,"case":rejected.name,"rejected":not plan.ok,"source_unchanged":convoy==before,"reason":plan.reason})
	print(JSON.stringify({"ok":ok,"rows":rows}))
	quit(0 if ok else 1)
