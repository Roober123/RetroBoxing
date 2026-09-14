class_name BalanceTCPProtocol
extends RefCounted

const MAGIC := 0x31584252 # "RBX1" on the wire.
const VERSION := 1
const HEADER_SIZE := 12
const MAX_PAYLOAD := 4 * 1024 * 1024
enum Command { HELLO = 1, RESET = 2, STEP = 3, CLOSE = 4, ERROR = 5 }

static func packet(command: int, payload := PackedByteArray()) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(HEADER_SIZE)
	bytes.encode_u32(0, MAGIC)
	bytes.encode_u16(4, VERSION)
	bytes.encode_u16(6, command)
	bytes.encode_u32(8, payload.size())
	bytes.append_array(payload)
	return bytes

static func header_error(bytes: PackedByteArray) -> String:
	if bytes.size() < HEADER_SIZE:
		return "Incomplete header"
	if bytes.decode_u32(0) != MAGIC:
		return "Invalid magic"
	if bytes.decode_u16(4) != VERSION:
		return "Incompatible protocol version"
	if bytes.decode_u16(6) not in [Command.HELLO, Command.RESET, Command.STEP, Command.CLOSE]:
		return "Invalid command"
	if bytes.decode_u32(8) > MAX_PAYLOAD:
		return "Payload too large"
	return ""

static func hello(manager: BalanceTrainingManager) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(24)
	var values := [VERSION, manager.arenas.size(), manager.get_observation_size(), manager.get_action_size(), manager.PHYSICS_HZ, manager.POLICY_HZ]
	for i in values.size():
		bytes.encode_u32(i * 4, values[i])
	return bytes

static func observations(rows: Array) -> PackedByteArray:
	var bytes := PackedByteArray()
	for row in rows:
		for value in row:
			var offset := bytes.size()
			bytes.resize(offset + 4)
			bytes.encode_float(offset, value)
	return bytes

static func decode_actions(bytes: PackedByteArray, count: int, size: int) -> Array:
	if bytes.size() != count * size * 4:
		return []
	var actions: Array = []
	for i in count:
		var row := PackedFloat32Array()
		for j in size:
			var value := bytes.decode_float((i * size + j) * 4)
			if not is_finite(value) or absf(value) > 1.0:
				return []
			row.append(value)
		actions.append(row)
	return actions

static func step_result(result: PolicyStepResult, observation_size: int) -> PackedByteArray:
	var bytes := observations(result.observations)
	bytes.append_array(observations([result.rewards]))
	for flag in result.terminated:
		bytes.append(int(flag))
	for flag in result.truncated:
		bytes.append(int(flag))
	for row in result.terminal_observations:
		bytes.append(int(not row.is_empty()))
	for row in result.terminal_observations:
		if row.is_empty():
			var zeros := PackedByteArray()
			zeros.resize(observation_size * 4)
			bytes.append_array(zeros)
		else:
			bytes.append_array(observations([row]))
	return bytes
