# RetroBoxing — TCP + Stable-Baselines3 Integration Plan

## Goal

Connect the existing deterministic Godot RL environment to Python using a small custom TCP protocol, then expose it to Stable-Baselines3 through a custom vector environment.

Do not change the ragdoll, PD system, reward design, observation layout, or action layout during this milestone unless a real integration bug requires it.

Current RL contract:

```text id="wjhj2t"
Observation size: 175 float32
Action size:       12 float32
Physics rate:      240 Hz
Policy rate:       60 Hz
Physics ticks/action: 4
```

Godot already owns:

```text id="uuk9bp"
simulation
reward
termination
truncation
reset
multi-arena batching
policy stepping
pause/wait behavior
```

Python should own:

```text id="nx0fda"
TCP client
SB3 VecEnv adapter
PPO
logging
model saving
```

---

# Milestone 1 — Add `reset_all()` to BalanceTrainingManager

Add a clean manager API:

```gdscript id="at88pf"
func reset_all() -> Array:
```

Requirements:

```text id="7h1rnk"
must only run while WAITING_FOR_ACTION

reset every arena

clear per-arena episode reward accumulators

return fresh observations
```

Do not reset lifetime statistics by default.

For example, preserve:

```text id="qs75xj"
episode_count
failed_episode_count
timed_out_episode_count
total_episode_duration
total_episode_reward
```

This API will be used by the TCP `RESET` command.

### Verify

After arbitrary actions:

```text id="hl415h"
reset_all()
```

must produce:

```text id="f8cnuu"
all arenas at initial transforms
zero physical velocity
neutral controller action
elapsed_time = 0
fresh observation batch
```

---

# Milestone 2 — Define the Binary TCP Protocol

Update `TCP_PROTOCOL.md`.

Use one TCP connection between:

```text id="2h6tdy"
one Godot training process
↕
one Python training process
```

Use binary payloads.

Do not use JSON for STEP messages.

Define a small message header.

Recommended structure:

```text id="bb1ezy"
uint32 magic
uint16 protocol_version
uint16 command
uint32 payload_size
```

Example command IDs:

```text id="2s9o1s"
1 = HELLO
2 = RESET
3 = STEP
4 = CLOSE
5 = ERROR
```

Use a fixed byte order.

Prefer:

```text id="hl8gfe"
little-endian
```

Document it explicitly.

---

# Milestone 3 — Define HELLO

Python sends:

```text id="qpxn1l"
HELLO
```

Godot responds with metadata:

```text id="4uk5kw"
protocol_version
arena_count
observation_size
action_size
physics_hz
policy_hz
```

For the current project:

```text id="xj558o"
observation_size = 175
action_size = 12
physics_hz = 240
policy_hz = 60
```

The Python client must validate these before allowing training.

If an incompatible protocol version is received:

```text id="yak4na"
disconnect cleanly
```

---

# Milestone 4 — Define RESET

Python sends:

```text id="ock4t0"
RESET
```

Godot calls:

```text id="du37bs"
BalanceTrainingManager.reset_all()
```

Godot responds:

```text id="b6nwo5"
observations
```

Shape:

```text id="1lhb1z"
[arena_count, observation_size]
```

Type:

```text id="w6qn3n"
float32
```

No reward or done flags are needed for RESET.

---

# Milestone 5 — Define STEP Input

Python sends:

```text id="ib664e"
STEP
```

followed by:

```text id="jjpgu4"
arena_count * action_size
```

float32 values.

Logical shape:

```text id="656vkn"
[arena_count, 12]
```

Godot validates:

```text id="ewcgj5"
manager.is_waiting_for_action()

action count correct

all values finite

all values within valid action range
```

Clamp only if that matches the existing controller behavior.

Prefer rejecting malformed packets rather than silently accepting incorrect dimensions.

---

# Milestone 6 — Connect STEP to the Existing Policy Step

