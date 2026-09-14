class_name BalanceTrainingManager
extends Node3D

signal policy_step_requested(observations: Array)

const PHYSICS_HZ := 240
const POLICY_HZ := 60
const POLICY_INTERVAL := PHYSICS_HZ / POLICY_HZ

@export var arena_scene: PackedScene = preload("res://balance_training_arena.tscn")
@export_range(1, 1024, 1) var arena_count := 8
@export_range(9.0, 100.0, 0.5) var arena_spacing := 12.0
@export_range(0.0, 2.0, 0.05) var initial_gravity_scale := 0.1
@export var reset_terminal_arenas := true

var arenas: Array[BalanceEnvironment] = []
var physics_tick := 0
var policy_step_count := 0

func _ready() -> void:
	assert(Engine.physics_ticks_per_second == PHYSICS_HZ)
	_spawn_arenas()

func _physics_process(_delta: float) -> void:
	physics_tick += 1
	if physics_tick % POLICY_INTERVAL != 0:
		return
	policy_step_count += 1
	policy_step_requested.emit(get_observations())
	if reset_terminal_arenas:
		reset_terminated()

func _spawn_arenas() -> void:
	var columns := ceili(sqrt(float(arena_count)))
	for i in arena_count:
		var arena := arena_scene.instantiate() as BalanceEnvironment
		arena.name = "Arena%d" % i
		arena.position = Vector3((i % columns) * arena_spacing, 0.0, (i / columns) * arena_spacing)
		add_child(arena)
		arena.set_gravity_scale(initial_gravity_scale)
		arenas.append(arena)

func get_observations() -> Array:
	var observations: Array = []
	for arena in arenas:
		observations.append(arena.get_observation())
	return observations

func apply_actions(actions: Array) -> void:
	assert(actions.size() == arenas.size(), "One action is required per arena.")
	for i in arenas.size():
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
