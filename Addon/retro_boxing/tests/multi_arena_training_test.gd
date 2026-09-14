extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var manager := BalanceTrainingManager.new()
	manager.arena_count = 4
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
		assert(observation.size() == manager.get_observation_size())
		for value in observation:
			assert(is_finite(value))
	assert(manager.get_action_size() == 12)
	assert(manager.get_rewards().size() == 4)
	for reward in manager.get_rewards():
		assert(is_finite(reward))
	var actions: Array = []
	for arena in manager.arenas:
		actions.append(arena.get_neutral_action())
	manager.begin_policy_step(actions)
	assert(manager.is_policy_step_in_progress())
	await manager.policy_step_completed
	assert(not manager.is_policy_step_in_progress())
	assert(manager.last_step_result.observations.size() == 4)
	assert(manager.last_step_result.rewards.size() == 4)
	assert(manager.last_step_result.terminated.size() == 4)
	assert(manager.last_step_result.truncated.size() == 4)
	manager.arenas[0].episode.minimum_pelvis_height = manager.arenas[0].episode._pelvis.global_position.y + 1.0
	var survivor_elapsed := manager.arenas[1].episode.elapsed_time
	manager.begin_policy_step(actions)
	await manager.policy_step_completed
	assert(manager.last_step_result.terminated[0])
	assert(manager.last_step_result.terminal_observations[0].size() == manager.get_observation_size())
	assert(manager.last_step_result.terminal_observations[1].is_empty())
	assert(manager.arenas[0].episode.elapsed_time == 0.0)
	assert(is_equal_approx(manager.arenas[1].episode.elapsed_time - survivor_elapsed, 4.0 / 240.0))
	manager.arenas[0].episode.minimum_pelvis_height = 0.45
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
	var states := manager.get_terminal_states()
	assert(states.size() == 4)
	assert(states[0].has("failed") and states[0].has("timed_out"))
	print("Multi-arena training tests passed")
	quit()
