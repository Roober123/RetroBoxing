# RetroBoxing TCP protocol v1

One Godot server accepts one Python client on `127.0.0.1:7000` by default.
All integers and IEEE-754 float32 values are **little-endian**. Arrays are
arena-major (C order), with no padding. No Variant or JSON encoding is used.

Every message starts with this 12-byte header (`struct.Struct("<IHHI")`):

| Offset | Type | Meaning |
| --- | --- | --- |
| 0 | uint32 | Magic `0x31584252` (bytes `RBX1`) |
| 4 | uint16 | Protocol version `1` |
| 6 | uint16 | Command |
| 8 | uint32 | Payload byte count, at most 4 MiB |

Responses use the request command, except errors. Send HELLO before RESET/STEP.
Wait for each response before another request. CLOSE has no response.

| ID | Command | Request payload | Response payload |
| --- | --- | --- | --- |
| 1 | HELLO | Empty | Six uint32: version, arena count N, observation size, action size, physics Hz, policy Hz |
| 2 | RESET | Empty | float32 observations `[N,175]` |
| 3 | STEP | float32 actions `[N,12]` | Arrays below, in order |
| 4 | CLOSE | Empty | None; server disconnects |
| 5 | ERROR | Server only | UTF-8 diagnostic, then disconnect |

HELLO returns `(1, N, 175, 12, 240, 60)`. Python validates every field before
permitting simulation commands. Supported N is 1 through 1024.

STEP response layout:

| Array | Type and shape | Bytes |
| --- | --- | --- |
| observations | float32 `[N,175]` | 700 N |
| rewards | float32 `[N]` | 4 N |
| terminated | uint8 `[N]` | N |
| truncated | uint8 `[N]` | N |
| terminal_mask | uint8 `[N]` | N |
| terminal_observations | float32 `[N,175]` | 700 N |

Total STEP payload: **1407 N bytes**. Flags are exactly 0 or 1. Failure takes
precedence over timeout, so terminated and truncated are mutually exclusive.
The mask equals their logical OR. Terminal rows contain the final observation
before automatic arena reset; ordinary observations contain the post-reset state.
Unused terminal rows are zero-filled.

STEP accepts only finite actions within `[-1,1]`, while the manager is waiting.
Incorrect sizes, invalid commands, bad magic/version, missing HELLO, and requests
during an active step produce ERROR and disconnect. Out-of-range values are
rejected instead of relying on the controller clamp. RESET delegates to
`reset_all()`, clearing episode reward accumulators while preserving lifetime
statistics. Neutral action is `[0,0,0,0,0,0,0,0,0,0,0,0]` (the final 12
observation values after reset).

Both ends handle fragmented headers/payloads. Godot buffers partial writes and
never waits in the socket callback for physics. The always-processing server
starts the existing four-tick policy step and sends its result from
`policy_step_completed`. A disconnect during a step lets that step finish and
pause normally; its result is discarded. New clients can connect once the
manager is waiting. Additional clients are disconnected while occupied.

See [RL_ENVIRONMENT.md](RL_ENVIRONMENT.md) for the unchanged simulation contract.
The server uses Godot's documented
[partial stream reads and writes](https://docs.godotengine.org/en/stable/classes/class_streampeer.html).
