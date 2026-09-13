extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	# Real project skeleton: discovery, deterministic ordering, setup and finite simulation.
	var ragdoll: ActiveRagdoll = load("res://Ragdoll/active_ragdoll.tscn").instantiate()
	root.add_child(ragdoll)
	var pd := ragdoll.pd_controller
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
