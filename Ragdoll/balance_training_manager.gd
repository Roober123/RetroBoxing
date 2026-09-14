class_name BalanceTrainingManager
extends Node3D

signal policy_step_completed(result: PolicyStepResult)

const PHYSICS_HZ := 240
const POLICY_HZ := 60
const POLICY_INTERVAL := PHYSICS_HZ / POLICY_HZ

@export var arena_scene: PackedScene = preload("res://balance_training_arena.tscn")
@export_range(1, 1024, 1) var arena_count := 8
@export_range(9.0, 100.0, 0.5) var arena_spacing := 12.0
@export_range(0.0, 2.0, 0.05) var initial_gravity_scale := 0.1

var arenas: Array[BalanceEnvironment] = []
var physics_tick := 0
var policy_step_count := 0
var last_step_result: PolicyStepResult
var _ticks_remaining := 0
var episode_count := 0
var failed_episode_count := 0
var timed_out_episode_count := 0
var total_episode_duration := 0.0
var total_episode_reward := 0.0
var _episode_rewards := PackedFloat32Array()

func _ready() -> void:
	assert(Engine.physics_ticks_per_second == PHYSICS_HZ)
	_spawn_arenas()
	_episode_rewards.resize(arenas.size())

func _physics_process(_delta: float) -> void:
	physics_tick += 1
	if _ticks_remaining == 0:
		return
	_ticks_remaining -= 1
	if _ticks_remaining == 0:
		_finish_policy_step()

func begin_policy_step(actions: Array) -> void:
	assert(_ticks_remaining == 0, "A policy step is already in progress.")
	apply_actions(actions)
	_ticks_remaining = POLICY_INTERVAL

func is_policy_step_in_progress() -> bool:
	return _ticks_remaining > 0

func _finish_policy_step() -> void:
	var result := PolicyStepResult.new()
	for i in arenas.size():
		var arena := arenas[i]
		var observation := arena.get_observation()
		var reward_value := arena.get_reward()
		var failed := arena.has_failed()
		var timed_out := arena.has_timed_out()
		result.observations.append(observation)
		result.rewards.append(reward_value)
		result.terminated.append(failed)
		result.truncated.append(timed_out)
		result.terminal_observations.append(observation.duplicate() if failed or timed_out else PackedFloat32Array())
		_episode_rewards[i] += reward_value
		if failed or timed_out:
			episode_count += 1
			failed_episode_count += int(failed)
			timed_out_episode_count += int(timed_out)
			total_episode_duration += arena.episode.elapsed_time
			total_episode_reward += _episode_rewards[i]
			_episode_rewards[i] = 0.0
			arena.reset()
	last_step_result = result
	policy_step_count += 1
	policy_step_completed.emit(result)

func _spawn_arenas() -> void:
	var columns := ceili(sqrt(float(arena_count)))
	for i in arena_count:
		var arena := arena_scene.instantiate() as BalanceEnvironment
		arena.name = "Arena%d" % i
		arena.position = Vector3((i % columns) * arena_spacing, 0.0, (i / columns) * arena_spacing)
		add_child(arena)
		arena.set_gravity_scale(initial_gravity_scale)
		arenas.append(arena)

func get_observation_size() -> int:
	return arenas[0].get_observation_size() if not arenas.is_empty() else 0

func get_action_size() -> int:
	return arenas[0].get_action_size() if not arenas.is_empty() else 0

func get_observations() -> Array:
	var observations: Array = []
	for arena in arenas:
		observations.append(arena.get_observation())
	return observations

func get_rewards() -> PackedFloat32Array:
	var rewards := PackedFloat32Array()
	for arena in arenas:
		rewards.append(arena.get_reward())
	return rewards

func apply_actions(actions: Array) -> void:
	assert(actions.size() == arenas.size(), "One action is required per arena.")
	for i in arenas.size():
		assert(actions[i].size() == get_action_size(), "Action has the wrong size.")
		arenas[i].apply_action(actions[i])

func get_terminal_states() -> Array[Dictionary]:
	var states: Array[Dictionary] = []
	for arena in arenas:
		states.append({"failed": arena.has_failed(), "timed_out": arena.has_timed_out()})
	return states

func reset_terminated() -> void:
	for arena in arenas:
		if arena.is_terminal():
			arena.reset()

func set_all_gravity_scale(value: float) -> void:
	for arena in arenas:
		arena.set_gravity_scale(value)

func get_training_statistics() -> Dictionary:
	return {
		"episode_count": episode_count,
		"average_episode_duration": total_episode_duration / episode_count if episode_count > 0 else 0.0,
		"average_episode_reward": total_episode_reward / episode_count if episode_count > 0 else 0.0,
		"failed_episode_count": failed_episode_count,
		"timed_out_episode_count": timed_out_episode_count,
	}
