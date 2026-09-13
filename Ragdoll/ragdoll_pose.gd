class_name RagdollPose
extends Resource
## Entries use get_joint_name(index) ordering from the same skeleton.
@export var rotations: Array[Quaternion] = []

func apply_to(controller: ActiveRagdollPD3D) -> void:
	if rotations.size() != controller.get_joint_count():
		push_error("Pose joint count does not match the controller.")
		return
	for rotation in rotations:
		if not rotation.is_finite() or rotation.length_squared() < 1e-12:
			push_error("Pose contains an invalid quaternion.")
			return
	for index in rotations.size():
		controller.set_joint_target_by_index(index, rotations[index])
		controller.set_joint_target_angular_velocity(controller.get_joint_name(index), Vector3.ZERO)

static func neutral(count: int) -> RagdollPose:
	var pose := RagdollPose.new()
	pose.rotations.resize(count)
	pose.rotations.fill(Quaternion.IDENTITY)
	return pose

func is_valid(count: int) -> bool:
	if rotations.size() != count:
		return false
	for q in rotations:
		if not q.is_finite() or q.length_squared() < 1e-12:
			return false
	return true

func blended(other: RagdollPose, weight: float) -> RagdollPose:
	assert(is_valid(rotations.size()) and other.is_valid(rotations.size()))
	var pose := neutral(rotations.size())
	for i in rotations.size():
		pose.rotations[i] = rotations[i].normalized().slerp(other.rotations[i].normalized(), clampf(weight, 0, 1))
	return pose

func composed(offset: RagdollPose) -> RagdollPose:
	assert(is_valid(rotations.size()) and offset.is_valid(rotations.size()))
	var pose := neutral(rotations.size())
	for i in rotations.size():
		pose.rotations[i] = (rotations[i].normalized() * offset.rotations[i].normalized()).normalized()
	return pose
