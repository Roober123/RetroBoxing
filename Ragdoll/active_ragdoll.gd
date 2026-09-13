class_name ActiveRagdoll
extends Node3D

## Empty enables every discovered joint; the root has no motor.
@export var motor_bones: Array[StringName] = []
## Profile vectors: response frequency (Hz), damping ratio, maximum torque (Nm).
@export var arms := Vector3(2.0, 1.0, 0.5)
@export var spine := Vector3(1.5, 1.0, 2.0)
@export var legs := Vector3(2.0, 1.0, 1.0)
@export var feet := Vector3(1.5, 1.0, 0.3)
@export var neck := Vector3(1.0, 0.2, 0.2)
var target_controller: RagdollTargetController
var neutral_pose: RagdollPose

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
	target_controller = RagdollTargetController.new()
	target_controller.initialize(pd_controller)
	add_child(target_controller)
	bone_sim.physical_bones_start_simulation()
	pd_controller.enabled = true

func configure_profiles() -> void:
	profile([&"mixamorig_LeftShoulder", &"mixamorig_RightShoulder", &"mixamorig_LeftArm", &"mixamorig_RightArm", &"mixamorig_LeftForeArm", &"mixamorig_RightForeArm", &"mixamorig_LeftHand", &"mixamorig_RightHand"], arms)
	profile([&"mixamorig_Spine", &"mixamorig_Spine1", &"mixamorig_Spine2"], spine)
	profile([&"mixamorig_LeftUpLeg", &"mixamorig_RightUpLeg", &"mixamorig_LeftLeg", &"mixamorig_RightLeg"], legs)
	profile([&"mixamorig_LeftFoot", &"mixamorig_RightFoot"], feet)
	profile([&"mixamorig_Neck", &"mixamorig_Head"], neck)

func profile(bones: Array[StringName], values: Vector3) -> void:
	pd_controller.set_body_profile(bones, values.x, values.y, values.z)
