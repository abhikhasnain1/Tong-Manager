extends SceneTree
## Receipt presentation only. Money/ledger behavior has separate authority tests.

var checks := 0
var failures: Array[String] = []
var host: Control
var feedback: PaymentFeedback
var started: Array[StringName] = []
var finished: Array[StringName] = []
var sounds: Array[StringName] = []
var serial := 0


func _init() -> void:
	run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)


func frames() -> void:
	await process_frame
	await process_frame


func receipt(source_id: StringName = &"", generation := 1) -> Dictionary:
	serial += 1
	return {"source_id": source_id if not source_id.is_empty() else StringName("payment_%d" % serial),
		"generation": generation, "kind": &"income", "amount": 25,
		"metadata": {"order_id": &"sample_order", "reasons": [&"cold_tea"]}}


func show(record: Dictionary) -> bool:
	return feedback.show_payment(record, Vector2(600, 450), Vector2(150, 40))


func check_receipt_lifecycle() -> void:
	var record := receipt(&"unique_sale")
	var untouched := record.duplicate(true)
	check(show(record), "A confirmed positive receipt starts presentation")
	check(feedback.get_active_count() == 1 and started == [&"unique_sale"], "One receipt creates one animation and start event")
	check(feedback.has_presented(&"unique_sale", 1), "Presentation remembers stable generation and source identity")
	record.amount = 90
	record.metadata.reasons.clear()
	var snapshots := feedback.get_active_snapshots()
	check(snapshots[0].record == untouched, "Incoming record and nested metadata are copied")
	snapshots[0].record.amount = 200
	snapshots[0].record.metadata.reasons.append(&"changed")
	check(feedback.get_active_snapshots()[0].record == untouched, "Inspection snapshots cannot mutate the active receipt")
	check(not show(record) and feedback.get_active_count() == 1, "Conflicting duplicate source cannot replay a cue")
	check(show(receipt(&"concurrent_sale")) and feedback.get_active_count() == 2, "Concurrent new payments retain separate animations")
	feedback.set_process(false)
	feedback._process(feedback.config.duration * .5)
	var midway := feedback.get_active_snapshots()
	check(midway.size() == 2 and midway[0].elapsed > 0.0 and midway[0].elapsed < midway[0].duration, "Both animations advance without replacing one another")
	var point: Vector2 = midway[0].positions[0]
	check(point.x < 600 and point.x > 150 and point.y < 450 and point.y > 0, "Coin travels smoothly toward cash HUD")
	feedback._process(feedback.config.duration)
	check(feedback.get_active_count() == 0 and finished.size() == 2, "Finished visual receipts are removed with one completion each")
	check(not show(untouched) and finished.count(&"unique_sale") == 1, "Completed receipt cannot replay")
	check(show(receipt(&"unique_sale", 2)), "Explicit new finance generation may reuse source identity")
	feedback.clear_feedback()
	check(feedback.get_active_count() == 0 and not feedback.is_sound_playing(), "Clear stops visuals and audio together")
	check(not show(receipt(&"unique_sale", 2)), "Clearing visual effects does not forget accepted identity")
	check(untouched.amount == 25 and untouched.metadata.reasons == [&"cold_tea"], "Component never writes a caller's monetary or review data")


func check_validation() -> void:
	for invalid in [{}, {"source_id": &"", "amount": 25}, {"source_id": &"  ", "amount": 25},
		{"source_id": 1, "amount": 25}, {"source_id": &"negative", "amount": -1},
		{"source_id": &"zero", "amount": 0}, {"source_id": &"fraction", "amount": 1.5},
		{"source_id": &"bool", "amount": true}, {"source_id": &"expense", "amount": 1, "kind": &"expense"},
		{"source_id": &"bad_generation", "amount": 1, "generation": -1}]:
		check(not show(invalid) and feedback.get_active_count() == 0, "Malformed or non-income record produces no cue")
	var record := receipt()
	check(not feedback.show_payment(record, Vector2(NAN, 0), Vector2.ZERO), "Nonfinite origin refuses presentation safely")
	check(not feedback.show_payment(record, Vector2.ZERO, Vector2(INF, 0)), "Nonfinite HUD destination refuses presentation safely")
	feedback.scale = Vector2(0, 1)
	check(not show(record), "Noninvertible local canvas refuses unsafe geometry")
	feedback.scale = Vector2.ONE
	check(not feedback.has_presented(record.source_id, record.generation), "Rejected geometry does not consume dedupe identity")
	check(show(record), "Valid retry after rejected geometry remains possible")
	var before := feedback.get_active_snapshots()
	for delta in [-1.0, NAN, INF, 0.0]: feedback._process(delta)
	check(feedback.get_active_snapshots() == before, "Invalid elapsed input cannot corrupt animation progress")
	feedback.clear_feedback()


