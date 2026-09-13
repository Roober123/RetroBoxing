extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	# Real project skeleton: discovery, deterministic ordering, setup and finite simulation.
	var ragdoll: ActiveRagdoll = load("res://Ragdoll/active_ragdoll.tscn").instantiate()
	root.add_child(ragdoll)
	var pd := ragdoll.pd_controller
	# Preserve the original isolated elbow regression below.
	ragdoll.target_controller.set_physics_process(false)
	for name in pd.get_controlled_bones():
		pd.set_joint_enabled(name, name == "mixamorig_LeftForeArm")
		pd.set_joint_parameters(name, 2.0, 0.08, 0.5)
	var untouched := pd.get_joint_parameters(&"mixamorig_RightForeArm")
	assert(pd.set_body_profile([&"mixamorig_LeftForeArm"], 2.0, 1.0, 0.4))
	var gains := pd.get_joint_parameters(&"mixamorig_LeftForeArm")
	assert(pd.set_body_profile([&"mixamorig_LeftForeArm"], 4.0, 2.0, 0.2))
	var faster := pd.get_joint_parameters(&"mixamorig_LeftForeArm")
	assert(is_equal_approx(faster.x, gains.x * 4.0))
	assert(is_equal_approx(faster.y, gains.y * 4.0))
	assert(is_equal_approx(faster.z, 0.2))
	assert(pd.get_joint_parameters(&"mixamorig_RightForeArm") == untouched)
	pd.set_joint_parameters(&"mixamorig_LeftForeArm", 2.0, 0.08, 0.5)
	var blended := ragdoll.neutral_pose.blended(ragdoll.test_pose, 0.5)
	assert(blended.is_valid(pd.get_joint_count()))
	for i in pd.get_joint_count():
		assert(blended.composed(ragdoll.neutral_pose).rotations[i].is_equal_approx(blended.rotations[i]))

	assert(pd.enabled)
	assert(pd.get_joint_count() == 19)
	assert(not "mixamorig_Hips" in pd.get_controlled_bones())
	var last_id := -1
	for index in pd.get_joint_count():
		var bone_id := ragdoll.skel.find_bone(pd.get_joint_name(index))
		assert(bone_id > last_id)
		last_id = bone_id
		print(pd.get_joint_name(index), " -> ", ragdoll.skel.get_bone_name(ragdoll.skel.get_bone_parent(bone_id)))
	for bone in ragdoll.bone_sim.get_children():
		if bone is PhysicalBone3D:
			bone.gravity_scale = 0
			bone.collision_layer = 0
			bone.collision_mask = 0
	var child: PhysicalBone3D
	var parent: PhysicalBone3D
	for bone in ragdoll.bone_sim.get_children():
		if bone is PhysicalBone3D:
			if bone.get_bone_id() == ragdoll.skel.find_bone("mixamorig_LeftForeArm"):
				child = bone
			if bone.get_bone_id() == ragdoll.skel.find_bone("mixamorig_LeftArm"):
				parent = bone
	var reference := parent.global_basis.get_rotation_quaternion().inverse() * child.global_basis.get_rotation_quaternion()
	var target := Quaternion(Vector3.RIGHT, deg_to_rad(30.0))
	pd.set_joint_target(&"mixamorig_LeftForeArm", target)
	for tick in 240:
		await physics_frame
	var relative := parent.global_basis.get_rotation_quaternion().inverse() * child.global_basis.get_rotation_quaternion()
	var error := relative.angle_to(reference * target)
	print("Elbow target error after 2 seconds: ", rad_to_deg(error), " degrees")
	assert(error < deg_to_rad(10.0), "Elbow did not approach its target")
	# A physical disturbance should displace the joint, then the motor recovers.
	PhysicsServer3D.body_apply_torque_impulse(child.get_rid(), parent.global_basis * Vector3(0.1, 0, 0))
	for tick in 12:
		await physics_frame
	relative = parent.global_basis.get_rotation_quaternion().inverse() * child.global_basis.get_rotation_quaternion()
	var disturbed_error := relative.angle_to(reference * target)
	for tick in 360:
		await physics_frame
	relative = parent.global_basis.get_rotation_quaternion().inverse() * child.global_basis.get_rotation_quaternion()
	var recovered_error := relative.angle_to(reference * target)
	print("Disturbance/recovery error: ", rad_to_deg(disturbed_error), " / ", rad_to_deg(recovered_error))
	assert(recovered_error < disturbed_error)
	pd.reset_all_targets()
	for tick in 240:
		await physics_frame
	relative = parent.global_basis.get_rotation_quaternion().inverse() * child.global_basis.get_rotation_quaternion()
	assert(relative.angle_to(reference) < deg_to_rad(10.0))
	# Full body profiles and moving targets in gravity-free isolation.
	ragdoll.configure_profiles()
	for name in pd.get_controlled_bones():
		pd.set_joint_enabled(name, true)
	ragdoll.target_controller.set_physics_process(true)
	for tick in 480:
		await physics_frame
	var worst := 0.0
	for i in pd.get_joint_count():
		var physical: PhysicalBone3D
		var physical_parent: PhysicalBone3D
		var id := ragdoll.skel.find_bone(pd.get_joint_name(i))
		for bone in ragdoll.bone_sim.get_children():
			if bone is PhysicalBone3D:
				if bone.get_bone_id() == id:
					physical = bone
				if bone.get_bone_id() == ragdoll.skel.get_bone_parent(id):
					physical_parent = bone
		var actual := physical_parent.global_basis.get_rotation_quaternion().inverse() * physical.global_basis.get_rotation_quaternion()
		var desired := pd.get_joint_reference_rotation(i) * ragdoll.test_pose.rotations[i]
		var joint_error := rad_to_deg(actual.angle_to(desired))
		print("Full-body error ", pd.get_joint_name(i), ": ", joint_error)
		worst = maxf(worst, joint_error)
		assert(physical.angular_velocity.is_finite())
	assert(worst < 15.0, "Full-body test pose failed to converge")
	# Region disturbances must displace and recover with all motors active.
	for name in ["mixamorig_LeftForeArm", "mixamorig_LeftArm", "mixamorig_LeftUpLeg", "mixamorig_Spine"]:
		var body := find_body(ragdoll, name)
		var before := joint_error(ragdoll, name, ragdoll.test_pose)
		PhysicsServer3D.body_apply_torque_impulse(body.get_rid(), Vector3.RIGHT * (0.5 if name in ["mixamorig_LeftUpLeg", "mixamorig_Spine"] else 0.1))
		var peak := before
		for tick in 30:
			await physics_frame
			peak = maxf(peak, joint_error(ragdoll, name, ragdoll.test_pose))
		for tick in 330:
			await physics_frame
		var recovered := joint_error(ragdoll, name, ragdoll.test_pose)
		print("Region recovery ", name, ": ", peak, " -> ", recovered)
		assert(peak > before + 0.1, "Impulse did not displace joint")
		assert(recovered < peak, "Joint did not recover")
	# Boxing is a full pose transition, with the hips still free.
	ragdoll.target_controller.base_pose = ragdoll.boxing_pose
	for tick in 600:
		await physics_frame
	for name in pd.get_controlled_bones():
		var stance_error := joint_error(ragdoll, name, ragdoll.boxing_pose)
		print("Boxing error ", name, ": ", stance_error)
		assert(stance_error < 15.0, "Boxing pose failed to converge")
	# Compare identical transitions with and without target velocity feed-forward.
	var tracking_errors: Array[float] = []
	var movement := ragdoll.test_pose.composed(ragdoll.neutral_pose)
	var elbow_index := Array(pd.get_controlled_bones()).find("mixamorig_LeftForeArm")
	movement.rotations[elbow_index] = (movement.rotations[elbow_index] * Quaternion(Vector3.RIGHT, deg_to_rad(30.0))).normalized()
	for feed_forward in [false, true]:
		ragdoll.target_controller.use_target_velocity = feed_forward
		ragdoll.target_controller.base_pose = ragdoll.test_pose
		for tick in 600:
			await physics_frame
		ragdoll.target_controller.base_pose = movement
		var total_error := 0.0
		for tick in 120:
			await physics_frame
			total_error += joint_error(ragdoll, "mixamorig_LeftForeArm", ragdoll.target_controller.current)
		tracking_errors.append(total_error / 120.0)
	print("Moving-target mean error, zero/calculated velocity: ", tracking_errors)
	assert(tracking_errors[1] < tracking_errors[0], "Velocity feed-forward did not improve tracking")
	# Restore gravity and collisions for the all-motor smoke test.
	for bone in ragdoll.bone_sim.get_children():
		if bone is PhysicalBone3D:
			bone.gravity_scale = 1
			bone.collision_layer = 1
			bone.collision_mask = 1
	# Smoke-test all motors only after the single-joint checks.
	for bone_name in pd.get_controlled_bones():
		pd.set_joint_enabled(bone_name, true)
	for tick in 240:
		await physics_frame
	for bone in ragdoll.bone_sim.get_children():
		if bone is PhysicalBone3D:
			assert(bone.global_transform.is_finite())
			assert(bone.angular_velocity.is_finite())
	# Cached object IDs must tolerate bodies being freed while the controller lives.
	child.free()
	for tick in 3:
		await physics_frame
	ragdoll.free()
	print("PD runtime tests passed")
	quit()

func find_body(ragdoll: ActiveRagdoll, name: String) -> PhysicalBone3D:
	for bone in ragdoll.bone_sim.get_children():
		if bone is PhysicalBone3D and bone.bone_name == name:
			return bone
	return null

func joint_error(ragdoll: ActiveRagdoll, name: String, pose: RagdollPose) -> float:
	var body := find_body(ragdoll, name)
	var parent_name := ragdoll.skel.get_bone_name(ragdoll.skel.get_bone_parent(body.get_bone_id()))
	var parent := find_body(ragdoll, parent_name)
	var pd := ragdoll.pd_controller
	var index := Array(pd.get_controlled_bones()).find(name)
	var relative := parent.global_basis.get_rotation_quaternion().inverse() * body.global_basis.get_rotation_quaternion()
	return rad_to_deg(relative.angle_to(pd.get_joint_reference_rotation(index) * pose.rotations[index]))
