extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	assert(Engine.physics_ticks_per_second == 240)
	var environment: BalanceEnvironment = load("res://balance_training_arena.tscn").instantiate()
	root.add_child(environment)
	var ragdoll: ActiveRagdoll = environment.get_node("ActiveRagdoll")
	assert(ragdoll.pd_controller.get_joint_count() == 19)
	assert(not &"mixamorig_Hips" in ragdoll.pd_controller.get_controlled_bones())
	for body in ragdoll.bone_sim.get_children():
		if body is PhysicalBone3D:
			assert(is_equal_approx(body.gravity_scale, 1.0))

	var controller := environment.balance_controller
	assert(controller.get_action_size() == 12)
	assert(controller.axes_ready)
	assert(controller.axis_resolver.joints.size() == 7)
	for bone in controller.axis_resolver.joints:
		var joint: Dictionary = controller.axis_resolver.joints[bone]
		for axis in joint.axes:
			assert(is_equal_approx(axis.length(), 1.0))
		for direction in joint.signs:
			assert(absf(direction) == 1.0)
		if joint.axes.size() == 2:
			assert(absf(joint.axes[0].dot(joint.axes[1])) < 0.1)
	# Permuting the physical joint frame must permute candidate selection,
	# while preserving the anatomical target in reference-body space.
	var offsets: Dictionary = {}
	for body in ragdoll.bone_sim.get_children():
		if body is PhysicalBone3D and controller.axis_resolver.joints.has(body.bone_name):
			offsets[body] = body.joint_offset
			var changed: Transform3D = body.joint_offset
			changed.basis = changed.basis * Basis(Vector3.ONE.normalized(), TAU / 3.0)
			body.joint_offset = changed
	var permuted := BalanceJointAxisResolver.new()
	assert(permuted.resolve(ragdoll.skel, ragdoll.bone_sim))
	for bone in permuted.joints:
		var original: Dictionary = controller.axis_resolver.joints[bone]
		var changed: Dictionary = permuted.joints[bone]
		for i in original.axes.size():
			assert((original.axes[i] * original.signs[i]).dot(changed.axes[i] * changed.signs[i]) > 0.99)
	for body in offsets:
		body.joint_offset = offsets[body]
	# Neutral must mean the same thing through reset and through the action API.
	environment.apply_action(controller.get_neutral_action())
	for rotation in ragdoll.target_controller.control_offset.rotations:
		assert(rotation.is_equal_approx(Quaternion.IDENTITY))
	for knee in [4, 5]:
		var middle := controller.get_neutral_action()
		middle[knee] = 0.0
		environment.apply_action(middle)
		var index: int = controller._joint_indices[&"mixamorig_LeftLeg" if knee == 4 else &"mixamorig_RightLeg"]
		assert(is_equal_approx(ragdoll.target_controller.control_offset.rotations[index].get_angle(), deg_to_rad(17.5)))
	var action := PackedFloat32Array()
	action.resize(controller.get_action_size())
	action.fill(2.0)
	environment.apply_action(action)
	for value in controller.action:
		assert(value == 1.0)

	await physics_frame
	var state := environment.state_provider.get_state()
	assert(state.joint_rotations.size() == 19)
	assert(state.joint_angular_velocities.size() == 19)
	var observation := environment.get_observation()
	assert(observation.size() == environment.get_observation_size())
	assert(environment.get_observation_size() == 175)
	assert(environment.get_action_size() == 12)
	for value in observation:
		assert(is_finite(value))
	var upright_reward := environment.get_reward()
	assert(is_finite(upright_reward))
	var original_pelvis_transform := environment.episode._pelvis.global_transform
	environment.episode._pelvis.global_basis = Basis(Vector3.FORWARD, deg_to_rad(45.0)) * environment.episode._pelvis.global_basis
	var leaning_reward := environment.get_reward()
	assert(is_finite(leaning_reward) and leaning_reward < upright_reward)
	environment.episode._pelvis.global_transform = original_pelvis_transform

	var initial_transforms: Array[Transform3D] = []
	var bodies: Array[PhysicalBone3D] = []
	for body in ragdoll.bone_sim.get_children():
		if body is PhysicalBone3D:
			bodies.append(body)
			initial_transforms.append(environment.episode._initial_transforms[bodies.size() - 1])
	for repetition in 3:
		for tick in 8:
			await physics_frame
		environment.reset()
		for i in bodies.size():
			var transform: Transform3D = PhysicsServer3D.body_get_state(bodies[i].get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
			assert(transform.origin.distance_to(initial_transforms[i].origin) < 0.0001)
			assert(PhysicsServer3D.body_get_state(bodies[i].get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY).is_zero_approx())
			assert(PhysicsServer3D.body_get_state(bodies[i].get_rid(), PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY).is_zero_approx())
		assert(controller.action == controller.get_neutral_action())
		assert(environment.episode.elapsed_time == 0.0)
		assert(not environment.has_timed_out())
		for rotation in ragdoll.target_controller.current.rotations:
			assert(rotation.is_equal_approx(Quaternion.IDENTITY))
		for rotation in ragdoll.target_controller.control_offset.rotations:
			assert(rotation.is_equal_approx(Quaternion.IDENTITY))

	# Exercise timer with different physics deltas without waiting ten wall seconds.
	environment.episode.set_physics_process(false)
	for delta in [1.0 / 60.0, 1.0 / 240.0]:
		environment.reset()
		for tick in int(round(9.9 / delta)):
			environment.episode._physics_process(delta)
		assert(not environment.has_timed_out())
		for tick in int(round(0.1 / delta)):
			environment.episode._physics_process(delta)
		assert(environment.has_timed_out())
		assert(not environment.has_failed())
		assert(environment.is_terminal())
	environment.reset()
	var pelvis: PhysicalBone3D = environment.episode._pelvis
	environment.episode.minimum_pelvis_height = pelvis.global_position.y + 1.0
	assert(environment.is_terminal())
	assert(environment.has_failed())
	assert(not environment.has_timed_out())
	assert(environment.get_reward() == -1.0)
	# Missing required physical joints must fail without fallback axes.
	var missing: PhysicalBone3D = controller.axis_resolver._bodies["mixamorig_LeftLeg"]
	ragdoll.bone_sim.remove_child(missing)
	var invalid := BalanceJointAxisResolver.new()
	print("The following missing balance joint error is expected:")
	assert(not invalid.resolve(ragdoll.skel, ragdoll.bone_sim))
	assert(invalid.error.contains("LeftLeg"))
	assert(invalid.joints.is_empty())
	missing.free()
	root.remove_child(environment)
	environment.free()
	print("Balance preparation tests passed")
	quit()