func check_geometry_and_motion() -> void:
	feedback.position = Vector2(30, 20)
	feedback.scale = Vector2(.75, .85)
	var record := receipt()
	check(show(record), "Transformed HUD layer accepts viewport-space endpoints")
	feedback.set_process(false)
	var inverse := feedback.get_global_transform_with_canvas().affine_inverse()
	var first := feedback.get_active_snapshots()[0]
	check((first.from as Vector2).is_equal_approx(inverse * Vector2(600, 450)) and (first.to as Vector2).is_equal_approx(inverse * Vector2(150, 40)), "Viewport endpoints convert correctly to local drawing coordinates")
	var viewport_bounds := root.get_visible_rect()
	for step in 8:
		feedback._process(feedback.config.duration / 10.0)
		for entry in feedback.get_active_snapshots():
			for location: Vector2 in entry.positions:
				check(viewport_bounds.has_point(feedback.get_global_transform_with_canvas() * location), "Animated coin center remains within visible viewport")
	feedback.clear_feedback()
	feedback.position = Vector2.ZERO
	feedback.scale = Vector2.ONE
	check(feedback.show_payment(receipt(), Vector2(-1000, -1000), Vector2(5000, -20)), "Offscreen source/destination are bounded for a visible receipt cue")
	feedback.set_process(false)
	var edge := feedback.get_active_snapshots()[0]
	check(viewport_bounds.encloses(edge.amount_rect), "Amount text stays inside visible viewport at edge destinations")
	for location: Vector2 in edge.positions: check(viewport_bounds.has_point(location), "Offscreen coin endpoint is clamped inside viewport")
	feedback.clear_feedback()
	var reduced := PaymentFeedbackConfig.new()
	reduced.reduced_motion = true
	reduced.sound_enabled = false
	feedback.configure(reduced)
	check(show(receipt()), "Reduced-motion setting still acknowledges a new payment")
	feedback.set_process(false)
	var initial: Vector2 = feedback.get_active_snapshots()[0].positions[0]
	feedback._process(reduced.duration * .4)
	var stationary: Array = feedback.get_active_snapshots()[0].positions
	check(stationary.size() == 2 and stationary[0] == initial, "Reduced motion staggers coin appearance while existing HUD coins stay stationary")
	feedback._process(reduced.duration * .1)
	check(feedback.get_active_snapshots()[0].positions == stationary, "Both reduced-motion coins remain stationary without travel or bob")
	feedback._process(reduced.duration)
	check(feedback.get_active_count() == 0, "Reduced-motion cue still expires promptly")
	feedback.configure(PaymentFeedbackConfig.new())


func check_sound() -> void:
	var stream: AudioStream = feedback.get_chime_stream()
	check(stream is AudioStreamMP3 and stream.resource_path == "res://assets/audio/sfx/coin_drop.mp3",
		"Default feedback loads the selected imported MP3 coin sound")
	var mp3 := stream as AudioStreamMP3
	check(mp3 != null and not mp3.loop and not mp3.data.is_empty(), "Imported MP3 contains audio data and never loops")
	check(stream != null and is_finite(stream.get_length()) and stream.get_length() > 0.0,
		"Imported sound reports a finite positive duration")
	if stream != null:
		var playback: AudioStreamPlayback = stream.instantiate_playback()
		check(playback != null, "Imported MP3 creates a decoder playback")
		if playback != null:
			playback.start()
			var peak := 0.0
			var decoded_frames := 0
			var finite_samples := true
			var remaining := ceili(minf(stream.get_length() + .25, 30.0) * AudioServer.get_mix_rate())
			while remaining > 0 and playback.is_playing():
				var samples: PackedVector2Array = playback.mix_audio(1.0, mini(4096, remaining))
				if samples.is_empty(): break
				remaining -= samples.size()
				decoded_frames += samples.size()
				for sample in samples:
					finite_samples = finite_samples and sample.is_finite()
					peak = maxf(peak, maxf(absf(sample.x), absf(sample.y)))
			check(decoded_frames > 0 and finite_samples and peak > .001,
				"Selected MP3 decodes to finite non-silent PCM through the engine")
			playback.stop()
	var old_mute := AudioServer.is_bus_mute(0)
	AudioServer.set_bus_mute(0, true)
	var before := sounds.size()
	check(show(receipt()), "Muted audio does not hide the visual acknowledgement")
	check(sounds.size() == before and not feedback.is_sound_playing(), "Master mute suppresses coin sound requests")
	feedback.clear_feedback()
	AudioServer.set_bus_mute(0, false)
	var settings := PaymentFeedbackConfig.new()
	settings.sound_bus = &"missing_payment_bus"
	settings.sound_volume_db = -23.0
	feedback.configure(settings)
	check(show(receipt()) and sounds.size() == before + 1, "Unmuted coin launch requests the selected sound once")
	var player := feedback.get_node("PaymentChime") as AudioStreamPlayer
	check(player.bus == &"Master" and player.volume_db == -23.0, "Missing configured bus safely falls back to Master with configured volume")
	feedback.clear_feedback()
	var replacement := stream.duplicate() as AudioStream
	settings.sound_stream = replacement
	feedback.configure(settings)
	check(show(receipt()) and player.stream == replacement,
		"Replacing the configured stream updates a reused idle voice")
	feedback.clear_feedback()
	settings.sound_stream = null
	settings.emit_changed()
	before = sounds.size()
	check(show(receipt()) and feedback.get_active_count() == 1 and sounds.size() == before and not feedback.is_sound_playing(),
		"Missing configured sound still animates the coin silently")
	feedback.clear_feedback()
	settings.sound_stream = stream
	settings.sound_enabled = false
	settings.emit_changed()
	before = sounds.size()
	check(show(receipt()) and sounds.size() == before, "Sound disable preserves receipt animation without playback")
	feedback.clear_feedback()
	feedback.configure(PaymentFeedbackConfig.new())
	AudioServer.set_bus_mute(0, old_mute)


