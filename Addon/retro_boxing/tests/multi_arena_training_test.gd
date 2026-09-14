extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var manager := BalanceTrainingManager.new()
	manager.arena_count = 4
	manager.reset_terminal_arenas = false
	root.add_child(manager)
	assert(manager.arenas.size() == 4)
	var gravity_scales := [0.1, 0.3, 0.6, 1.0]
	for i in manager.arenas.size():
		manager.arenas[i].set_gravity_scale(gravity_scales[i])
		assert(is_equal_approx(manager.arenas[i].get_gravity_scale(), gravity_scales[i]))
		assert(manager.arenas[i].position == Vector3((i % 2) * 12.0, 0.0, (i / 2) * 12.0))
	await physics_frame
	var observations := manager.get_observations()
	assert(observations.size() == 4)
	for observation in observations:
		assert(not observation.is_empty())
	var actions: Array = []
	for arena in manager.arenas:
		actions.append(arena.get_neutral_action())
	manager.apply_actions(actions)
	var other_elapsed: float = manager.arenas[1].episode.elapsed_time
	manager.arenas[0].reset()
	assert(manager.arenas[0].episode.elapsed_time == 0.0)
	assert(manager.arenas[1].episode.elapsed_time == other_elapsed)
	manager.arenas[0].set_gravity_scale(0.1)
	for repetition in 10:
		manager.arenas[0].reset()
	assert(is_equal_approx(manager.arenas[0].get_gravity_scale(), 0.1))
	for body in manager.arenas[0].ragdoll.bone_sim.get_children():
		if body is PhysicalBone3D:
			assert(is_equal_approx(body.gravity_scale, 0.1))
	manager.set_physics_process(false)
	manager.physics_tick = 0
	manager.policy_step_count = 0
	for tick in 240:
		manager._physics_process(1.0 / 240.0)
	assert(manager.policy_step_count == 60)
	for tick in 720:
		manager._physics_process(1.0 / 240.0)
	assert(manager.policy_step_count == 240)
	var states := manager.get_terminal_states()
	assert(states.size() == 4)
	assert(states[0].has("failed") and states[0].has("timed_out"))
	print("Multi-arena training tests passed")
	quit()