When a complete STEP packet arrives:

```text id="31cj5g"
decode actions
↓
manager.begin_policy_step(actions)
```

Do not block the socket-processing code waiting inside the same callback.

Instead:

```text id="e92nxq"
receive STEP
↓
start policy step
↓
manager runs 4 physics ticks
↓
policy_step_completed emitted
↓
TCP server sends result
```

This keeps Godot's existing stepping model intact.

---

# Milestone 7 — Define STEP Output

When `policy_step_completed` fires, send:

```text id="9iutz0"
observations
rewards
terminated
truncated
terminal_observation presence
terminal_observations
```

Recommended fixed-size core arrays:

```text id="9f6dbk"
observations:
    float32 [N, 175]

rewards:
    float32 [N]

terminated:
    uint8 [N]

truncated:
    uint8 [N]
```

For terminal observations, use one simple format.

Recommended:

```text id="w54qrn"
terminal_mask:
    uint8 [N]

terminal_observations:
    float32 [N, 175]
```

For non-terminal arenas:

```text id="a0qwtf"
terminal_mask[i] = 0
```

and the corresponding terminal observation row may be zero-filled.

This keeps every STEP response a fixed size.

That is easier to parse and debug than variable-size packets.

---

# Milestone 8 — Create `BalanceTrainingServer.gd`

Create something like:

```text id="uzlotp"
Ragdoll/balance_training_server.gd
```

Responsibilities:

```text id="zoaa6v"
listen on TCP port

accept one Python connection

read message headers

read complete payloads

validate commands

translate TCP actions into manager calls

serialize policy results

handle disconnects
```

It must not calculate:

```text id="e0e25r"
reward
observation
termination
physics
reset logic
```

Those already belong to the training environment.

Set:

```text id="pw2rpv"
process_mode = PROCESS_MODE_ALWAYS
```

because the training SceneTree is paused while waiting for Python.

---

# Milestone 9 — Handle TCP Stream Semantics Correctly

TCP is a byte stream.

Do not assume:

```text id="9ak7ue"
one send = one receive
```

The server must support partial reads.

Maintain a receive buffer:

```text id="udlrmq"
incoming bytes
↓
wait until full header exists
↓
read payload_size
↓
wait until full payload exists
↓
process complete packet
```

Likewise, make sure outgoing packets are fully written.

This is important even on localhost.

---

# Milestone 10 — Add Connection State

Use a simple connection state:

```text id="zra21r"
LISTENING
CONNECTED
STEP_RUNNING
```

Expected flow:

```text id="97b0lg"
Godot starts
↓
LISTENING

Python connects
↓
CONNECTED

STEP received
↓
STEP_RUNNING

policy step completes
↓
send result
↓
CONNECTED
```

Reject another STEP while one is already running.

---

# Milestone 11 — Handle Disconnects Safely

If Python disconnects:

```text id="o9ykgo"
clear peer

return server to LISTENING

leave training manager in WAITING_FOR_ACTION
```

If disconnect occurs while a policy step is running:

```text id="kv6krg"
allow current 4-tick step to finish

discard unsent result if necessary

return to WAITING_FOR_ACTION
```

Do not leave the simulation permanently unpaused.

The server should be able to accept a new client without restarting Godot.

---

# Milestone 12 — Add Godot-Side Protocol Tests

Before writing SB3 code, add tests for serialization.

Test:

```text id="rdatva"
HELLO encode/decode

RESET response shape

STEP request shape

STEP response shape

wrong protocol version

wrong action count

NaN action

invalid command
```

These tests should not need a real Python process.

Use byte buffers directly where possible.

---

# Milestone 13 — Create a Minimal Python TCP Client

Create a small Python training folder, for example:

```text id="557h7s"
training/
    protocol.py
    tcp_client.py
    random_client.py
```

Do not add SB3 yet.

`protocol.py` owns:

