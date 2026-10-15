class_name ArrivalFraction
extends RefCounted

# Decimal integers keep the frozen arrival plan exact even when a resource
# solution has a denominator wider than the platform's signed integer.
static func integer(value: Variant) -> String:
	var result: String = str(value)
	if value is float:
		result = str(int(value))
	var negative: bool = result.begins_with("-")
	if negative:
		result = result.substr(1)
	while result.length() > 1 and result.begins_with("0"):
		result = result.substr(1)
	return "-" + result if negative and result != "0" else result

static func valid_integer(value: Variant, allow_negative: bool = false) -> bool:
	if not value is String or value.is_empty():
		return false
	var digits: String = value.substr(1) if value.begins_with("-") else value
	if value.begins_with("-") and not allow_negative:
		return false
	if digits.is_empty() or (digits.length() > 1 and digits.begins_with("0")) or value == "-0":
		return false
	for index: int in digits.length():
		if digits.unicode_at(index) < 48 or digits.unicode_at(index) > 57:
			return false
	return true

static func make(numerator: Variant = 0, denominator: Variant = 1) -> Dictionary:
	var n: String = integer(numerator)
	var d: String = integer(denominator)
	assert(d != "0")
	if d.begins_with("-"):
		d = d.substr(1)
		n = negate_integer(n)
	if n == "0":
		return {"n":"0", "d":"1"}
	if d == "1":
		return {"n":n,"d":d}
	var g: String = gcd(absolute(n), d)
	return {"n":divide_integer(n, g), "d":divmod(d, g)[0]}

static func from_value(value: Variant) -> Dictionary:
	if value is Dictionary:
		return make(value.get("n",value.get("numerator","0")),value.get("d",value.get("denominator","1")))
	if value is float and value != floor(value):
		# Original quotes express tick expectations to six decimal places at most.
		return make(roundi(value * 1000000.0),1000000)
	return make(value)

static func valid(value: Variant, nonnegative: bool = true) -> bool:
	return value is Dictionary and valid_integer(value.get("n"),not nonnegative) and valid_integer(value.get("d")) and value.d != "0" and gcd(absolute(value.n),value.d) == "1"

static func add(a: Dictionary, b: Dictionary) -> Dictionary:
	if a.n == "0":
		return b
	if b.n == "0":
		return a
	if a.d == b.d:
		return make(add_integer(a.n,b.n),a.d)
	var common: String = gcd(a.d,b.d)
	var first_scale: String = divmod(b.d,common)[0]
	var second_scale: String = divmod(a.d,common)[0]
	return make(add_integer(multiply_integer(a.n,first_scale),multiply_integer(b.n,second_scale)),multiply_integer(a.d,first_scale))

static func sub(a: Dictionary, b: Dictionary) -> Dictionary:
	return add(a,negate(b))

static func mul(a: Dictionary, b: Dictionary) -> Dictionary:
	if a.n == "0" or b.n == "0":
		return make()
	if a.n == a.d:
		return b
	if b.n == b.d:
		return a
	return make(multiply_integer(a.n,b.n),multiply_integer(a.d,b.d))

static func div(a: Dictionary, b: Dictionary) -> Dictionary:
	assert(b.n != "0")
	if a.n == "0":
		return make()
	if b.n == b.d:
		return a
	return make(multiply_integer(a.n,b.d),multiply_integer(a.d,b.n))

static func negate(a: Dictionary) -> Dictionary:
	return {"n":negate_integer(a.n),"d":a.d}

static func compare(a: Dictionary, b: Dictionary) -> int:
	if a.d == b.d:
		return compare_integer(a.n,b.n)
	return compare_integer(multiply_integer(a.n,b.d),multiply_integer(b.n,a.d))

static func minimum(a: Dictionary, b: Dictionary) -> Dictionary:
	return a if compare(a,b) <= 0 else b

static func maximum(a: Dictionary, b: Dictionary) -> Dictionary:
	return a if compare(a,b) >= 0 else b

static func floor_value(a: Dictionary) -> int:
	var parts: Array = divmod(absolute(a.n),a.d)
	return -int(parts[0])-int(parts[1] != "0") if a.n.begins_with("-") else int(parts[0])

static func ceil_value(a: Dictionary) -> int:
	return -floor_value(negate(a))

