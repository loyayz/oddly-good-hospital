class_name HospitalLedger
extends RefCounted

static func balance(world: WorldState) -> int:
	return world.ledger_balance()

static func post(world: WorldState, entry: LedgerEntry, settled: bool = true) -> CommandResult:
	var entries: Dictionary = world.facts.ledger.entries
	if entries.has(entry.entry_id):
		var original: Dictionary = entries[entry.entry_id]
		if int(original.amount)!=entry.amount:
			return CommandResult.new(false,"entry_id_conflict","同一账目凭据的金额已改变",[],world.facts.world_revision)
		return CommandResult.new(true,"duplicate","",[],world.facts.world_revision)
	var available: int = world.available_ledger_balance()
	if available+entry.amount<0:
		return CommandResult.new(false,"insufficient_funds","资金不足，原账目保留",[],world.facts.world_revision)
	entries[entry.entry_id] = {"owner_id":entry.owner_id,"component":entry.component,"amount":entry.amount,"tick":world.facts.sim_tick,"settled":settled}
	world.ledger_posted(entry.entry_id)
	if settled:
		world.touch(false)
	return CommandResult.new(true,"applied","",[entry.entry_id],world.facts.world_revision)

static func settle(world: WorldState) -> Array[SimEvent]:
	var events: Array[SimEvent] = []
	var keys: Array = world.pending_ledger_ids()
	for key: String in keys:
		var entry: Dictionary = world.facts.ledger.entries[key]
		if not entry.settled:
			entry.settled = true
			events.append(SimEvent.new(world.facts.sim_tick,"ledger_settled",[key],{"amount":entry.amount}))
		world.ledger_settled(key)
	return events
