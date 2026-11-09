extends SceneTree

const Bank = preload("res://tools/assets/sound_bank.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var effects: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/effects/index.json"))
	for effect: Dictionary in effects.effects:
		var packed: PackedScene = load("res://" + str(effect.path)) as PackedScene
		if packed == null:
			failures.append("Cannot load effect " + str(effect.id))
			continue
		var node: Node = packed.instantiate()
		var particles: CPUParticles3D = node.get_node("Particles") as CPUParticles3D
		if particles.amount > 32 or particles.emitting:
			failures.append("Effect budget/default state invalid " + str(effect.id))
		node.free()
	var bank: Node = Bank.new()
	root.add_child(bank)
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), true)
	if bank.play_current("ui:press_oneshot", "ui", 0.0, "old", false):
		failures.append("Late one-shot was replayed")
	if not bank.play_current("ui:press_oneshot", "ui", 0.0, "current", true):
		failures.append("Current one-shot could not play")
	if bank.play_current("ui:press_oneshot", "ui", 0.0, "current", true):
		failures.append("One-shot event identity was replayed")
	await process_frame
	bank.set_muted(true)
	var pools: Dictionary = bank.get("_pools")
	var players: int = 0
	for group: String in pools:
		for player: AudioStreamPlayer in pools[group]:
			players += 1
			if player.playing or player.stream != null:
				failures.append("Muted player retains a decoder stream")
	if players != 16:
		failures.append("Fixed audio pool size mismatch")
	bank.free()
	# Let the audio server release the stopped playback before process shutdown.
	await create_timer(0.08).timeout
	var result: Dictionary = {"effects_instantiated":effects.effects.size(),"audio_players":players,
		"late_one_shot":"omitted", "duplicate_one_shot":"omitted", "mute":"all playback stopped and stream references released",
		"failures":failures, "sound_bank_sha256":FileAccess.get_sha256("res://tools/assets/sound_bank.gd")}
	var file := FileAccess.open("res://art-source/production/validation/auxiliary.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print("AUXILIARY_ASSET_RESULT=" + JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
