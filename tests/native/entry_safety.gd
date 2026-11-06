extends SceneTree
const Base=preload("res://baseline.gd")
const Current=preload("res://current.gd")
const World=preload("res://world.gd")
const Clearance=preload("res://clearance.gd")
var checks:int=0
func check(ok):
	checks+=1
	if not ok:push_error("failed "+str(checks));quit(1)
func run(s,w,limit=9223372036854775807):return s._waiting_point(w,"a",{"floor_id":1},limit)
func setup(s,n,compact,mode,offset):
	var packed=PackedInt64Array();var fallback=[]
	for i in n:
		packed.append(i*9216+i)
		fallback.append({"cell":Vector2i(i%96,i/96),"lower":i+offset})
	s.ordered={"packed":packed if compact else PackedInt64Array(),"fallback":[] if compact else fallback,"compact":compact,"offset_ticks":offset}
	if not compact and offset==0:s.ordered.erase("offset_ticks")
	s.safe=mode!="unsafe";s.inside=mode=="inside";s.exists=mode!="absent"
	s.space.reserved=mode=="reserved";s.space.dynamic=mode!="dynamic"
	s.geometry={"points":{},"geometry":Clearance.new()}
	s.space.navigation.calls=0;s.space.query_counts.clear();s.space.views.clear();s.space.constructs=0
	s.trace.clear();s.space.trace.clear()
	s.space.navigation.leg={"travel_ticks":3} if mode=="success" else {}
	s.space.quote={"ok":true,"travel_ticks":3} if mode=="quote" else {"ok":false}
	var distances=PackedInt32Array();distances.resize(9216);distances.fill(-1)
	if mode=="field":distances[0]=2
	s.space.navigation.field={"distances":distances,"speed":1.0,"prefix_ticks":0} if mode=="field" else {}
func _initialize():
	if "--targeted" in OS.get_cmdline_user_args():
		_targeted()
		return
	var control="--control" in OS.get_cmdline_user_args()
	var a=Current.new() if control else Base.new();var b=Current.new();var w=World.new();var rows=[]
	a.logging=true;b.logging=true;a.space.logging=true;b.space.logging=true
	for compact in [true,false]:
		for n in [0,1,8,96,512]:
			for mode in ["absent","inside","unsafe","reserved","dynamic","failure","success","field","quote"]:
				for offset in [0,7]:
					for limit in [0,3,100000]:
						setup(a,n,compact,mode,offset);setup(b,n,compact,mode,offset)
						var x=run(a,w,limit);var y=run(b,w,limit)
						check(x==y);check(a.trace==b.trace);check(a.space.trace==b.space.trace);check(a.space.constructs==b.space.constructs)
						check(a.space.navigation.calls==b.space.navigation.calls);check(a.space.query_counts==b.space.query_counts)
						if mode in ["unsafe","reserved","dynamic","failure","absent"] or n==0 and mode!="inside":check(y.is_empty())
						if mode=="inside":check(y=={"floor_id":1,"cell":[0,0],"travel_ticks":0})
						if mode in ["success","quote"] and n>0 and limit>=maxi(offset,3):check(y=={"floor_id":1,"cell":[0,0],"travel_ticks":3})
	# Independent fractional public API: round for reservation, original float origin for dynamic body.
	for cell in [[0,0],[1.25,-0.25],[0.5,-0.5],[-1.5,2.5],[95,95]]:
		for mode in ["unsafe","reserved","dynamic","success"]:
			setup(a,1,true,mode,0);setup(b,1,true,mode,0)
			var x=a.safe_wait(w,"a",1,cell);var y=b.safe_wait(w,"a",1,cell)
			check(x==y);check(y==(mode=="success"));check(a.trace==b.trace);check(a.space.trace==b.space.trace)
			if mode!="unsafe":check(b.space.trace[0]==["reservation",Vector2i(roundi(cell[0]),roundi(cell[1]))])
			if mode in ["dynamic","success"]:check(b.space.trace[1]==["dynamic",Rect2(Vector2(float(cell[0]),float(cell[1])),Vector2.ONE)])
	if "--check-only" in OS.get_cmdline_user_args():
		a.space.views.clear();b.space.views.clear()
		print(JSON.stringify({"checks":checks,"windows":[],"control":control}))
		quit()
		return
	a.logging=false;b.logging=false;a.space.logging=false;b.space.logging=false
	for compact in [true,false]:
		for n in [0,1,96,512]:
			for mode in ["unsafe","reserved","dynamic","failure","success","field","quote"]:
				setup(a,n,compact,mode,0);setup(b,n,compact,mode,0)
				var iterations=8000 if n<=8 or mode in ["success","quote"] else 150
				for old in [true,false,false,true,true,false,false,true]:
					var s=a if old else b;var sum=0;var start=Time.get_ticks_usec()
					for i in iterations:sum+=int(run(s,w).get("travel_ticks",-1))
					rows.append({"kind":"scan","compact":compact,"n":n,"mode":mode,"old":old,"us":Time.get_ticks_usec()-start,"iterations":iterations,"sum":sum})
	a.space.views.clear();b.space.views.clear()
	print(JSON.stringify({"checks":checks,"windows":rows,"control":control}))
	quit()

func _targeted():
	var a=Base.new();var b=Current.new();var c=Current.new();var w=World.new();var rows=[]
	for spec in [[1,"dynamic",false,50000],[512,"field",false,5000],[96,"unsafe",true,2000],[1,"success",true,20000],[512,"failure",true,200],[0,"unsafe",false,50000]]:
		for control in [false,true]:
			var left=c if control else a
			setup(left,spec[0],true,spec[1],0);setup(b,spec[0],true,spec[1],0)
			for old in [true,false,false,true,true,false,false,true]:
				var s=left if old else b;var sum=0;var start=Time.get_ticks_usec()
				for i in spec[3]:
					if spec[2]:s.geometry.points.clear();s.space.views.clear()
					sum+=int(run(s,w).get("travel_ticks",-1))
				rows.append({"kind":"targeted","n":spec[0],"mode":spec[1],"cold":spec[2],"control":control,"old":old,"us":Time.get_ticks_usec()-start,"iterations":spec[3],"sum":sum})
	a.space.views.clear();b.space.views.clear();c.space.views.clear()
	print(JSON.stringify({"checks":0,"windows":rows}))
	quit()
