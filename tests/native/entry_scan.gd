extends SceneTree
const Base=preload("res://baseline.gd")
const Current=preload("res://current.gd")
const World=preload("res://world.gd")
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
	s.safe=mode!="unsafe";s.inside=mode=="inside";s.exists=mode!="absent";s.safe_calls=0
	s.space.navigation.calls=0;s.space.query_counts.clear()
	s.space.navigation.leg={"travel_ticks":3} if mode=="success" else {}
	var distances=PackedInt32Array();distances.resize(9216);distances.fill(-1)
	if mode=="field":distances[0]=2
	s.space.navigation.field={"distances":distances,"speed":1.0,"prefix_ticks":0} if mode=="field" else {}
func _initialize():
	var a=Base.new();var b=Current.new();var w=World.new();var rows=[]
	for compact in [true,false]:
		for n in [0,1,8,96,512]:
			for mode in ["absent","inside","unsafe","failure","success","field"]:
				for offset in [0,7]:
					for limit in [0,3,100000]:
						setup(a,n,compact,mode,offset);setup(b,n,compact,mode,offset)
						var x=run(a,w,limit);var y=run(b,w,limit)
						check(x==y);check(a.safe_calls==b.safe_calls);check(a.space.navigation.calls==b.space.navigation.calls);check(a.space.query_counts==b.space.query_counts)
						if mode=="unsafe" or mode=="failure" or mode=="absent" or n==0 and mode!="inside":check(y.is_empty())
						if mode=="inside":check(y=={"floor_id":1,"cell":[0,0],"travel_ticks":0})
						if mode=="success" and n>0 and limit>=maxi(offset,3):check(y=={"floor_id":1,"cell":[0,0],"travel_ticks":3})
	for compact in [true,false]:
		for n in [0,1,8,96,512]:
			for mode in ["unsafe","failure","success","field"]:
				setup(a,n,compact,mode,0);setup(b,n,compact,mode,0)
				var iterations=20000 if n<=8 or mode=="success" else 1000
				for old in [true,false,false,true,true,false,false,true]:
					var s=a if old else b;var sum=0;var start=Time.get_ticks_usec()
					for i in iterations:sum+=int(run(s,w).get("travel_ticks",-1))
					rows.append({"compact":compact,"n":n,"mode":mode,"old":old,"us":Time.get_ticks_usec()-start,"iterations":iterations,"sum":sum})
	print(JSON.stringify({"checks":checks,"windows":rows}))
	quit()
