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
	return reward_for_state(state)

static func reward_for_state(state: Dictionary) -> float:
	var uprightness := clampf(state.pelvis_up.dot(Vector3.UP), 0.0, 1.0)
	var com_reward := exp(-2.0 * state.horizontal_com_offset.length_squared()) if state.has_support else 0.0
	var height_reward := clampf(state.pelvis_height / BalanceStateProvider.STANDING_HEIGHT, 0.0, 1.0)
	var angular_stability := exp(-0.3 * state.pelvis_angular_velocity.length_squared())
	var velocity_reward := exp(-0.5 * state.horizontal_com_velocity.length_squared())
	var value := uprightness + com_reward + 0.5 * height_reward + 0.5 * angular_stability + 0.5 * velocity_reward
	return value if is_finite(value) else -1.0
