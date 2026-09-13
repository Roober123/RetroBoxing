extends Node

@export var controller_path: NodePath = ^"../BalanceController"
@export var episode_path: NodePath = ^"../BalanceEpisode"
@export_range(0.05, 1.0, 0.05) var step := 0.25
@onready var controller: BalanceController = get_node(controller_path)
@onready var episode: BalanceEpisode = get_node(episode_path)
var selected_action := 0

func _ready() -> void:
	print("Balance controls: [ / ] select, - / = adjust, 0 clear, R reset")
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
		KEY_R:
			episode.reset()

func _adjust(amount: float) -> void:
	var next := controller.action.duplicate()
	next[selected_action] = clampf(next[selected_action] + amount, -1.0, 1.0)
	controller.apply_action(next)
	print(controller.get_action_names()[selected_action], ": ", next[selected_action])

func _print_selection() -> void:
	print("Selected balance action: ", controller.get_action_names()[selected_action])
