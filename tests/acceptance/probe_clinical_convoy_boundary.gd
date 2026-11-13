extends SceneTree
func _initialize()->void:
 var out:Dictionary={}
 for name:String in ["r4-safe.json.checkpoint.bin","seed2026111302.input.bin"]:
  var f:=FileAccess.open("/tmp/ogh-mixed-visit-b87545e/"+name,FileAccess.READ);var e:Dictionary=f.get_var(false);f.close();var facts:Dictionary=e.get("facts",e);var convoys:Dictionary={}
  for id:String in facts.moves:
   if facts.moves[id].has("convoy"):convoys[id]=facts.moves[id]
  out[name]={"tick":facts.sim_tick,"convoys":convoys,"visitors":facts.get("visitors",{}),"ward_stays":facts.ward_stays}
 var f:=FileAccess.open("/workspace/scratch/6962cc21ddf3/clinical-convoy-boundaries.json",FileAccess.WRITE);f.store_string(JSON.stringify(out,"\t"));f.close();quit()
