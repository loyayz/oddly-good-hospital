extends SceneTree
var rows:Array=[]
func _initialize()->void:call_deferred("_run")
func check(id:String,passed:bool,details:Variant=null)->void:
 rows.append({"id":id,"passed":passed,"details":details});print("DUE_NEED_CASE ",id," ",passed)
func _run()->void:
 var content:HospitalContent=HospitalContent.new()
 for mutate:bool in [false,true]:
  var result:Dictionary=load("res://tests/acceptance/waiting_need_scan.gd").new().run(content,mutate)
  check("NEED-SCAN-"+str(mutate),result.ok,result)
 var staff:RefCounted=load("res://tests/acceptance/staff.gd").new();staff._content=content;staff.call("_case_35",self)
 var areas:RefCounted=load("res://tests/acceptance/public_area_use.gd").new()
 for id:String in ["47","61"]:areas.run(self,content,"STAFF-"+id)
 var native_result:Dictionary=load("res://tests/acceptance/native_waiting_dispatch.gd").new().run(content,true)
 check("EXPLICIT-NATIVE-FIELD-CONTRACT",native_result.ok,native_result)
 var result:Dictionary={"passed":rows.size()==6 and rows.all(func(row:Dictionary)->bool:return row.passed),"cases":rows}
 FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t"));quit(0 if result.passed else 1)