func check_per_coin_audio() -> void:
	var cue := PaymentFeedback.new()
	host.add_child(cue)
	var settings := PaymentFeedbackConfig.new()
	settings.sound_base_pitch = 1.1
	settings.sound_pitch_step_semitones = 3.0
	settings.sound_pitch_cycle = 3
	cue.configure(settings)
	var launches: Array[Dictionary] = []
	var audible: Array[StringName] = []
	cue.coin_launched.connect(func(id: StringName, index: int, pitch: float) -> void:
		launches.append({"source_id": id, "coin_index": index, "pitch": pitch}))
	cue.sound_requested.connect(func(id: StringName) -> void: audible.append(id))
	var first := receipt(&"two_coin_test")
	check(cue.show_payment(first, Vector2(600, 450), Vector2(150, 40)), "Per-coin receipt starts normally")
	cue.set_process(false)
	check(launches.size() == 1 and audible == [&"two_coin_test"] and launches[0].coin_index == 0, "Only the first coin launches and sounds at receipt start")
	check(cue.get_active_snapshots()[0].positions.size() == 1, "Second coin is absent before its actual launch")
	check(is_equal_approx(launches[0].pitch, 1.1), "New component starts at configured base pitch")
	var first_voice := cue.get_voice_snapshots()[0]
	cue._process(settings.coin_launch_stagger_seconds * .5)
	check(launches.size() == 1 and audible.size() == 1, "No early sound or visible coin before stagger deadline")
	cue._process(settings.coin_launch_stagger_seconds * .5)
	check(launches.size() == 2 and audible.size() == 2 and launches[1].coin_index == 1, "Second visible coin gets its own sound at the stagger deadline")
	check(cue.get_active_snapshots()[0].positions.size() == 2, "Two launches produce exactly two drawn coins")
	check(is_equal_approx(launches[1].pitch, 1.1 * pow(2.0, 3.0 / 12.0)), "Second voice uses configured semitone step")
	var voices := cue.get_voice_snapshots()
	check(voices.size() == 2 and voices[0].voice_id != voices[1].voice_id, "Overlapping coin sounds own separate playback voices")
	check(voices[0].voice_id == first_voice.voice_id and voices[0].pitch == first_voice.pitch, "Launching another coin never retunes the already playing voice")
	check(not cue.show_payment(first, Vector2.ZERO, Vector2.ONE) and audible.size() == 2, "Duplicate receipt cannot add any coin sounds")
	check(cue.show_payment(receipt(&"overlapping_coins"), Vector2(800, 450), Vector2(150, 40)), "Concurrent receipt launches independently")
	cue.set_process(false)
	check(launches.size() == 3 and is_equal_approx(launches[2].pitch, 1.1 * pow(2.0, 6.0 / 12.0)), "Pitch sequence also varies across concurrent receipts")
	cue._process(settings.coin_launch_stagger_seconds)
	check(launches.size() == 4 and is_equal_approx(launches[3].pitch, 1.1), "Configured pitch cycle wraps predictably")
	check(cue.get_voice_snapshots()[0].pitch == first_voice.pitch, "Later receipt voices still leave old voice pitch unchanged")
	cue.clear_feedback()
	cue._process(10.0)
	check(launches.size() == 4 and audible.size() == 4 and not cue.is_sound_playing(), "Clearing stops all voices and cannot emit late scheduled sounds")
	for interruption in [&"clear", &"focus", &"resize", &"config", &"detach"]:
		cue.show_payment(receipt(), Vector2.ZERO, Vector2.ONE)
		cue.set_process(false)
		var before := audible.size()
		if interruption == &"clear": cue.clear_feedback()
		elif interruption == &"focus": cue.notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
		elif interruption == &"resize": root.size_changed.emit()
		elif interruption == &"config": settings.emit_changed()
		else: host.remove_child(cue)
		cue._process(1.0)
		check(audible.size() == before and cue.get_active_count() == 0 and not cue.is_sound_playing(), "Lifecycle interruption cancels delayed coin launch: " + String(interruption))
		if interruption == &"focus": cue.notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN)
		elif interruption == &"detach": host.add_child(cue)
	var old_mute := AudioServer.is_bus_mute(0)
	AudioServer.set_bus_mute(0, true)
	var muted_start := audible.size()
	var visible_start := launches.size()
	cue.show_payment(receipt(), Vector2.ZERO, Vector2.ONE)
	cue.set_process(false)
	cue._process(settings.coin_launch_stagger_seconds)
	check(launches.size() == visible_start + 2 and audible.size() == muted_start, "Muted payment still launches two visible coins without either sound")
	AudioServer.set_bus_mute(0, false)
	cue._process(.1)
	check(audible.size() == muted_start, "Unmuting does not replay already launched muted coins")
	cue.clear_feedback()
	var reentrant := receipt(&"cancel_launch")
	var observer := func(_id: StringName, _index: int, _pitch: float) -> void:
		cue.clear_feedback()
		check(not cue.show_payment(reentrant, Vector2.ZERO, Vector2.ONE), "Launch observer cannot reenter a duplicate receipt")
	cue.coin_launched.connect(observer, CONNECT_ONE_SHOT)
	var before_cancel := audible.size()
	cue.show_payment(reentrant, Vector2.ZERO, Vector2.ONE)
	cue._process(1.0)
	check(audible.size() == before_cancel and cue.get_active_count() == 0, "Synchronous launch cancellation prevents both immediate and delayed audio")
	var stop_on_sound := func(_id: StringName) -> void: cue.clear_feedback()
	cue.sound_requested.connect(stop_on_sound, CONNECT_ONE_SHOT)
	cue.show_payment(receipt(), Vector2.ZERO, Vector2.ONE)
	var after_first_sound := audible.size()
	cue._process(1.0)
	check(audible.size() == after_first_sound and not cue.is_sound_playing(), "Sound observer cleanup cannot leave a second delayed sound")
	var replacement := receipt(&"replacement_after_second_launch")
	var second_observer := func(_id: StringName, index: int, _pitch: float) -> void:
		if index == 1:
			cue.clear_feedback()
			cue.show_payment(replacement, Vector2.ZERO, Vector2.ONE)
			cue.set_process(false)
	cue.coin_launched.connect(second_observer)
	cue.show_payment(receipt(), Vector2.ZERO, Vector2.ONE)
	cue.set_process(false)
	var before_second_cancel := audible.size()
	cue._process(.11)
	check(cue.get_active_count() == 1 and cue.get_active_snapshots()[0].source_id == replacement.source_id,
		"Second-coin observer may clear and replace a receipt without corrupting active iteration")
	check(audible.size() == before_second_cancel + 1 and audible.back() == replacement.source_id,
		"Replacement sounds its first coin without an old second-coin sound leaking after cleanup")
	cue.coin_launched.disconnect(second_observer)
	cue.clear_feedback()
	cue.show_payment(receipt(), Vector2.ZERO, Vector2.ONE)
	cue.set_process(false)
	var before_mid_mute := audible.size()
	AudioServer.set_bus_mute(0, true)
	cue._process(.11)
	check(audible.size() == before_mid_mute and cue.get_active_snapshots()[0].positions.size() == 2,
		"Muting between launches suppresses only the next sound while its coin still appears")
	AudioServer.set_bus_mute(0, false)
	cue.clear_feedback()
	settings.sound_base_pitch = NAN
	settings.sound_pitch_step_semitones = INF
	settings.sound_pitch_cycle = 0
	settings.coin_launch_stagger_seconds = NAN
	cue.show_payment(receipt(), Vector2.ZERO, Vector2.ONE)
	cue.set_process(false)
	check(is_equal_approx(launches.back().pitch, 1.0), "Nonfinite pitch settings and invalid cycle safely use bounded defaults")
	cue._process(.11)
	check(cue.get_active_snapshots()[0].positions.size() == 2, "Nonfinite stagger uses the finite default")
	cue.clear_feedback()
	AudioServer.set_bus_mute(0, old_mute)
	cue.queue_free()


