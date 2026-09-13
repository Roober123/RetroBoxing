class_name ActiveRagdoll
extends Node3D

## Empty enables every discovered joint. Start with one elbow for tuning.
@export var motor_bones: Array[StringName] = [&"mixamorig_LeftForeArm"]
@export var debug_targets := false
@export var stiffness := 2.0
@export var damping := 0.08
@export var max_torque := 0.5

@onready var bone_sim: PhysicalBoneSimulator3D = $PhysicalSkeleton/PhysicalBoneSimulator3D
@onready var skel: Skeleton3D = $PhysicalSkeleton
var pd_controller: ActiveRagdollPD3D

func _ready() -> void:
	RagdollCollisionJitterFix.new().apply(skel, bone_sim)
	pd_controller = ActiveRagdollPD3D.new()
	pd_controller.name = "PDController"
	add_child(pd_controller)
	pd_controller.default_stiffness = stiffness
	pd_controller.default_damping = damping
	pd_controller.default_max_torque = max_torque
	if not pd_controller.initialize(skel, bone_sim):
		push_error("Could not initialize ragdoll PD joints.")
		return
	for bone_name in pd_controller.get_controlled_bones():
		pd_controller.set_joint_enabled(bone_name, motor_bones.is_empty() or bone_name in motor_bones)
	if not pd_controller.capture_reference_pose():
		return
	bone_sim.physical_bones_start_simulation()
	pd_controller.enabled = true
	if debug_targets:
		var debug := preload("res://Ragdoll/ragdoll_debug_targets.gd").new()
		debug.controller = pd_controller
		add_child(debug)
