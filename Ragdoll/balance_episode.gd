class_name BalanceEpisode
extends Node

@export var ragdoll_path: NodePath = ^"../ActiveRagdoll"
@export var controller_path: NodePath = ^"../BalanceController"
@export var minimum_pelvis_height := 0.45
@export var minimum_head_height := 0.45
@export_range(0.0, 90.0, 1.0) var maximum_pelvis_tilt_degrees := 60.0
@export var maximum_distance := 4.0
@export_range(0.01, 3600.0, 0.01) var maximum_episode_duration := 10.0
var elapsed_time := 0.0

@onready var ragdoll: ActiveRagdoll = get_node(ragdoll_path)
@onready var balance_controller: BalanceController = get_node(controller_path)
var _bodies: Array[PhysicalBone3D] = []
var _initial_transforms: Array[Transform3D] = []
var _pelvis: PhysicalBone3D
var _head: PhysicalBone3D
var _start_position := Vector3.ZERO

func _ready() -> void:
	for child in ragdoll.bone_sim.get_children():
		if child is PhysicalBone3D:
			var body := child as PhysicalBone3D
			_bodies.append(body)
			_initial_transforms.append(body.global_transform)
			if body.bone_name == &"mixamorig_Hips":
				_pelvis = body
			elif body.bone_name == &"mixamorig_Head":
				_head = body
	_start_position = _pelvis.global_position

func _physics_process(delta: float) -> void:
	elapsed_time = minf(elapsed_time + delta, maximum_episode_duration)
	# Avoid delaying the boundary by one tick because of accumulated roundoff.
	if maximum_episode_duration - elapsed_time < 0.000000001:
		elapsed_time = maximum_episode_duration

func reset() -> void:
	elapsed_time = 0.0
	ragdoll.pd_controller.enabled = false
	ragdoll.target_controller.reset_targets()
	balance_controller.reset_action()
	ragdoll.bone_sim.physical_bones_stop_simulation()
	for i in _bodies.size():
		var body := _bodies[i]
		body.global_transform = _initial_transforms[i]
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
	ragdoll.bone_sim.physical_bones_start_simulation()
	for i in _bodies.size():
		var body := _bodies[i]
		PhysicsServer3D.body_set_state(body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, _initial_transforms[i])
		PhysicsServer3D.body_set_state(body.get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, Vector3.ZERO)
		PhysicsServer3D.body_set_state(body.get_rid(), PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, Vector3.ZERO)
		PhysicsServer3D.body_set_state(body.get_rid(), PhysicsServer3D.BODY_STATE_SLEEPING, false)
	ragdoll.pd_controller.enabled = true

func has_timed_out() -> bool:
	return elapsed_time >= maximum_episode_duration

func is_terminal() -> bool:
	return has_failed() or has_timed_out()

func has_failed() -> bool:
	if not _pelvis or not _head:
		return true
	if _pelvis.global_position.y < minimum_pelvis_height or _head.global_position.y < minimum_head_height:
		return true
	var pelvis_up := _pelvis.global_basis.orthonormalized() * Vector3.UP
	if pelvis_up.dot(Vector3.UP) < cos(deg_to_rad(maximum_pelvis_tilt_degrees)):
		return true
	var displacement := _pelvis.global_position - _start_position
	displacement.y = 0.0
	return displacement.length() > maximum_distance