func check_cleanup() -> void:
	var record := receipt()
	show(record)
	feedback.notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(feedback.get_active_count() == 0 and not feedback.is_sound_playing(), "Focus loss clears transient visuals and audio")
	check(not show(receipt()), "Unfocused component does not start unseen coin motion")
	feedback.notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN)
	check(not show(record), "Focus return cannot replay a payment cleared during focus loss")
	check(show(receipt()), "Focus return permits genuinely new receipts")
	host.hide()
	check(feedback.get_active_count() == 0 and not feedback.is_sound_playing() and not show(receipt()), "Ancestor hiding clears and suppresses transient feedback")
	host.show()
	show(receipt())
	root.size_changed.emit()
	check(feedback.get_active_count() == 0 and not feedback.is_sound_playing(), "Viewport resizing clears stale endpoint animations")
	show(receipt())
	feedback.config.emit_changed()
	check(feedback.get_active_count() == 0, "Configuration change clears an active presentation")
	show(receipt())
	feedback.configure(PaymentFeedbackConfig.new())
	check(feedback.get_active_count() == 0 and not feedback.is_sound_playing(), "Replacing configuration stops old effects")
	show(receipt())
	host.remove_child(feedback)
	check(feedback.get_active_count() == 0 and not feedback.is_sound_playing(), "Scene exit stops effects without waiting for audio-finished signals")
	check(not show(receipt()), "Detached component refuses new feedback")
	host.add_child(feedback)
	await frames()
	check(show(receipt()), "Reentered component can present new receipts")
	root.size_changed.emit()
	check(feedback.get_active_count() == 0, "Reentry restores viewport cleanup subscription")
	show(receipt())
	feedback.config.emit_changed()
	check(feedback.get_active_count() == 0, "Reentry restores configuration cleanup subscription")


