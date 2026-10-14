class_name PaymentFeedback
extends Control
## A disposable receipt cue. Confirmed payment authority lives elsewhere.

signal feedback_started(source_id: StringName)
signal feedback_finished(source_id: StringName)
signal sound_requested(source_id: StringName)
signal coin_launched(source_id: StringName, coin_index: int, pitch: float)

const COIN_COUNT := 2

var config: PaymentFeedbackConfig = preload("res://data/balance/payment_feedback.tres")
var _entries: Array[Dictionary] = []
var _seen: Dictionary = {}
var _voices: Array[AudioStreamPlayer] = []
var _pitch_serial := 0
var _clear_revision := 0
var _focused := true
var _serial := 0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	set_process(false)


func _ready() -> void:
	_attach_lifecycle()


func _enter_tree() -> void:
	_attach_lifecycle.call_deferred()


func _attach_lifecycle() -> void:
	if not is_inside_tree() or is_queued_for_deletion(): return
	if not get_viewport().size_changed.is_connected(clear_feedback):
		get_viewport().size_changed.connect(clear_feedback)
	if not visibility_changed.is_connected(_on_visibility_changed):
		visibility_changed.connect(_on_visibility_changed)
	_connect_config()


func configure(value: PaymentFeedbackConfig) -> void:
	clear_feedback()
	if config != null and config.changed.is_connected(_on_config_changed):
		config.changed.disconnect(_on_config_changed)
	config = value if value != null else PaymentFeedbackConfig.new()
	_connect_config()


func _connect_config() -> void:
	if config != null and not config.changed.is_connected(_on_config_changed):
		config.changed.connect(_on_config_changed)


func _on_config_changed() -> void:
	clear_feedback()


func show_payment(record: Dictionary, from_viewport: Vector2, to_viewport: Vector2) -> bool:
	if (not is_inside_tree() or is_queued_for_deletion() or not is_visible_in_tree() or not _focused
		or not from_viewport.is_finite() or not to_viewport.is_finite()
		or typeof(record.get("source_id")) not in [TYPE_STRING, TYPE_STRING_NAME]
		or String(record.source_id).strip_edges().is_empty()
		or typeof(record.get("amount")) != TYPE_INT or record.amount <= 0
		or typeof(record.get("generation", 0)) != TYPE_INT or record.get("generation", 0) < 0
		or record.get("kind", &"income") != &"income"):
		return false
	var source_id := StringName(record.source_id)
	var generation: int = record.get("generation", 0)
	var key := _key(source_id, generation)
	if _seen.has(key): return false
	var canvas := get_global_transform_with_canvas()
	if not canvas.is_finite() or is_zero_approx(canvas.determinant()): return false
	var inverse := canvas.affine_inverse()
	var duration := _finite_clamped(config.duration, 0.85, 0.2, 2.0)
	var scale_value := _finite_clamped(config.coin_scale, 1.0, 0.5, 2.0)
	var record_copy := record.duplicate(true)
	_serial += 1
	var entry := {"key": key, "source_id": source_id, "generation": generation,
		"record": record_copy, "elapsed": 0.0, "duration": duration,
		"from": inverse * from_viewport, "to": inverse * to_viewport,
		"reduced_motion": config.reduced_motion, "scale": scale_value,
		"arc": _finite_clamped(config.arc_height, 32.0, 0.0, 80.0),
		"font_size": clampi(config.amount_font_size, 12, 32), "serial": _serial,
		"stagger": minf(duration * 0.45, _finite_clamped(config.coin_launch_stagger_seconds, 0.11, 0.04, 0.2)),
		"coins": [{"launched": false, "pitch": 1.0}, {"launched": false, "pitch": 1.0}]}
	_seen[key] = true
	_entries.append(entry)
	set_process(true)
	queue_redraw()
	var self_ref: WeakRef = weakref(self)
	feedback_started.emit(source_id)
	if self_ref.get_ref() != null and is_inside_tree() and not is_queued_for_deletion():
		_launch_due_coins(key)
	return true


func has_presented(source_id: StringName, generation := 0) -> bool:
	return _seen.has(_key(source_id, generation))


func get_active_count() -> int:
	return _entries.size()


func get_active_snapshots() -> Array[Dictionary]:
	var snapshots: Array[Dictionary] = []
	for entry in _entries:
		var copy := entry.duplicate(true)
		copy["positions"] = _coin_positions(entry)
		copy["amount_rect"] = _amount_rect(entry)
		snapshots.append(copy)
	return snapshots


