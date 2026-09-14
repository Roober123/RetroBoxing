extends SceneTree

# Dedicated headless entry point; existing visual training scene stays unchanged.
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var manager := BalanceTrainingManager.new()
	manager.name = "BalanceTrainingManager"
	manager.arena_count = 2
	var port := 7000
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--arenas="):
			manager.arena_count = int(arg.trim_prefix("--arenas="))
		elif arg.begins_with("--port="):
			port = int(arg.trim_prefix("--port="))
	assert(manager.arena_count >= 1 and manager.arena_count <= 1024)
	root.add_child(manager)
	var server := BalanceTrainingServer.new()
	server.port = port
	root.add_child(server)
