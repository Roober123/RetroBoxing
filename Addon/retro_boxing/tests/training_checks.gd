extends RefCounted

static func snapshot(manager: BalanceTrainingManager) -> Array:
	var values: Array = [manager.physics_tick, manager.policy_step_count]
	for arena in manager.arenas:
		values.append(arena.episode.elapsed_time)
		values.append(arena.get_observation())
		values.append(arena.ragdoll.target_controller.current.rotations.duplicate())
		for body in arena.ragdoll.bone_sim.get_children():
			if body is PhysicalBone3D:
				values.append([body.global_transform, body.linear_velocity, body.angular_velocity])
	return values

static func check_frozen(manager: BalanceTrainingManager) -> void:
	assert(manager.is_waiting_for_action())
	assert(not manager.is_policy_step_in_progress())
	var before := snapshot(manager)
	for frame in 8:
		await manager.get_tree().physics_frame
		assert(snapshot(manager) == before, "Simulation advanced while waiting")
	for frame in 3:
		await manager.get_tree().process_frame
		assert(snapshot(manager) == before, "Simulation advanced on idle frame")

static func check_result(manager: BalanceTrainingManager) -> void:
	assert(manager.is_waiting_for_action())
	var result := manager.last_step_result
	assert(result.observations.size() == manager.arena_count)
	for i in manager.arena_count:
		assert(not (result.terminated[i] and result.truncated[i]))
		assert(is_finite(result.rewards[i]))
		assert(result.observations[i].size() == manager.get_observation_size())
		assert(result.observations[i] == manager.arenas[i].get_observation())
		var finished: bool = result.terminated[i] or result.truncated[i]
		assert(result.terminal_observations[i].is_empty() == not finished)
		if finished:
			assert(result.terminal_observations[i].size() == manager.get_observation_size())
		for observation in [result.observations[i], result.terminal_observations[i]]:
			for value in observation:
				assert(is_finite(value))
