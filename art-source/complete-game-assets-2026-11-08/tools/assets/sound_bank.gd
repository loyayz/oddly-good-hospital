extends Node

## Fixed shared pools; the caller provides current, already selected sources.
const LIMITS: Dictionary = {"facility": 6, "actor": 6, "ui": 2, "music": 2}
var _pools: Dictionary = {}
var _clips: Dictionary = {}
var _streams: Dictionary = {}
var _seen: Dictionary = {}
var muted: bool = false

func _ready() -> void:
	var index: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/audio/index.json"))
	for clip: Dictionary in index.clips:
		_clips[str(clip.id)] = clip
	for group: String in LIMITS:
		_pools[group] = []
		for count: int in int(LIMITS[group]):
			var player := AudioStreamPlayer.new()
			player.name = group + str(count)
			add_child(player)
			_pools[group].append(player)

func set_muted(value: bool) -> void:
	muted = value
	if muted:
		stop_scene(true)

func stop_scene(include_music: bool = false) -> void:
	for group: String in _pools:
		if group == "music" and not include_music:
			continue
		for player: AudioStreamPlayer in _pools[group]:
			player.stop()
			player.stream = null
	_streams.clear()

func play_current(id: String, group: String, progress: float = 0.0, event_key: String = "", is_current: bool = true) -> bool:
	if muted or not _clips.has(id) or not _pools.has(group):
		return false
	var definition: Dictionary = _clips[id]
	var looped: bool = bool(definition.loop)
	if not looped and (not is_current or (not event_key.is_empty() and _seen.has(event_key))):
		return false
	var available: AudioStreamPlayer = null
	for player: AudioStreamPlayer in _pools[group]:
		if not player.playing:
			available = player
			break
	if available == null:
		return false
	if not _streams.has(id):
		var stream: AudioStreamOggVorbis = load("res://" + str(definition.path)) as AudioStreamOggVorbis
		if stream == null:
			return false
		stream.loop = looped
		_streams[id] = stream
	available.stream = _streams[id]
	available.pitch_scale = 1.0
	available.volume_db = -13.0 if group == "music" else -17.0
	available.play(clampf(progress, 0.0, 1.0) * available.stream.get_length() if looped else 0.0)
	if not looped and not event_key.is_empty():
		_seen[event_key] = true
		if _seen.size() > 512:
			_seen.erase(_seen.keys()[0])
	return true
