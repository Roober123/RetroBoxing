extends SceneTree

const STEP_COUNT := 2000

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var manager := BalanceTrainingManager.new()
	manager.arena_count = 2
	manager.initial_gravity_scale = 1.0
	root.add_child(manager)
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var random_statistics: Dictionary
	for step in STEP_COUNT:
		var actions: Array = []
		for arena in manager.arenas:
			var action := arena.get_neutral_action()
			if step < STEP_COUNT / 2:
				for i in action.size():
					action[i] = rng.randf_range(-1.0, 1.0)
			actions.append(action)
		manager.begin_policy_step(actions)
		while manager.is_policy_step_in_progress():
			await physics_frame
		var result := manager.last_step_result
		assert(result.observations.size() == manager.arena_count)
		for i in manager.arena_count:
			assert(result.observations[i].size() == manager.get_observation_size())
			assert(typeof(result.terminated[i]) == TYPE_BOOL)
			assert(typeof(result.truncated[i]) == TYPE_BOOL)
			assert(is_finite(result.rewards[i]))
			for value in result.observations[i]:
				assert(is_finite(value) and absf(value) <= BalanceStateProvider.NORMALIZED_LIMIT)
			for body in manager.arenas[i].ragdoll.bone_sim.get_children():
				if body is PhysicalBone3D:
					assert(body.global_transform.is_finite())
					assert(body.linear_velocity.is_finite() and body.angular_velocity.is_finite())
		if step == STEP_COUNT / 2 - 1:
			random_statistics = manager.get_training_statistics().duplicate()
	var statistics := manager.get_training_statistics()
	var neutral_statistics := {
		"episode_count": statistics.episode_count - random_statistics.episode_count,
		"failed_episode_count": statistics.failed_episode_count - random_statistics.failed_episode_count,
		"timed_out_episode_count": statistics.timed_out_episode_count - random_statistics.timed_out_episode_count,
		"policy_steps": STEP_COUNT / 2,
	}
	print("Random policy statistics: ", random_statistics)
	print("Neutral policy baseline: ", neutral_statistics)
	print("RL environment stress tests passed")
	quit()
