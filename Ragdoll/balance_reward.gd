class_name BalanceReward
extends Node

@onready var state_provider: BalanceStateProvider = $"../BalanceStateProvider"
@onready var episode: BalanceEpisode = $"../BalanceEpisode"

func get_reward() -> float:
	if episode.has_failed():
		return -1.0
	var state := state_provider.get_state()
	if state.is_empty():
		return -1.0
	var uprightness := clampf(state.pelvis_up.dot(Vector3.UP), 0.0, 1.0)
	var com_reward := exp(-2.0 * state.horizontal_com_offset.length_squared())
	var height_reward := clampf(state.pelvis_height / BalanceStateProvider.STANDING_HEIGHT, 0.0, 1.0)
	var value := uprightness + com_reward + height_reward
	return value if is_finite(value) else -1.0
