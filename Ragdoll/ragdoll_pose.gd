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
