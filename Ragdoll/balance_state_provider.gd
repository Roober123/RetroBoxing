class_name BalanceStateProvider
extends Node

const STANDING_HEIGHT := 1.0
const LINEAR_VELOCITY_SCALE := 5.0
const ANGULAR_VELOCITY_SCALE := 10.0
const CHARACTER_SIZE_SCALE := 1.0
const NORMALIZED_LIMIT := 5.0

@export var ragdoll_path: NodePath = ^"../ActiveRagdoll"
@onready var ragdoll: ActiveRagdoll = get_node(ragdoll_path)

var _bodies_by_id: Dictionary = {}
var _pelvis: PhysicalBone3D
var _left_foot: PhysicalBone3D
var _right_foot: PhysicalBone3D
var _body_rids: Array[RID] = []

func _ready() -> void:
	for child in ragdoll.bone_sim.get_children():
		if child is PhysicalBone3D:
			var body := child as PhysicalBone3D
			_bodies_by_id[body.get_bone_id()] = body
			_body_rids.append(body.get_rid())
	_pelvis = _body_for_name(&"mixamorig_Hips")
	_left_foot = _body_for_name(&"mixamorig_LeftFoot")
	_right_foot = _body_for_name(&"mixamorig_RightFoot")

func get_state() -> Dictionary:
	if not _pelvis:
		return {}
	var pelvis_inverse := _pelvis.global_basis.orthonormalized().inverse()
	var joint_rotations: Array[Quaternion] = []
	var joint_angular_velocities: Array[Vector3] = []
	for i in ragdoll.pd_controller.get_joint_count():
		var bone_id := ragdoll.skel.find_bone(ragdoll.pd_controller.get_joint_name(i))
		var child: PhysicalBone3D = _bodies_by_id.get(bone_id)
		var parent: PhysicalBone3D = _bodies_by_id.get(ragdoll.skel.get_bone_parent(bone_id))
		var parent_basis := parent.global_basis.orthonormalized()
		joint_rotations.append((parent_basis.get_rotation_quaternion().inverse() * child.global_basis.orthonormalized().get_rotation_quaternion()).normalized())
		joint_angular_velocities.append(parent_basis.inverse() * (child.angular_velocity - parent.angular_velocity))

	var com_position := Vector3.ZERO
	var com_velocity := Vector3.ZERO
	var total_mass := 0.0
	for body_value in _bodies_by_id.values():
		var body := body_value as PhysicalBone3D
		com_position += body.global_position * body.mass
		com_velocity += body.linear_velocity * body.mass
		total_mass += body.mass
	if total_mass > 0.0:
		com_position /= total_mass
		com_velocity /= total_mass
	var support_center := (_left_foot.global_position + _right_foot.global_position) * 0.5
	var horizontal_offset := com_position - support_center
	horizontal_offset.y = 0.0
	return {
		"pelvis_orientation": _pelvis.global_basis.orthonormalized().get_rotation_quaternion(),
		"pelvis_up": _pelvis.global_basis.orthonormalized() * Vector3.UP,
		"pelvis_forward": _pelvis.global_basis.orthonormalized() * Vector3.FORWARD,
		"pelvis_angular_velocity": pelvis_inverse * _pelvis.angular_velocity,
		"pelvis_linear_velocity": pelvis_inverse * _pelvis.linear_velocity,
		"pelvis_height": _pelvis.global_position.y,
		"joint_rotations": joint_rotations,
		"joint_angular_velocities": joint_angular_velocities,
		"left_foot_position": _pelvis.to_local(_left_foot.global_position),
		"right_foot_position": _pelvis.to_local(_right_foot.global_position),
		"left_foot_contact": _foot_has_contact(_left_foot),
		"right_foot_contact": _foot_has_contact(_right_foot),
		"com_position": _pelvis.to_local(com_position),
		"com_velocity": pelvis_inverse * com_velocity,
		"support_center": _pelvis.to_local(support_center),
		"horizontal_com_offset": pelvis_inverse * horizontal_offset,
	}

func get_observation() -> PackedFloat32Array:
	var state := get_state()
	var observation := PackedFloat32Array()
	if state.is_empty():
		return observation
	_append_vector(observation, state.pelvis_up)
	_append_vector(observation, state.pelvis_forward)
	_append_vector(observation, _normalized_vector(state.pelvis_angular_velocity, ANGULAR_VELOCITY_SCALE))
	_append_vector(observation, _normalized_vector(state.pelvis_linear_velocity, LINEAR_VELOCITY_SCALE))
	observation.append(clampf(state.pelvis_height / STANDING_HEIGHT, -NORMALIZED_LIMIT, NORMALIZED_LIMIT))
	for i in state.joint_rotations.size():
		var rotation: Quaternion = state.joint_rotations[i]
		if rotation.w < 0.0:
			rotation = -rotation
		observation.append_array(PackedFloat32Array([rotation.x, rotation.y, rotation.z, rotation.w]))
		_append_vector(observation, _normalized_vector(state.joint_angular_velocities[i], ANGULAR_VELOCITY_SCALE))
	_append_vector(observation, _normalized_vector(state.left_foot_position, CHARACTER_SIZE_SCALE))
	_append_vector(observation, _normalized_vector(state.right_foot_position, CHARACTER_SIZE_SCALE))
	observation.append(1.0 if state.left_foot_contact else 0.0)
	observation.append(1.0 if state.right_foot_contact else 0.0)
	_append_vector(observation, _normalized_vector(state.com_position, CHARACTER_SIZE_SCALE))
	_append_vector(observation, _normalized_vector(state.com_velocity, LINEAR_VELOCITY_SCALE))
	_append_vector(observation, _normalized_vector(state.horizontal_com_offset, CHARACTER_SIZE_SCALE))
	assert(observation.size() == get_observation_size())
	return observation

func get_observation_size() -> int:
	return 30 + ragdoll.pd_controller.get_joint_count() * 7

func _normalized_vector(value: Vector3, scale: float) -> Vector3:
	var normalized := value / scale
	return Vector3(clampf(normalized.x, -NORMALIZED_LIMIT, NORMALIZED_LIMIT), clampf(normalized.y, -NORMALIZED_LIMIT, NORMALIZED_LIMIT), clampf(normalized.z, -NORMALIZED_LIMIT, NORMALIZED_LIMIT))

func _body_for_name(bone_name: StringName) -> PhysicalBone3D:
	return _bodies_by_id.get(ragdoll.skel.find_bone(bone_name))

func _foot_has_contact(foot: PhysicalBone3D) -> bool:
	var query := PhysicsRayQueryParameters3D.create(foot.global_position + Vector3.UP * 0.05, foot.global_position + Vector3.DOWN * 0.2)
	query.exclude = _body_rids
	return not foot.get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _append_vector(values: PackedFloat32Array, vector: Vector3) -> void:
	values.append_array(PackedFloat32Array([vector.x, vector.y, vector.z]))