func check_reentrant_signals() -> void:
	var attempt := {"accepted": true}
	var record := receipt()
	var callback := func(_id: StringName) -> void:
		attempt.accepted = show(record)
		feedback.clear_feedback()
	feedback.feedback_started.connect(callback, CONNECT_ONE_SHOT)
	var before := sounds.size()
	check(show(record) and not attempt.accepted, "A synchronous observer cannot replay the receipt being announced")
	check(feedback.get_active_count() == 0 and sounds.size() == before, "Clearing from start observer prevents a ghost animation or late chime")
	var completed := {"count": 0}
	var finish_callback := func(_id: StringName) -> void:
		completed.count += 1
		show(receipt())
	feedback.feedback_finished.connect(finish_callback, CONNECT_ONE_SHOT)
	show(receipt())
	feedback.set_process(false)
	feedback._process(10.0)
	check(completed.count == 1 and feedback.get_active_count() == 1, "Completion observer can start a separate receipt without corrupting iteration")
	feedback.clear_feedback()


func check_passthrough(node: Node) -> void:
	if node is Control:
		check(node.mouse_filter == Control.MOUSE_FILTER_IGNORE and node.focus_mode == Control.FOCUS_NONE, "Receipt controls never capture pointer or keyboard focus")
	for child in node.get_children(): check_passthrough(child)


func run() -> void:
	await frames()
	host = Control.new()
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(host)
	feedback = PaymentFeedback.new()
	host.add_child(feedback)
	feedback.configure(PaymentFeedbackConfig.new())
	feedback.feedback_started.connect(func(id: StringName) -> void: started.append(id))
	feedback.feedback_finished.connect(func(id: StringName) -> void: finished.append(id))
	feedback.sound_requested.connect(func(id: StringName) -> void: sounds.append(id))
	await frames()
	check_receipt_lifecycle()
	check_validation()
	check_geometry_and_motion()
	check_sound()
	check_per_coin_audio()
	await check_cleanup()
	check_reentrant_signals()
	check_passthrough(feedback)
	host.queue_free()
	await frames()
	# Playback stop commands cross to the audio thread. Let its final short
	# mixing block retire before terminating this deliberately accelerated test.
	await create_timer(.35).timeout
	print("PAYMENT_FEEDBACK: %d checks; %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
