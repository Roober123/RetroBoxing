extends SceneTree

class TickProbe extends Node:
	var ticks := 0
	func _physics_process(_delta: float) -> void:
		ticks += 1

var known_terminal := PackedFloat32Array()

const Checks = preload("res://Addon/retro_boxing/tests/training_checks.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var manager := BalanceTrainingManager.new()
	manager.arena_count = 4
	physics_frame.connect(func():
		if is_instance_valid(manager) and manager.is_policy_step_in_progress() and manager._ticks_remaining == 0:
			known_terminal = manager.arenas[0].get_observation()
	)
	root.add_child(manager)
	var probe := TickProbe.new()
	manager.arenas[0].add_child(probe)
	assert(manager.is_waiting_for_action())
	assert(manager.get_observation_size() == 175)
	await Checks.check_frozen(manager)
	assert(probe.ticks == 0)
	var actions: Array = []
	for arena in manager.arenas:
		actions.append(arena.get_neutral_action())
	var before_tick := manager.physics_tick
	manager.begin_policy_step(actions)
	assert(manager.is_policy_step_in_progress())
	await manager.policy_step_completed
	assert(manager.physics_tick - before_tick == 4)
	assert(probe.ticks == manager.physics_tick)
	Checks.check_result(manager)
	for i in manager.arena_count:
		assert(not manager.last_step_result.terminated[i])
		assert(not manager.last_step_result.truncated[i])
		assert(is_equal_approx(manager.arenas[i].episode.elapsed_time, 4.0 / 240.0))
	await Checks.check_frozen(manager)
	# Failure, timeout, simultaneous failure+timeout, and survivor in one batch.
	manager.arenas[0].episode.minimum_pelvis_height = 100.0
	manager.arenas[1].episode.maximum_episode_duration = 0.025
	manager.arenas[2].episode.minimum_pelvis_height = 100.0
	manager.arenas[2].episode.maximum_episode_duration = 0.025
	actions[0].fill(0.7)
	before_tick = manager.physics_tick
	manager.begin_policy_step(actions)
	await manager.policy_step_completed
	assert(manager.physics_tick - before_tick == 4)
	assert(probe.ticks == manager.physics_tick)
	Checks.check_result(manager)
	var result := manager.last_step_result
	assert(result.terminated == [true, false, true, false])
	assert(result.truncated == [false, true, false, false])
	assert(result.terminal_observations[0] == known_terminal)
	assert(result.terminal_observations[0] != result.observations[0])
	assert(result.terminal_observations[0].slice(163) == actions[0])
	for i in 3:
		assert(result.observations[i].slice(163) == manager.arenas[i].get_neutral_action())
		assert(manager.arenas[i].episode.elapsed_time == 0.0)
	assert(manager.failed_episode_count == 2)
	assert(manager.timed_out_episode_count == 1)
	await Checks.check_frozen(manager)
	assert(probe.ticks == 8)
	manager.free()
	assert(not paused)
	print("Training transition tests passed")
	quit()
