class_name ArrivalFraction
extends RefCounted

# The saved protocol remains canonical decimal strings. GMP owns arithmetic;
# this adapter owns the existing quote conversion and integer rounding rules.
static func integer(value: Variant) -> String:
	var result: String = str(int(value)) if value is float else str(value)
	var negative: bool = result.begins_with("-")
	if negative: result = result.substr(1)
	while result.length()>1 and result.begins_with("0"): result = result.substr(1)
	return "-"+result if negative and result!="0" else result

static func valid_integer(value: Variant, allow_negative: bool = false) -> bool:
	if not value is String or value.is_empty(): return false
	var digits: String = value.substr(1) if value.begins_with("-") else value
	if value.begins_with("-") and not allow_negative: return false
	if digits.is_empty() or (digits.length()>1 and digits.begins_with("0")) or value=="-0": return false
	for index: int in digits.length():
		if digits.unicode_at(index)<48 or digits.unicode_at(index)>57: return false
	return true

static func make(numerator: Variant = 0, denominator: Variant = 1) -> Dictionary:
	var n: String = integer(numerator)
	var d: String = integer(denominator)
	assert(d!="0")
	if d.begins_with("-"):
		d = d.substr(1)
		n = negate_integer(n)
	if n=="0": return {"n":"0","d":"1"}
	if d=="1": return {"n":n,"d":d}
	return PlatformArrivalMath.fraction(0,{"n":n,"d":d},{"n":"0","d":"1"})

static func from_value(value: Variant) -> Dictionary:
	if value is Dictionary: return make(value.get("n",value.get("numerator","0")),value.get("d",value.get("denominator","1")))
	if value is float and value!=floor(value): return make(roundi(value*1000000.0),1000000)
	return make(value)

static func valid(value: Variant, nonnegative: bool = true) -> bool:
	return value is Dictionary and valid_integer(value.get("n"),not nonnegative) and valid_integer(value.get("d")) and value.d!="0" and gcd(absolute(value.n),value.d)=="1"

static func add(a: Dictionary, b: Dictionary) -> Dictionary:
	if a.n=="0": return b
	if b.n=="0": return a
	return PlatformArrivalMath.fraction(1,a,b)

static func sub(a: Dictionary, b: Dictionary) -> Dictionary:
	return PlatformArrivalMath.fraction(2,a,b)

static func mul(a: Dictionary, b: Dictionary) -> Dictionary:
	if a.n=="0" or b.n=="0": return make()
	if a.n==a.d: return b
	if b.n==b.d: return a
	return PlatformArrivalMath.fraction(3,a,b)

static func div(a: Dictionary, b: Dictionary) -> Dictionary:
	assert(b.n!="0")
	return PlatformArrivalMath.fraction(4,a,b)

static func negate(a: Dictionary) -> Dictionary:
	return {"n":negate_integer(a.n),"d":a.d}

static func compare(a: Dictionary, b: Dictionary) -> int:
	return str(PlatformArrivalMath.fraction(5,a,b).n).to_int()

static func minimum(a: Dictionary, b: Dictionary) -> Dictionary:
	return a if compare(a,b)<=0 else b

static func maximum(a: Dictionary, b: Dictionary) -> Dictionary:
	return a if compare(a,b)>=0 else b

static func floor_value(a: Dictionary) -> int:
	var parts: Array = divmod(absolute(a.n),a.d)
	return -int(parts[0])-int(parts[1]!="0") if a.n.begins_with("-") else int(parts[0])

static func ceil_value(a: Dictionary) -> int:
	return -floor_value(negate(a))

static func to_float(a: Dictionary) -> float:
	return float(a.n)/float(a.d)

static func absolute(value: String) -> String:
	return value.substr(1) if value.begins_with("-") else value

static func negate_integer(value: String) -> String:
	return value if value=="0" else value.substr(1) if value.begins_with("-") else "-"+value

static func compare_integer(a: String, b: String) -> int:
	return str(PlatformArrivalMath.integer(5,a,b).value).to_int()

static func add_integer(a: String, b: String) -> String:
	return PlatformArrivalMath.integer(0,a,b).value

static func multiply_integer(a: String, b: String) -> String:
	return PlatformArrivalMath.integer(1,a,b).value

static func divide_integer(a: String, b: String) -> String:
	return PlatformArrivalMath.integer(2,a,b).value

static func divmod(a: String, b: String) -> Array:
	assert(b!="0" and not a.begins_with("-") and not b.begins_with("-"))
	var result: Dictionary = PlatformArrivalMath.integer(3,a,b)
	return [result.value,result.remainder]

static func gcd(a: String, b: String) -> String:
	return PlatformArrivalMath.integer(4,a,b).value
