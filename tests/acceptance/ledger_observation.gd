extends RefCounted

func run(t, content: HospitalContent) -> void:
	var world: WorldState = HospitalFactory.create(HospitalSnapshots.uuid(),"余额观察",false,content)
	var before: Dictionary = world.freeze()
	var observations: Dictionary = {}
	var correct: bool = HospitalLedger.balance(world)==24800 and world.available_ledger_balance()==24800 and world.freeze()==before
	observations.initial = correct
	var debit: LedgerEntry = LedgerEntry.new(world.hospital_id,"pending_debit",-40)
	var credit: LedgerEntry = LedgerEntry.new(world.hospital_id,"pending_credit",70)
	correct = correct and HospitalLedger.post(world,debit,false).accepted and HospitalLedger.post(world,credit,false).accepted
	correct = correct and HospitalLedger.balance(world)==24800 and world.available_ledger_balance()==24760
	observations.pending = [correct,HospitalLedger.balance(world),world.available_ledger_balance()]
	before = world.freeze()
	var denied: CommandResult = HospitalLedger.post(world,LedgerEntry.new(world.hospital_id,"excess",-24761))
	correct = correct and not denied.accepted and world.freeze()==before
	observations.denied = [correct,denied.accepted,world.freeze()==before]
	var restored: WorldState = WorldState.new(before.duplicate(true))
	var events: Array[SimEvent] = HospitalLedger.settle(world)
	correct = correct and events.size()==2 and HospitalLedger.balance(world)==24830 and world.available_ledger_balance()==24830
	observations.settled = [correct,events.size(),HospitalLedger.balance(world),world.available_ledger_balance()]
	correct = correct and HospitalLedger.balance(restored)==24800 and restored.available_ledger_balance()==24760
	observations.restored = [correct,HospitalLedger.balance(restored),restored.available_ledger_balance()]
	correct = correct and HospitalLedger.post(world,LedgerEntry.new(world.hospital_id,"paid",-5)).accepted and HospitalLedger.balance(world)==24825
	observations.paid = [correct,HospitalLedger.balance(world)]
	var replacement: Dictionary = restored.freeze()
	world.facts = replacement
	correct = correct and HospitalLedger.balance(world)==24800 and world.available_ledger_balance()==24760
	observations.replacement = [correct,HospitalLedger.balance(world),world.available_ledger_balance()]
	HospitalLedger.settle(world)
	correct = correct and HospitalLedger.balance(world)==24830 and HospitalLedger.settle(world).is_empty()
	observations.resettled = [correct,HospitalLedger.balance(world)]
	# The runtime observation is not saved, and a different entries container
	# must rebuild even when its membership count is unchanged.
	world.facts.ledger.entries = restored.facts.ledger.entries.duplicate(true)
	correct = correct and HospitalLedger.balance(world)==24800 and world.available_ledger_balance()==24760
	observations.container = [correct,HospitalLedger.balance(world),world.available_ledger_balance()]
	var opening_delta: int = 25000-int(world.facts.ledger.opening_balance)
	world.facts.ledger.opening_balance = 25000
	correct = correct and HospitalLedger.balance(world)==24800+opening_delta and world.available_ledger_balance()==24760+opening_delta
	observations.opening = [correct,HospitalLedger.balance(world),world.available_ledger_balance()]
	var reason: String = world.validate(content)+restored.validate(content)
	t.check("CORE-45",correct and reason.is_empty(),{"observations":observations,"validation":reason})
