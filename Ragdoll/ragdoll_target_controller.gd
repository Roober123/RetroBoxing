class_name RagdollTargetController
extends Node
## All poses use the initialized PD controller's joint ordering.
var controller: ActiveRagdollPD3D
var base_pose: RagdollPose
var control_offset: RagdollPose
var smoothing_speed := 8.0
var use_target_velocity := true
var current: RagdollPose

func initialize(pd: ActiveRagdollPD3D) -> void:
	controller = pd
	base_pose = RagdollPose.neutral(pd.get_joint_count())
	control_offset = RagdollPose.neutral(pd.get_joint_count())
	current = RagdollPose.neutral(pd.get_joint_count())
	# Update targets before the PD motor runs this tick.
	process_physics_priority = -1

func reset_targets() -> void:
	if not is_instance_valid(controller):
		return
	base_pose = RagdollPose.neutral(controller.get_joint_count())
	control_offset = RagdollPose.neutral(controller.get_joint_count())
	current = RagdollPose.neutral(controller.get_joint_count())
	controller.reset_all_targets()

func _physics_process(delta: float) -> void:
	if not is_instance_valid(controller) or delta <= 0:
		return
	if not base_pose.is_valid(controller.get_joint_count()) or not control_offset.is_valid(controller.get_joint_count()):
		push_error("Target pose is invalid or has the wrong joint count.")
		return
	var desired := base_pose.composed(control_offset)
	var weight := 1.0 - exp(-maxf(smoothing_speed, 0.0) * delta)
	for i in current.rotations.size():
		var previous := current.rotations[i]
		var next := previous.slerp(desired.rotations[i], weight).normalized()
		var step := (next * previous.inverse()).normalized()
		if step.w < 0:
			step = -step
		var vector := Vector3(step.x, step.y, step.z)
		var velocity := Vector3.ZERO
		if use_target_velocity and vector.length() > 0.000001:
			velocity = vector.normalized() * (2.0 * atan2(vector.length(), step.w) / delta)
			# Offset derivatives are in reference-child axes; PD expects parent axes.
			velocity = controller.get_joint_reference_rotation(i) * velocity
		controller.set_joint_target_by_index(i, next)
		controller.set_joint_target_angular_velocity(controller.get_joint_name(i), velocity)
		current.rotations[i] = next
