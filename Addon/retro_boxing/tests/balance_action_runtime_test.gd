extends SceneTree
## Optional -- --capture writes a rendered contact sheet to .godot/balance-actions.png.
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var environment: BalanceEnvironment = load("res://test.tscn").instantiate()
	root.add_child(environment)
	var controller := environment.balance_controller
	var ragdoll: ActiveRagdoll = environment.get_node("ActiveRagdoll")
	var bodies: Dictionary = {}
	for body in ragdoll.bone_sim.get_children():
		if body is PhysicalBone3D:
			bodies[body.get_bone_id()] = body
			body.gravity_scale = 0.0
	# Keep the real collisions enabled, matching the manual verification mode.
	var capture := "--capture" in OS.get_cmdline_user_args()
	var sheet: Image
	var label: Label
	if capture:
		root.size = Vector2i(480, 480)
		sheet = Image.create(480 * 4, 480 * 3, false, Image.FORMAT_RGBA8)
		label = Label.new()
		label.position = Vector2(12, 12)
		root.add_child(label)
		var camera: Camera3D = environment.get_node("Camera3D")
		camera.position = Vector3(2.1, 1.4, 2.1)
		camera.look_at(Vector3(0, 0.95, 0))
	for action_index in 12:
		environment.reset()
		var action := controller.get_neutral_action()
		action[action_index] = 1.0
		controller.apply_action(action)
		var joint_index := -1
		var target := Quaternion.IDENTITY
		for i in ragdoll.pd_controller.get_joint_count():
			var rotation := ragdoll.target_controller.control_offset.rotations[i]
			if not rotation.is_equal_approx(Quaternion.IDENTITY):
				joint_index = i
				target = rotation
		assert(joint_index >= 0)
		for tick in 480:
			await physics_frame
		var bone := ragdoll.pd_controller.get_joint_name(joint_index)
		var config: Dictionary = controller.axis_resolver.joints[bone]
		var child: PhysicalBone3D = bodies[config.bone_id]
		var parent: PhysicalBone3D = bodies[config.parent]
		var relative := parent.global_basis.orthonormalized().get_rotation_quaternion().inverse() * child.global_basis.orthonormalized().get_rotation_quaternion()
		var reference := ragdoll.pd_controller.get_joint_reference_rotation(joint_index)
		var error := relative.angle_to(reference * target)
		print(controller.ACTION_NAMES[action_index], " tracking error: ", rad_to_deg(error))
		assert(error < target.get_angle() * 0.8, "Action did not meaningfully approach its target")
		if capture:
			label.text = controller.ACTION_NAMES[action_index] + " = +1"
			await process_frame
			await RenderingServer.frame_post_draw
			var screenshot := root.get_texture().get_image()
			sheet.blit_rect(screenshot, Rect2i(0, 0, 480, 480), Vector2i((action_index % 4) * 480, (action_index / 4) * 480))
	if capture:
		sheet.save_png("res://.godot/balance-actions.png")
	# Compare identical starts in normal gravity, including ground contact.
	for body in bodies.values():
		body.gravity_scale = 1.0
	var neutral_rotations: Array[Quaternion] = []
	for trial in 6:
		environment.reset()
		var action := controller.get_neutral_action()
		if trial > 0:
			for index in [[6, 8], [0, 2], [1, 3], [4, 5], [10]][trial - 1]:
				action[index] = 1.0
		controller.apply_action(action)
		for tick in 120:
			await physics_frame
		var largest_change := 0.0
		var i := 0
		for body in bodies.values():
			var rotation: Quaternion = body.global_basis.orthonormalized().get_rotation_quaternion()
			assert(rotation.is_finite())
			if trial == 0:
				neutral_rotations.append(rotation)
			else:
				largest_change = maxf(largest_change, rotation.angle_to(neutral_rotations[i]))
			i += 1
		if trial > 0:
			print("Gravity response ", trial, ": ", rad_to_deg(largest_change), " degrees")
			assert(largest_change > deg_to_rad(1.0))
	print("Balance action runtime tests passed")
	quit()
