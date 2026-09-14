"""Little-endian RBX1 binary protocol. See TCP_PROTOCOL.md."""
from dataclasses import dataclass
import struct

import numpy as np

MAGIC = 0x31584252
VERSION = 1
HELLO, RESET, STEP, CLOSE, ERROR = range(1, 6)
HEADER = struct.Struct("<IHHI")
METADATA = struct.Struct("<6I")
MAX_PAYLOAD = 4 * 1024 * 1024
OBSERVATION_SIZE, ACTION_SIZE = 175, 12
NEUTRAL_ACTION = np.zeros(ACTION_SIZE, dtype=np.float32)


class ProtocolError(RuntimeError):
    pass


def packet(command, payload=b""):
    return HEADER.pack(MAGIC, VERSION, command, len(payload)) + payload


def unpack_header(data):
    magic, version, command, size = HEADER.unpack(data)
    if magic != MAGIC or version != VERSION:
        raise ProtocolError("Incompatible magic or protocol version")
    if command not in (HELLO, RESET, STEP, CLOSE, ERROR) or size > MAX_PAYLOAD:
        raise ProtocolError("Invalid command or payload size")
    return command, size


def decode_hello(data):
    if len(data) != METADATA.size:
        raise ProtocolError("Incorrect HELLO length")
    version, count, obs, action, physics, policy = METADATA.unpack(data)
    if (version, obs, action, physics, policy) != (VERSION, 175, 12, 240, 60):
        raise ProtocolError("Incompatible environment contract")
    if not 1 <= count <= 1024:
        raise ProtocolError("Invalid arena count")
    return dict(protocol_version=version, arena_count=count, observation_size=obs,
                action_size=action, physics_hz=physics, policy_hz=policy)


def encode_actions(actions, count):
    actions = np.asarray(actions, dtype="<f4")
    if actions.shape != (count, ACTION_SIZE):
        raise ValueError(f"Actions must have shape ({count}, {ACTION_SIZE})")
    if not np.isfinite(actions).all() or (np.abs(actions) > 1).any():
        raise ValueError("Actions must be finite and in [-1, 1]")
    return actions.tobytes(order="C")


def decode_observations(data, count):
    if len(data) != count * OBSERVATION_SIZE * 4:
        raise ProtocolError("Incorrect observation length")
    result = np.frombuffer(data, dtype="<f4").reshape(count, OBSERVATION_SIZE).copy()
    if not np.isfinite(result).all():
        raise ProtocolError("Non-finite observations")
    return result


@dataclass
class StepResult:
    observations: np.ndarray
    rewards: np.ndarray
    terminated: np.ndarray
    truncated: np.ndarray
    terminal_mask: np.ndarray
    terminal_observations: np.ndarray


def decode_step(data, count):
    if len(data) != count * (OBSERVATION_SIZE * 8 + 7):
        raise ProtocolError("Incorrect STEP length")
    offset = count * OBSERVATION_SIZE * 4
    observations = decode_observations(data[:offset], count)
    rewards = np.frombuffer(data, dtype="<f4", count=count, offset=offset).copy()
    offset += count * 4
    flags = np.frombuffer(data, dtype=np.uint8, count=count * 3, offset=offset).reshape(3, count)
    if (flags > 1).any() or not np.isfinite(rewards).all():
        raise ProtocolError("Invalid flags or rewards")
    terminated, truncated, mask = flags.astype(bool)
    if (terminated & truncated).any() or not np.array_equal(mask, terminated | truncated):
        raise ProtocolError("Inconsistent terminal flags")
    terminal = decode_observations(data[offset + count * 3:], count)
    return StepResult(observations, rewards, terminated, truncated, mask, terminal)
