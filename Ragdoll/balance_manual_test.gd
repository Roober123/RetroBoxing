extends Node

@export var controller_path: NodePath = ^"../BalanceController"
@export var episode_path: NodePath = ^"../BalanceEpisode"
@export_range(0.05, 1.0, 0.05) var step := 0.25
@onready var controller: BalanceController = get_node(controller_path)
@onready var episode: BalanceEpisode = get_node(episode_path)
var selected_action := 0
@export var gravity_free := false
@export var auto_cycle := false
@export_range(0.2, 10.0, 0.1) var cycle_seconds := 2.0
var _cycle_elapsed := 0.0
var _cycle_index := 0
var _gravity: Dictionary = {}

func _ready() -> void:
	if not OS.is_debug_build():
		set_physics_process(false)
		set_process_unhandled_key_input(false)
		return
	for body in controller.ragdoll.bone_sim.get_children():
		if body is PhysicalBone3D:
			_gravity[body] = body.gravity_scale
	_set_gravity()
	print("Balance controls: [ / ] select, - / = adjust, 0 neutral, R reset, G gravity, C cycle")
	_print_selection()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_BRACKETLEFT:
			selected_action = wrapi(selected_action - 1, 0, controller.get_action_size())
			_print_selection()
		KEY_BRACKETRIGHT:
			selected_action = wrapi(selected_action + 1, 0, controller.get_action_size())
			_print_selection()
		KEY_MINUS:
			_adjust(-step)
		KEY_EQUAL:
			_adjust(step)
		KEY_0:
			controller.reset_action()
		KEY_G:
			gravity_free = not gravity_free
			_set_gravity()
			episode.reset()
		KEY_C:
			auto_cycle = not auto_cycle
			_cycle_index = 0
			_cycle_elapsed = cycle_seconds
		KEY_R:
			episode.reset()

func _adjust(amount: float) -> void:
	var next := controller.action.duplicate()
	next[selected_action] = clampf(next[selected_action] + amount, -1.0, 1.0)
	controller.apply_action(next)
	print(controller.get_action_names()[selected_action], ": ", next[selected_action])

func _print_selection() -> void:
	print("Selected balance action: ", controller.get_action_names()[selected_action])

func _set_gravity() -> void:
	for body in _gravity:
		body.gravity_scale = 0.0 if gravity_free else _gravity[body]
	print("Gravity-free verification: ", gravity_free)

func _physics_process(delta: float) -> void:
	if not auto_cycle:
		return
	_cycle_elapsed += delta
	if _cycle_elapsed < cycle_seconds:
		return
	_cycle_elapsed = 0.0
	episode.reset()
	selected_action = (_cycle_index / 3) as int
	var value := float(_cycle_index % 3 - 1)
	var next := controller.get_neutral_action()
	next[selected_action] = value
	controller.apply_action(next)
	print("Verify ", controller.get_action_names()[selected_action], " = ", value)
	_cycle_index = (_cycle_index + 1) % (controller.get_action_size() * 3)
