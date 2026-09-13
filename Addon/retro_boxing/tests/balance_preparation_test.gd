extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	assert(Engine.physics_ticks_per_second == 240)
	var environment: BalanceEnvironment = load("res://test.tscn").instantiate()
	root.add_child(environment)
	var ragdoll: ActiveRagdoll = environment.get_node("ActiveRagdoll")
	assert(ragdoll.pd_controller.get_joint_count() == 19)
	assert(not &"mixamorig_Hips" in ragdoll.pd_controller.get_controlled_bones())
	for body in ragdoll.bone_sim.get_children():
		if body is PhysicalBone3D:
			assert(is_equal_approx(body.gravity_scale, 1.0))

	var controller := environment.balance_controller
	assert(controller.get_action_size() == 12)
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
	assert(not observation.is_empty())
	for value in observation:
		assert(is_finite(value))

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
		for value in controller.action:
			assert(value == 0.0)

	var pelvis: PhysicalBone3D = environment.episode._pelvis
	environment.episode.minimum_pelvis_height = pelvis.global_position.y + 1.0
	assert(environment.is_terminal())
	root.remove_child(environment)
	environment.free()
	print("Balance preparation tests passed")
	quit()
