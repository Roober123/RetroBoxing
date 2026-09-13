extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var ragdoll: ActiveRagdoll = load("res://Ragdoll/active_ragdoll.tscn").instantiate()
	root.add_child(ragdoll)
	var pd := ragdoll.pd_controller
	var name := &"mixamorig_LeftForeArm"
	var original := pd.get_joint_parameters(name)
	print("The following three rejected profile errors are expected:")
	assert(not pd.set_body_profile([name, &"missing_bone"], 3.0, 1.0, 0.5))
	assert(pd.get_joint_parameters(name) == original)
	assert(not pd.set_body_profile([name], -1.0, 1.0, 0.5))
	assert(not pd.set_body_profile([name], INF, 1.0, 0.5))
	assert(pd.get_joint_parameters(name) == original)
	assert(pd.set_body_profile([], 2.0, 1.0, 0.5))
	# Equivalent quaternion signs must not cause a long-path target excursion.
	var targets := ragdoll.target_controller
	targets.base_pose = RagdollPose.neutral(pd.get_joint_count())
	targets.base_pose.rotations[0] = -Quaternion.IDENTITY
	targets._physics_process(1.0 / 120.0)
	assert(targets.current.rotations[0].angle_to(Quaternion.IDENTITY) < 0.001)
	ragdoll.free()
	print("PD profile API tests passed")
	quit()