func get_chime_stream() -> AudioStream:
	return config.sound_stream


func is_sound_playing() -> bool:
	for voice in _voices:
		if is_instance_valid(voice) and voice.playing: return true
	return false


func get_voice_snapshots() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for voice in _voices:
		if is_instance_valid(voice) and voice.playing:
			result.append({"voice_id": voice.get_instance_id(), "pitch": voice.pitch_scale,
				"source_id": voice.get_meta("source_id", &""), "coin_index": voice.get_meta("coin_index", -1),
				"bus": voice.bus, "volume_db": voice.volume_db})
	return result


func clear_feedback() -> void:
	_clear_revision += 1
	_entries.clear()
	for voice in _voices:
		if is_instance_valid(voice): voice.stop()
	set_process(false)
	queue_redraw()


func _process(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0: return
	var revision := _clear_revision
	var keys: Array[String] = []
	for entry in _entries: keys.append(entry.key)
	var completed: Array[StringName] = []
	var self_ref: WeakRef = weakref(self)
	for key in keys:
		var index := _find_entry(key)
		if index < 0: continue
		_entries[index].elapsed = minf(_entries[index].duration, _entries[index].elapsed + delta)
		if _entries[index].elapsed >= _entries[index].duration:
			completed.append(_entries[index].source_id)
			_entries.remove_at(index)
		else:
			_launch_due_coins(key)
			if self_ref.get_ref() == null or not is_inside_tree() or is_queued_for_deletion(): return
			if revision != _clear_revision: return
	set_process(not _entries.is_empty())
	queue_redraw()
	for source_id in completed:
		feedback_finished.emit(source_id)
		if self_ref.get_ref() == null or not is_inside_tree() or is_queued_for_deletion(): return
		if revision != _clear_revision: return


func _launch_due_coins(key: String) -> void:
	var self_ref: WeakRef = weakref(self)
	for coin_index in COIN_COUNT:
		var index := _find_entry(key)
		if index < 0 or not is_inside_tree() or is_queued_for_deletion(): return
		var entry: Dictionary = _entries[index]
		if entry.coins[coin_index].launched or entry.elapsed < entry.stagger * coin_index: continue
		var pitch := _finite_clamped(config.sound_base_pitch, 1.0, 0.5, 2.0) * pow(2.0,
			_finite_clamped(config.sound_pitch_step_semitones, 2.0, 0.0, 7.0) * float(_pitch_serial % clampi(config.sound_pitch_cycle, 1, 8)) / 12.0)
		pitch = clampf(pitch, 0.5, 4.0)
		_pitch_serial += 1
		entry.coins[coin_index] = {"launched": true, "pitch": pitch}
		coin_launched.emit(entry.source_id, coin_index, pitch)
		if self_ref.get_ref() == null or not is_inside_tree() or is_queued_for_deletion(): return
		if _find_entry(key) < 0: return
		_play_chime(entry.source_id, coin_index, pitch)
		if self_ref.get_ref() == null or not is_inside_tree() or is_queued_for_deletion(): return


func _key(source_id: StringName, generation: int) -> String:
	return str(generation) + ":" + String(source_id)


func _find_entry(key: String) -> int:
	for index in _entries.size():
		if _entries[index].key == key: return index
	return -1


func _local_view_rect() -> Rect2:
	var inverse := get_global_transform_with_canvas().affine_inverse()
	return inverse * get_viewport().get_visible_rect()


func _coin_positions(entry: Dictionary) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var bounds := _local_view_rect().grow(-14.0 * entry.scale)
	for index in COIN_COUNT:
		if not entry.coins[index].launched: continue
		var time := _coin_progress(entry, index)
		var eased := time * time * (3.0 - 2.0 * time)
		var location: Vector2 = entry.to if entry.reduced_motion else (entry.from as Vector2).lerp(entry.to, eased)
		if not entry.reduced_motion:
			location.y -= sin(PI * time) * entry.arc
		location += Vector2(float(index) * 9.0, -float(index) * 8.0) * entry.scale
		location = location.clamp(bounds.position, bounds.end)
		result.append(location)
	return result


func _coin_progress(entry: Dictionary, index: int) -> float:
	var delay: float = entry.stagger * index
	return clampf((entry.elapsed - delay) / (entry.duration - delay), 0.0, 1.0)


func _amount_rect(entry: Dictionary) -> Rect2:
	var text := "+" + str(entry.record.amount)
	var font := ThemeDB.fallback_font
	var size_value := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, entry.font_size) + Vector2(8.0, 4.0)
	var location: Vector2 = entry.to + Vector2(16.0 * entry.scale, -size_value.y * 0.5)
	# Stagger concurrent receipts near the HUD rather than printing on a customer.
	location.y += float((entry.serial - 1) % 3) * (size_value.y + 2.0)
	var bounds := _local_view_rect().grow(-4.0)
	location = location.clamp(bounds.position, bounds.end - size_value)
	return Rect2(location, size_value)


