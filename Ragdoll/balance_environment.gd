class_name BalanceEnvironment
extends Node3D

@onready var state_provider: BalanceStateProvider = $BalanceStateProvider
@onready var balance_controller: BalanceController = $BalanceController
@onready var episode: BalanceEpisode = $BalanceEpisode

func reset() -> void:
	episode.reset()

func get_observation() -> PackedFloat32Array:
	return state_provider.get_observation()

func apply_action(action) -> void:
	balance_controller.apply_action(action)

func is_terminal() -> bool:
	return episode.is_terminal()

func has_failed() -> bool:
	return episode.has_failed()

func has_timed_out() -> bool:
	return episode.has_timed_out()
