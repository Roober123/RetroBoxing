class_name ActiveRagdoll
extends Node3D

## Empty enables every discovered joint; the root has no motor.
@export var motor_bones: Array[StringName] = []
@export var debug_targets := true
@export var isolate_gravity := true
## Profile vectors: response frequency (Hz), damping ratio, maximum torque (Nm).
@export var arms := Vector3(2.0, 1.0, 0.5)
@export var spine := Vector3(1.5, 1.0, 2.0)
@export var legs := Vector3(2.0, 1.0, 1.0)
@export var feet := Vector3(1.5, 1.0, 0.3)
@export var neck := Vector3(1.0, 0.2, 0.2)
var target_controller: RagdollTargetController
var neutral_pose: RagdollPose
var test_pose: RagdollPose
var boxing_pose: RagdollPose

@onready var bone_sim: PhysicalBoneSimulator3D = $PhysicalSkeleton/PhysicalBoneSimulator3D
@onready var skel: Skeleton3D = $PhysicalSkeleton
var pd_controller: ActiveRagdollPD3D

func _ready() -> void:
	RagdollCollisionJitterFix.new().apply(skel, bone_sim)
	pd_controller = ActiveRagdollPD3D.new()
	pd_controller.name = "PDController"
	add_child(pd_controller)
	if not pd_controller.initialize(skel, bone_sim):
		push_error("Could not initialize ragdoll PD joints.")
		return
	for bone_name in pd_controller.get_controlled_bones():
		pd_controller.set_joint_enabled(bone_name, motor_bones.is_empty() or bone_name in motor_bones)
	if not pd_controller.capture_reference_pose():
		return
	configure_profiles()
	neutral_pose = RagdollPose.neutral(pd_controller.get_joint_count())
	test_pose = make_pose(false)
	boxing_pose = make_pose(true)
	target_controller = RagdollTargetController.new()
	target_controller.initialize(pd_controller)
	target_controller.base_pose = test_pose
	add_child(target_controller)
	for bone in bone_sim.get_children():
		if bone is PhysicalBone3D:
			bone.gravity_scale = 0.0 if isolate_gravity else 1.0
	bone_sim.physical_bones_start_simulation()
	pd_controller.enabled = true
	if debug_targets:
		var debug := preload("res://Ragdoll/ragdoll_debug_targets.gd").new()
		debug.ragdoll = self
		add_child(debug)

func configure_profiles() -> void:
	profile([&"mixamorig_LeftShoulder", &"mixamorig_RightShoulder", &"mixamorig_LeftArm", &"mixamorig_RightArm", &"mixamorig_LeftForeArm", &"mixamorig_RightForeArm", &"mixamorig_LeftHand", &"mixamorig_RightHand"], arms)
	profile([&"mixamorig_Spine", &"mixamorig_Spine1", &"mixamorig_Spine2"], spine)
	profile([&"mixamorig_LeftUpLeg", &"mixamorig_RightUpLeg", &"mixamorig_LeftLeg", &"mixamorig_RightLeg"], legs)
	profile([&"mixamorig_LeftFoot", &"mixamorig_RightFoot"], feet)
	profile([&"mixamorig_Neck", &"mixamorig_Head"], neck)

func profile(bones: Array[StringName], values: Vector3) -> void:
	pd_controller.set_body_profile(bones, values.x, values.y, values.z)

func make_pose(boxing: bool) -> RagdollPose:
	var pose := RagdollPose.neutral(pd_controller.get_joint_count())
	# Body-local offsets; modest bends for actuator testing, no root correction.
	for i in pose.rotations.size():
		var bone := String(pd_controller.get_joint_name(i))
		var angle := 0.0
		if bone.ends_with("UpLeg"):
			angle = -15.0 if boxing else -10.0
		elif bone.ends_with("Leg"):
			angle = 25.0 if boxing else 15.0
		elif bone.ends_with("Foot"):
			angle = -10.0 if boxing else -5.0
		elif bone == "mixamorig_Spine":
			angle = 8.0 if boxing else 5.0
		pose.rotations[i] = Quaternion(Vector3.RIGHT, deg_to_rad(angle))
	# Aim arm segments in skeleton space so mirrored body frames produce a guard.
	var world_targets: Dictionary = {}
	for body in bone_sim.get_children():
		if body is PhysicalBone3D:
			world_targets[body.get_bone_id()] = body.global_basis.get_rotation_quaternion()
	for i in pose.rotations.size():
		var name := String(pd_controller.get_joint_name(i))
		var id := skel.find_bone(name)
		var parent_id := skel.get_bone_parent(id)
		var reference := pd_controller.get_joint_reference_rotation(i)
		var parent_world: Quaternion = world_targets[parent_id]
		if name.ends_with("Arm"):
			var side := 1.0 if "Left" in name else -1.0
			var forearm := name.ends_with("ForeArm")
			var next_name := name.replace("ForeArm", "Hand") if forearm else name.replace("Arm", "ForeArm")
			var segment := skel.get_bone_global_pose(skel.find_bone(next_name)).origin - skel.get_bone_global_pose(id).origin
			var direction: Vector3
			if boxing:
				direction = Vector3(-side * 0.1, 0.9, -0.3) if forearm else Vector3(side * 0.25, -0.75, -0.6 if side > 0 else -0.45)
			else:
				direction = Vector3(side * 0.65, -0.15, -0.65) if forearm else Vector3(side * 0.8, -0.35, -0.3)
			var swing := Quaternion((skel.global_basis * segment).normalized(), (skel.global_basis * direction).normalized())
			var desired_world: Quaternion = swing * world_targets[id]
			pose.rotations[i] = (reference.inverse() * parent_world.inverse() * desired_world).normalized()
		world_targets[id] = (parent_world * reference * pose.rotations[i]).normalized()
	return pose