static func to_float(a: Dictionary) -> float:
	return float(a.n) / float(a.d)

static func absolute(value: String) -> String:
	return value.substr(1) if value.begins_with("-") else value

static func negate_integer(value: String) -> String:
	return value if value == "0" else value.substr(1) if value.begins_with("-") else "-" + value

static func compare_integer(a: String, b: String) -> int:
	if a.begins_with("-") != b.begins_with("-"):
		return -1 if a.begins_with("-") else 1
	var result: int = _compare_unsigned(absolute(a),absolute(b))
	return -result if a.begins_with("-") else result

static func add_integer(a: String, b: String) -> String:
	var aa: String = absolute(a)
	var bb: String = absolute(b)
	var an: bool = a.begins_with("-")
	if an == b.begins_with("-"):
		var result: String = _add_unsigned(aa,bb)
		return "-"+result if an and result != "0" else result
	var comparison: int = _compare_unsigned(aa,bb)
	if comparison == 0:
		return "0"
	var result: String = _subtract_unsigned(aa,bb) if comparison > 0 else _subtract_unsigned(bb,aa)
	var negative: bool = an if comparison > 0 else not an
	return "-"+result if negative else result

static func multiply_integer(a: String, b: String) -> String:
	var aa: String = absolute(a)
	var bb: String = absolute(b)
	if aa == "0" or bb == "0":
		return "0"
	var result: String = "0"
	for index: int in bb.length():
		result = _add_unsigned(result+"0",_multiply_digit(aa,bb.unicode_at(index)-48))
	return "-"+result if a.begins_with("-") != b.begins_with("-") else result

static func divide_integer(a: String, b: String) -> String:
	var quotient: String = divmod(absolute(a),absolute(b))[0]
	return "-"+quotient if quotient != "0" and a.begins_with("-") != b.begins_with("-") else quotient

static func divmod(a: String, b: String) -> Array:
	assert(b != "0" and not a.begins_with("-") and not b.begins_with("-"))
	if _compare_unsigned(a,b) < 0:
		return ["0",a]
	var quotient: String = ""
	var remainder: String = "0"
	for index: int in a.length():
		remainder = integer(remainder+a.substr(index,1))
		var digit: int = 0
		while _compare_unsigned(remainder,b) >= 0:
			remainder = _subtract_unsigned(remainder,b)
			digit += 1
		quotient += str(digit)
	return [integer(quotient),remainder]

static func gcd(a: String, b: String) -> String:
	if a == "1" or b == "1":
		return "1"
	while b != "0":
		var next: String = divmod(a,b)[1]
		a = b
		b = next
	return a

static func _compare_unsigned(a: String, b: String) -> int:
	if a.length() != b.length():
		return -1 if a.length() < b.length() else 1
	return 0 if a == b else -1 if a < b else 1

static func _add_unsigned(a: String, b: String) -> String:
	var result: String = ""
	var carry: int = 0
	var ia: int = a.length()-1
	var ib: int = b.length()-1
	while ia >= 0 or ib >= 0 or carry > 0:
		var digit: int = carry
		if ia >= 0:
			digit += a.unicode_at(ia)-48
		if ib >= 0:
			digit += b.unicode_at(ib)-48
		result = str(digit % 10)+result
		carry = digit/10
		ia -= 1
		ib -= 1
	return integer(result)

static func _subtract_unsigned(a: String, b: String) -> String:
	var result: String = ""
	var borrow: int = 0
	var ib: int = b.length()-1
	for ia: int in range(a.length()-1,-1,-1):
		var digit: int = a.unicode_at(ia)-48-borrow
		if ib >= 0:
			digit -= b.unicode_at(ib)-48
		borrow = int(digit < 0)
		if borrow > 0:
			digit += 10
		result = str(digit)+result
		ib -= 1
	return integer(result)

static func _multiply_digit(a: String, digit: int) -> String:
	if digit == 0:
		return "0"
	var result: String = ""
	var carry: int = 0
	for index: int in range(a.length()-1,-1,-1):
		var value: int = (a.unicode_at(index)-48)*digit+carry
		result = str(value % 10)+result
		carry = value/10
	return str(carry)+result if carry > 0 else integer(result)
