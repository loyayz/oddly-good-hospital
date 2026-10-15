class_name ArrivalCapacitySolver
extends RefCounted

const F = preload("res://game/arrivals/exact_fraction.gd")

# Exact primal simplex. The empty assignment is feasible: every case equation
# has RHS zero and every real resource has a nonnegative remaining budget.
# Bland's variable order makes even degenerate shared-resource cases stable.
static func solve(cases: Array, budgets: Dictionary) -> Dictionary:
	var columns: Array = []
	for case_index: int in cases.size():
		for bundle: Dictionary in cases[case_index].bundles:
			columns.append({"case_index":case_index,"bundle":bundle})
	if columns.is_empty() or cases.is_empty():
		return {"capacity":F.make(),"assignments":[],"bottleneck":"缺少完整可接诊资源束"}
	var resource_ids: Array = budgets.keys()
	resource_ids.sort()
	var rows: Array = []
	var owners: Array[String] = []
	var variables: int = columns.size()+1
	for case_index: int in cases.size():
		var equation: Dictionary = {0:F.negate(cases[case_index].probability)}
		for column: int in columns.size():
			if int(columns[column].case_index) == case_index:
				equation[column+1] = F.make(1)
		rows.append({"a":equation,"b":F.make()})
		owners.append("")
		var reverse: Dictionary = {}
		for column: int in equation:
			reverse[column] = F.negate(equation[column])
		rows.append({"a":reverse,"b":F.make()})
		owners.append("")
	for resource_id: String in resource_ids:
		var coefficients: Dictionary = {}
		for column: int in columns.size():
			var demand: Dictionary = columns[column].bundle.get("resources",{})
			if demand.has(resource_id) and F.compare(F.from_value(demand[resource_id]),F.make()) > 0:
				coefficients[column+1] = F.from_value(demand[resource_id])
		rows.append({"a":coefficients,"b":F.from_value(budgets[resource_id])})
		owners.append(resource_id)
	var basis: Array[int] = []
	for index: int in rows.size():
		rows[index].a[variables+index] = F.make(1)
		basis.append(variables+index)
	var objective: Dictionary = {"a":{0:F.make(-1)},"b":F.make()}
	while true:
		var entering: int = -1
		var objective_columns: Array = objective.a.keys()
		objective_columns.sort()
		for column: int in objective_columns:
			if F.compare(objective.a[column],F.make()) < 0:
				entering = column
				break
		if entering < 0:
			break
		var leaving: int = -1
		var ratio: Dictionary = {}
		for index: int in rows.size():
			var coefficient: Dictionary = rows[index].a.get(entering,F.make())
			if F.compare(coefficient,F.make()) <= 0:
				continue
			var next: Dictionary = F.div(rows[index].b,coefficient)
			if leaving < 0 or F.compare(next,ratio) < 0 or (F.compare(next,ratio) == 0 and basis[index] < basis[leaving]):
				leaving = index
				ratio = next
		if leaving < 0:
			return {"capacity":F.make(),"assignments":[],"bottleneck":"资源束缺少真实时间约束","error":"unbounded_resource_model"}
		var pivot: Dictionary = rows[leaving]
		var divisor: Dictionary = pivot.a[entering]
		for column: int in pivot.a:
			pivot.a[column] = F.div(pivot.a[column],divisor)
		pivot.b = F.div(pivot.b,divisor)
		for index: int in rows.size():
			if index != leaving:
				_eliminate(rows[index],pivot,entering)
		_eliminate(objective,pivot,entering)
		basis[leaving] = entering
	var assignments: Array = []
	var bottleneck: String = ""
	var values: Dictionary = {}
	for index: int in rows.size():
		values[basis[index]] = rows[index].b
		if basis[index] > 0 and basis[index] < variables and rows[index].b.n != "0":
			assignments.append({"case_index":columns[basis[index]-1].case_index,"bundle_index":basis[index]-1,"amount":rows[index].b})
	for index: int in rows.size():
		var slack: Dictionary = values.get(variables+index,F.make())
		if slack.n == "0" and not owners[index].is_empty() and bottleneck.is_empty():
			bottleneck = owners[index]
	return {"capacity":objective.b,"assignments":assignments,"bottleneck":bottleneck,"resource_count":budgets.size(),"bundle_count":columns.size()}

static func _eliminate(row: Dictionary, pivot: Dictionary, entering: int) -> void:
	var factor: Dictionary = row.a.get(entering,F.make())
	if factor.n == "0":
		return
	for column: int in pivot.a:
		var updated: Dictionary = F.sub(row.a.get(column,F.make()),F.mul(factor,pivot.a[column]))
		if updated.n == "0":
			row.a.erase(column)
		else:
			row.a[column] = updated
	row.b = F.sub(row.b,F.mul(factor,pivot.b))
