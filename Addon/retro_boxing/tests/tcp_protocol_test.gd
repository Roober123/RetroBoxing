extends SceneTree

const Protocol = preload("res://Ragdoll/balance_tcp_protocol.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var manager := BalanceTrainingManager.new()
	manager.arena_count = 2
	root.add_child(manager)
	var hello := Protocol.packet(Protocol.Command.HELLO, Protocol.hello(manager))
	assert(hello.size() == 36)
	assert(hello.decode_u32(12) == 1 and hello.decode_u32(16) == 2)
	assert(hello.decode_u32(20) == 175 and hello.decode_u32(24) == 12)
	assert(hello.decode_u32(28) == 240 and hello.decode_u32(32) == 60)
	assert(Protocol.header_error(hello).is_empty())
	var bad := hello.duplicate()
	bad.encode_u16(4, 99)
	assert(not Protocol.header_error(bad).is_empty())
	bad = hello.duplicate()
	bad.encode_u16(6, 99)
	assert(not Protocol.header_error(bad).is_empty())
	var actions := PackedByteArray()
	actions.resize(2 * 12 * 4)
	assert(Protocol.decode_actions(actions, 2, 12).size() == 2)
	assert(Protocol.decode_actions(actions.slice(4), 2, 12).is_empty())
	actions.encode_float(0, NAN)
	assert(Protocol.decode_actions(actions, 2, 12).is_empty())
	actions.encode_float(0, 1.1)
	assert(Protocol.decode_actions(actions, 2, 12).is_empty())
	actions.encode_float(0, 0.5)
	var initial := manager.get_observations()
	var initial_transforms: Array = []
	for arena in manager.arenas:
		for body in arena.ragdoll.bone_sim.get_children():
			if body is PhysicalBone3D:
				initial_transforms.append(body.global_transform)
	manager.begin_policy_step(Protocol.decode_actions(actions, 2, 12))
	await manager.policy_step_completed
	var result := Protocol.step_result(manager.last_step_result, 175)
	assert(result.size() == 2 * (175 * 8 + 7))
	manager.episode_count = 7
	manager.failed_episode_count = 3
	manager.timed_out_episode_count = 4
	manager.total_episode_duration = 12.0
	manager.total_episode_reward = 42.0
	var reset := manager.reset_all()
	assert(Protocol.observations(reset).size() == 2 * 175 * 4)
	assert(manager.episode_count == 7 and manager.failed_episode_count == 3)
	assert(manager.timed_out_episode_count == 4 and manager.total_episode_duration == 12.0)
	assert(manager.total_episode_reward == 42.0)
	for i in 2:
		assert(manager._episode_rewards[i] == 0.0)
		assert(manager.arenas[i].episode.elapsed_time == 0.0)
		assert(reset[i] == initial[i])
	var body_index := 0
	for arena in manager.arenas:
		for body in arena.ragdoll.bone_sim.get_children():
			if body is PhysicalBone3D:
				assert(body.global_transform == initial_transforms[body_index])
				assert(body.linear_velocity == Vector3.ZERO)
				assert(body.angular_velocity == Vector3.ZERO)
				body_index += 1
	manager.arenas[0].episode.minimum_pelvis_height = 100.0
	manager.arenas[1].episode.maximum_episode_duration = 0.001
	manager.begin_policy_step(Protocol.decode_actions(actions, 2, 12))
	await manager.policy_step_completed
	result = Protocol.step_result(manager.last_step_result, 175)
	var flags_offset := 2 * (175 * 4 + 4)
	assert(result.slice(flags_offset, flags_offset + 6) == PackedByteArray([1, 0, 0, 1, 1, 1]))
	assert(result.slice(flags_offset + 6) == Protocol.observations(manager.last_step_result.terminal_observations))
	await process_frame
	manager.free()
	print("TCP protocol tests passed")
	quit()
