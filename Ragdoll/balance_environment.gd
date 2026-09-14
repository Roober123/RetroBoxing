class_name BalanceEnvironment
extends Node3D

@export_range(0.0, 2.0, 0.05) var gravity_scale := 1.0
@onready var state_provider: BalanceStateProvider = $BalanceStateProvider
@onready var balance_controller: BalanceController = $BalanceController
@onready var episode: BalanceEpisode = $BalanceEpisode
@onready var ragdoll: ActiveRagdoll = $ActiveRagdoll
var _original_gravity_scales: Dictionary = {}

func _ready() -> void:
	for child in ragdoll.bone_sim.get_children():
		if child is PhysicalBone3D:
			_original_gravity_scales[child] = child.gravity_scale
	_apply_gravity_scale()

func reset() -> void:
	episode.reset()

func get_observation() -> PackedFloat32Array:
	return state_provider.get_observation()

func apply_action(action) -> void:
	balance_controller.apply_action(action)

func get_action_size() -> int:
	return balance_controller.get_action_size()

func get_neutral_action() -> PackedFloat32Array:
	return balance_controller.get_neutral_action()

func set_gravity_scale(value: float) -> void:
	gravity_scale = clampf(value, 0.0, 2.0)
	_apply_gravity_scale()

func get_gravity_scale() -> float:
	return gravity_scale

func _apply_gravity_scale() -> void:
	for body in _original_gravity_scales:
		if is_instance_valid(body):
			body.gravity_scale = float(_original_gravity_scales[body]) * gravity_scale

func is_terminal() -> bool:
	return episode.is_terminal()

func has_failed() -> bool:
	return episode.has_failed()

func has_timed_out() -> bool:
	return episode.has_timed_out()
