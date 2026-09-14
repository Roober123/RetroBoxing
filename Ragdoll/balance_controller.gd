class_name BalanceController
extends Node

const ACTION_NAMES := [
	"left_hip_pitch", "left_hip_roll", "right_hip_pitch", "right_hip_roll",
	"left_knee_flexion", "right_knee_flexion",
	"left_ankle_pitch", "left_ankle_roll", "right_ankle_pitch", "right_ankle_roll",
	"spine_pitch", "spine_roll",
]

@export var ragdoll_path: NodePath = ^"../ActiveRagdoll"
@export_range(0.0, 90.0, 0.5) var hip_limit_degrees := 20.0
@export_range(0.0, 90.0, 0.5) var knee_limit_degrees := 35.0
@export_range(0.0, 90.0, 0.5) var ankle_limit_degrees := 15.0
@export_range(0.0, 90.0, 0.5) var spine_limit_degrees := 10.0

@onready var ragdoll: ActiveRagdoll = get_node(ragdoll_path)
var action := PackedFloat32Array()
var _joint_indices: Dictionary = {}
var axis_resolver := BalanceJointAxisResolver.new()
var axes_ready := false

func _ready() -> void:
	for i in ragdoll.pd_controller.get_joint_count():
		_joint_indices[ragdoll.pd_controller.get_joint_name(i)] = i
	axes_ready = axis_resolver.resolve(ragdoll.skel, ragdoll.bone_sim)
	for bone in axis_resolver.joints:
		if not _joint_indices.has(bone):
			push_error("Balance joint has no PD motor: %s" % bone)
			axes_ready = false
	action.resize(ACTION_NAMES.size())
	reset_action()

func get_action_size() -> int:
	return ACTION_NAMES.size()

func get_action_names() -> PackedStringArray:
	return PackedStringArray(ACTION_NAMES)

func apply_action(values) -> void:
	if not axes_ready:
		return
	if values == null or values.size() != ACTION_NAMES.size():
		push_error("Balance action must contain %d values." % ACTION_NAMES.size())
		return
	for value in values:
		if not is_finite(float(value)):
			push_error("Balance action values must be finite.")
			return
	for i in ACTION_NAMES.size():
		action[i] = clampf(float(values[i]), -1.0, 1.0)
	var pose := RagdollPose.neutral(ragdoll.pd_controller.get_joint_count())
	_set_two_axis(pose, &"mixamorig_LeftUpLeg", action[0], action[1], hip_limit_degrees)
	_set_two_axis(pose, &"mixamorig_RightUpLeg", action[2], action[3], hip_limit_degrees)
	_set_one_axis(pose, &"mixamorig_LeftLeg", action[4], knee_limit_degrees)
	_set_one_axis(pose, &"mixamorig_RightLeg", action[5], knee_limit_degrees)
	_set_two_axis(pose, &"mixamorig_LeftFoot", action[6], action[7], ankle_limit_degrees)
	_set_two_axis(pose, &"mixamorig_RightFoot", action[8], action[9], ankle_limit_degrees)
	_set_two_axis(pose, &"mixamorig_Spine", action[10], action[11], spine_limit_degrees)
	ragdoll.target_controller.control_offset = pose

func reset_action() -> void:
	action = get_neutral_action()
	if is_instance_valid(ragdoll) and is_instance_valid(ragdoll.target_controller):
		ragdoll.target_controller.control_offset = RagdollPose.neutral(ragdoll.pd_controller.get_joint_count())

func _set_one_axis(pose: RagdollPose, bone: StringName, value: float, limit_degrees: float) -> void:
	var index: int = _joint_indices.get(bone, -1)
	if index >= 0:
		limit_degrees = minf(limit_degrees, axis_resolver.joints[bone].limit_degrees)
		pose.rotations[index] = Quaternion(axis_resolver.joints[bone].axes[0], deg_to_rad(limit_degrees) * (value + 1.0) * 0.5 * axis_resolver.joints[bone].signs[0])

func _set_two_axis(pose: RagdollPose, bone: StringName, pitch: float, roll: float, limit_degrees: float) -> void:
	var index: int = _joint_indices.get(bone, -1)
	if index >= 0:
		limit_degrees = minf(limit_degrees, axis_resolver.joints[bone].limit_degrees)
		var pitch_rotation := Quaternion(axis_resolver.joints[bone].axes[0], deg_to_rad(limit_degrees) * pitch * axis_resolver.joints[bone].signs[0])
		var roll_rotation := Quaternion(axis_resolver.joints[bone].axes[1], deg_to_rad(limit_degrees) * roll * axis_resolver.joints[bone].signs[1])
		pose.rotations[index] = (pitch_rotation * roll_rotation).normalized()

func get_neutral_action() -> PackedFloat32Array:
	var neutral := PackedFloat32Array()
	neutral.resize(ACTION_NAMES.size())
	neutral[4] = -1.0
	neutral[5] = -1.0
	return neutral