```text id="r5k92x"
message constants
header packing
header unpacking
numpy serialization
```

`tcp_client.py` owns:

```text id="o9g5yp"
connect()
hello()
reset()
step(actions)
close()
```

---

# Milestone 14 — Python HELLO Test

Run Godot training scene.

Run Python client.

Verify Python receives:

```text id="5y895x"
arena_count
observation_size = 175
action_size = 12
physics_hz = 240
policy_hz = 60
```

Fail immediately if these do not match expectations.

This is the first end-to-end TCP test.

Stop here if HELLO is unreliable.

---

# Milestone 15 — Python RESET Test

From Python:

```python id="nbz51k"
obs = client.reset()
```

Verify:

```text id="ah5hbi"
obs.dtype == float32

obs.shape ==
(arena_count, 175)

all finite
```

Also verify the final 12 values of each observation represent the neutral action.

---

# Milestone 16 — Python Random STEP Test

Generate:

```text id="f4wr7l"
random actions in [-1, 1]
```

Shape:

```text id="03ztun"
[N, 12]
```

Call:

```python id="zdkpbf"
result = client.step(actions)
```

Verify:

```text id="lst23n"
observations.shape == (N, 175)

rewards.shape == (N,)

terminated.shape == (N,)

truncated.shape == (N,)

terminal_mask.shape == (N,)
```

Check all numeric values are finite.

---

# Milestone 17 — Run 10,000 TCP Steps Without SB3

This is the transport stress test.

Run:

```text id="4gzg9y"
10,000 STEP calls
```

using random actions.

Verify:

```text id="qeyocj"
no lost packets

no protocol desync

no partial-read bugs

no changing shapes

no NaNs

Godot remains responsive

terminal/reset behavior remains correct

Python can reconnect after disconnect
```

Do not start PPO until this works.

---

# Milestone 18 — Create `RetroBoxingVecEnv`

Now add:

```text id="wet7mi"
training/retro_boxing_vec_env.py
```

Subclass:

```python id="792ti6"
stable_baselines3.common.vec_env.VecEnv
```

Define spaces:

```text id="h6xm0g"
observation_space:
Box(
    low=-5,
    high=5,
    shape=(175,),
    dtype=float32
)

action_space:
Box(
    low=-1,
    high=1,
    shape=(12,),
    dtype=float32
)
```

The exact observation bounds can be widened if some values naturally exceed this range, but they should match the actual Godot observation contract.

---

# Milestone 19 — Implement VecEnv `reset()`

SB3 calls:

```python id="7l0bek"
env.reset()
```

Implementation:

```text id="vdr6jo"
TCP RESET
↓
receive observation batch
↓
return numpy array [N, 175]
```

Ensure:

```text id="h5xk2v"
dtype = np.float32
```

---

# Milestone 20 — Implement `step_async()`

SB3 calls:

```python id="ebrpml"
step_async(actions)
```

Store actions.

Optionally send STEP immediately.

Validate:

```text id="s5koyh"
shape == (N, 12)

finite values
```

Do not receive the result yet.

---

# Milestone 21 — Implement `step_wait()`

`step_wait()` receives the STEP result.

Convert:

```text id="g0w94y"
done = terminated OR truncated
```

Create one `info` dictionary per arena.

For timeout:

```python id="0ole0k"
info["TimeLimit.truncated"] = True
```

For completed episodes:

```python id="whgzh5"
info["terminal_observation"] = terminal_observation
```

Return:

```python id="qfm7xv"
observations,
rewards,
dones,
infos
```

This is the SB3-facing adaptation layer.

Do not change Godot's terminated/truncated representation.

---

# Milestone 22 — Implement VecEnv `close()`

Send:

```text id="ebxvrh"
CLOSE
```

then close the Python socket.

Handle cases where Godot has already disconnected without crashing.

---

# Milestone 23 — Run SB3 Environment Checks

Before PPO, test manually:

```python id="qy35as"
obs = env.reset()

for _ in range(1000):
    actions = np.random.uniform(
        -1,
        1,
        size=(env.num_envs, 12)
    )
    obs, rewards, dones, infos = env.step(actions)
```

Verify:

```text id="cm30zn"
correct shapes

correct dtypes

correct terminal observations

correct timeout flags

automatic arena resets behave correctly
```

---

# Milestone 24 — First PPO Smoke Test

Start small.

Use:

```text id="99n6nm"
arena_count = 1 or 2
gravity_scale = 0.1
```

Do not start at full gravity.

Create:

```text id="gjqxrx"
train_ppo.py
```

Conceptually:

```python id="ty4c8i"
env = RetroBoxingVecEnv(...)

model = PPO(
    "MlpPolicy",
    env,
    verbose=1,
)

model.learn(...)
```

The goal is not a stable boxer yet.

The first goal is:

```text id="z6zdub"
PPO runs

no environment/protocol errors

loss values remain finite

episode statistics appear

average survival begins improving
```

---

# Milestone 25 — Compare PPO Against Neutral Baseline

You already have a neutral baseline.

Compare:

```text id="ncm29c"
average episode duration

average episode reward
```

between:

```text id="eb4fgq"
neutral controller
```

and:

```text id="438xfd"
PPO policy
```

The first success criterion is simply:

> PPO learns to survive measurably longer than the neutral action baseline.

Do not judge visual quality yet.

---

# Milestone 26 — Increase Parallel Arenas

Once PPO works with 1–2 arenas:

```text id="r48139"
2
↓
4
↓
8
↓
16
```

Measure:

```text id="m7hgkn"
steps per second
CPU usage
Godot frame/physics cost
Python training throughput
```

Do not increase arena count purely because the machine can allocate them.

Use the count that gives the best useful simulation throughput.

---

# Milestone 27 — Add Training Logging

Use SB3 logging/TensorBoard for:

```text id="foxpxu"
episode reward
episode duration
policy loss
value loss
entropy
explained variance
steps per second
```

Also send or log from Godot if useful:

```text id="ystvgg"
failed episodes
timed-out episodes
```

Do not build a Godot UI for this.

---

# Milestone 28 — Save and Reload a PPO Model

Verify:

```text id="6zlxl7"
train
save
close program
restart Godot/Python
load model
continue training
```

This ensures the training pipeline is practical before investing in long runs.

---

# Final Architecture

```text id="z8nuzx"
Godot

BalanceTrainingManager
│
├── Arena 0
├── Arena 1
├── Arena 2
└── ...
        │
        ▼
BalanceTrainingServer
PROCESS_MODE_ALWAYS
        │
        │ binary TCP
        ▼

Python

RetroBoxingTCPClient
        │
        ▼
RetroBoxingVecEnv
        │
        ▼
Stable-Baselines3 PPO
```

Godot owns simulation.

Python owns learning.

Neither side should contain the other's responsibilities.

---

# Important Stop Points

Stop after each of these and verify before continuing:

```text id="n0zn1b"
1. HELLO works reliably

2. RESET works reliably

3. random STEP works reliably

4. 10,000 TCP steps work reliably

5. VecEnv random-action test works

6. PPO starts without protocol/environment errors

7. PPO beats neutral baseline
```

Do not debug PPO while TCP is still unreliable.

Do not tune reward while the VecEnv contract is still unreliable.

Do not optimize training speed until learning works correctly.

---

# First Implementation Target

The immediate next milestone should only implement:

```text id="ew3esg"
BalanceTrainingManager.reset_all()

BalanceTrainingServer.gd

HELLO
RESET
STEP
CLOSE

Python TCP client

random-action end-to-end test
```

Do not add SB3 until that passes.

Once the random Python client can drive thousands of transitions correctly, wrapping it in `RetroBoxingVecEnv` should be a relatively small step.