func _draw() -> void:
	for entry in _entries:
		var progress: float = entry.elapsed / entry.duration
		var alpha := minf(1.0, progress / 0.1) * minf(1.0, (1.0 - progress) / 0.18)
		var positions := _coin_positions(entry)
		for index in positions.size():
			var coin_alpha := minf(1.0, _coin_progress(entry, index) / 0.045) * minf(1.0, (1.0 - progress) / 0.18)
			_draw_coin(positions[index], 10.0 * entry.scale, coin_alpha)
		if progress > 0.68 or entry.reduced_motion:
			var rect := _amount_rect(entry)
			var font := ThemeDB.fallback_font
			var baseline := rect.position + Vector2(4.0, font.get_ascent(entry.font_size) + 2.0)
			var text := "+" + str(entry.record.amount)
			draw_string_outline(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, entry.font_size, 3, Color(config.ink, alpha))
			draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, entry.font_size, Color(config.shine, alpha))


func _draw_coin(center: Vector2, radius: float, alpha: float) -> void:
	draw_circle(center + Vector2(0, 1.5), radius + 0.5, Color(config.ink, alpha * 0.25), true, -1.0, true)
	draw_circle(center, radius, Color(config.edge, alpha), true, -1.0, true)
	draw_circle(center, radius - 1.8, Color(config.gold, alpha), true, -1.0, true)
	draw_arc(center, radius - 3.0, PI * 1.1, PI * 1.8, 16, Color(config.shine, alpha), 1.4, true)
	draw_arc(center, radius * 0.35, 0, TAU, 16, Color(config.edge, alpha * 0.75), 1.2, true)
	draw_line(center + Vector2(0, -radius * 0.5), center + Vector2(0, radius * 0.5), Color(config.edge, alpha * 0.75), 1.2, true)


func _available_voice() -> AudioStreamPlayer:
	for voice in _voices:
		if is_instance_valid(voice) and not voice.playing: return voice
	var voice := AudioStreamPlayer.new()
	voice.name = "PaymentChime" if _voices.is_empty() else "PaymentCoinVoice%d" % _voices.size()
	# Each overlapping coin owns its pitch; never retune a playing voice.
	voice.max_polyphony = 1
	add_child(voice)
	_voices.append(voice)
	return voice


func _play_chime(source_id: StringName, coin_index: int, pitch: float) -> void:
	if not config.sound_enabled or not _focused or not is_visible_in_tree(): return
	var stream := get_chime_stream()
	if stream == null: return
	var bus := config.sound_bus if AudioServer.get_bus_index(config.sound_bus) >= 0 else &"Master"
	var current := AudioServer.get_bus_index(bus)
	var checked: Array[int] = []
	while current >= 0 and not checked.has(current):
		checked.append(current)
		if AudioServer.is_bus_mute(current): return
		if current == 0: break
		current = AudioServer.get_bus_index(AudioServer.get_bus_send(current))
	var voice := _available_voice()
	voice.stream = stream
	voice.bus = bus
	voice.volume_db = _finite_clamped(config.sound_volume_db, -17.0, -60.0, 0.0)
	voice.pitch_scale = pitch
	voice.set_meta("source_id", source_id)
	voice.set_meta("coin_index", coin_index)
	voice.play()
	sound_requested.emit(source_id)


static func _finite_clamped(value: float, fallback: float, minimum: float, maximum: float) -> float:
	return clampf(value, minimum, maximum) if is_finite(value) else fallback


func _on_visibility_changed() -> void:
	if not is_visible_in_tree(): clear_feedback()


func _notification(what: int) -> void:
	if what in [NOTIFICATION_WM_WINDOW_FOCUS_OUT, MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT]:
		_focused = false
		clear_feedback()
	elif what in [NOTIFICATION_WM_WINDOW_FOCUS_IN, MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN]:
		_focused = true


func _exit_tree() -> void:
	clear_feedback()
	if config != null and config.changed.is_connected(_on_config_changed): config.changed.disconnect(_on_config_changed)
	if get_viewport() != null and get_viewport().size_changed.is_connected(clear_feedback): get_viewport().size_changed.disconnect(clear_feedback)
