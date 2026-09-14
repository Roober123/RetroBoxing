class_name BalanceTrainingServer
extends Node

const Protocol = preload("res://Ragdoll/balance_tcp_protocol.gd")
@export var port := 7000
@export var bind_address := "127.0.0.1"
@export var manager_path: NodePath = ^"../BalanceTrainingManager"
enum ConnectionState { LISTENING, CONNECTED, STEP_RUNNING }
var state := ConnectionState.LISTENING
var manager: BalanceTrainingManager
var _server := TCPServer.new()
var _peer: StreamPeerTCP
var _incoming := PackedByteArray()
var _outgoing := PackedByteArray()
var _hello_done := false
var _closing := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	manager = get_node(manager_path)
	manager.policy_step_completed.connect(_on_step_completed)
	var error := _server.listen(port, bind_address)
	if error != OK:
		push_error("Training TCP listen failed: %s" % error_string(error))
		set_process(false)
	else:
		print("Training TCP listening on %s:%d" % [bind_address, port])

func _exit_tree() -> void:
	_disconnect()
	_server.stop()

func _process(_delta: float) -> void:
	if _server.is_connection_available():
		var candidate := _server.take_connection()
		if _peer == null and manager.is_waiting_for_action():
			_peer = candidate
			_peer.set_no_delay(true)
			state = ConnectionState.CONNECTED
		else:
			candidate.disconnect_from_host()
	if _peer == null:
		return
	_peer.poll()
	if _peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		_disconnect()
		return
	if not _closing:
		var available := _peer.get_available_bytes()
		if available > 0:
			var received := _peer.get_partial_data(mini(available, 65536))
			if received[0] != OK:
				_disconnect()
				return
			_incoming.append_array(received[1])
		_consume_packets()
	if not _outgoing.is_empty():
		var sent := _peer.put_partial_data(_outgoing)
		if sent[0] != OK:
			_disconnect()
			return
		_outgoing = _outgoing.slice(sent[1])
	if _closing and _outgoing.is_empty():
		_disconnect()

func _consume_packets() -> void:
	while not _closing and _incoming.size() >= Protocol.HEADER_SIZE:
		var error := Protocol.header_error(_incoming)
		if not error.is_empty():
			_reject(error)
			return
		var command := _incoming.decode_u16(6)
		var size := _incoming.decode_u32(8)
		var expected := manager.arenas.size() * manager.get_action_size() * 4 if command == Protocol.Command.STEP else 0
		if size != expected:
			_reject("Incorrect payload size")
			return
		if _incoming.size() < Protocol.HEADER_SIZE + size:
			return
		var payload := _incoming.slice(Protocol.HEADER_SIZE, Protocol.HEADER_SIZE + size)
		_incoming = _incoming.slice(Protocol.HEADER_SIZE + size)
		_handle_packet(command, payload)

func _handle_packet(command: int, payload: PackedByteArray) -> void:
	if command == Protocol.Command.CLOSE:
		_closing = true # No CLOSE response.
		return
	if state == ConnectionState.STEP_RUNNING:
		_reject("Policy step already running")
		return
	if command == Protocol.Command.HELLO:
		_hello_done = true
		_send(command, Protocol.hello(manager))
	elif not _hello_done:
		_reject("HELLO required")
	elif command == Protocol.Command.RESET:
		_send(command, Protocol.observations(manager.reset_all()))
	elif command == Protocol.Command.STEP:
		var actions := Protocol.decode_actions(payload, manager.arenas.size(), manager.get_action_size())
		if actions.is_empty() or not manager.is_waiting_for_action():
			_reject("Invalid actions or manager busy")
			return
		state = ConnectionState.STEP_RUNNING
		manager.begin_policy_step(actions)

func _on_step_completed(result: PolicyStepResult) -> void:
	if _peer != null and not _closing:
		_send(Protocol.Command.STEP, Protocol.step_result(result, manager.get_observation_size()))
		state = ConnectionState.CONNECTED

func _send(command: int, payload: PackedByteArray) -> void:
	_outgoing.append_array(Protocol.packet(command, payload))
	if _outgoing.size() > Protocol.MAX_PAYLOAD * 2:
		_closing = true

func _reject(message: String) -> void:
	_send(Protocol.Command.ERROR, message.to_utf8_buffer())
	_closing = true

func _disconnect() -> void:
	if _peer != null:
		_peer.disconnect_from_host()
	_peer = null
	_incoming.clear()
	_outgoing.clear()
	_hello_done = false
	_closing = false
	state = ConnectionState.LISTENING
