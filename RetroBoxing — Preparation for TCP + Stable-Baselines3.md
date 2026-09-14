# RetroBoxing — Preparation for TCP + Stable-Baselines3

## Goal

Prepare the existing balance-training system so that the next milestone can add:

```text
Godot
    ↕ TCP
Python VecEnv
    ↓
Stable-Baselines3 PPO
```

Do **not** implement TCP, Python, PPO, ONNX, or Godot RL Agents in this plan.

At the end of this plan, Godot itself should already behave like a complete batched RL environment.

Current intended rates remain:

```text
Physics: 240 Hz
Policy:   60 Hz
Action hold: 4 physics ticks
```

---

# Milestone 1 — Add a Balance Reward Component

Create:

```text
Ragdoll/balance_reward.gd
```

Attach one to every `BalanceTrainingArena`.

Its only responsibility is:

```text
current ragdoll state
        ↓
scalar reward
```

It should read from:

```text
BalanceStateProvider
```

and should not modify the ragdoll.

Expose:

```gdscript
func get_reward() -> float
```

For the first RL experiment, keep the reward intentionally simple.

Use approximately:

```text
uprightness
COM near support center
reasonable pelvis height
```

For example conceptually:

```text
reward =
    upright_reward
  + com_reward
  + height_reward
```

A fallen ragdoll should receive a clear negative terminal penalty.

Do **not** reward yet:

```text
boxing stance
hands near face
dodging
punching
movement
specific joint rotations
energy efficiency
```

The first task is only:

> remain standing.

### Verification

Test several known states:

```text
upright → high reward

leaning → lower reward

bad COM displacement → lower reward

fallen → low/negative reward
```

All rewards must be finite.

---

# Milestone 2 — Expose Reward Through BalanceEnvironment

Extend the public arena API.

Current API already contains functionality such as:

```text
reset()
get_observation()
apply_action()
is_terminal()
has_failed()
has_timed_out()
```

Add:

```gdscript
func get_reward() -> float
```

`BalanceEnvironment` should simply delegate to its reward component.

The eventual TCP layer should communicate almost entirely with this public API rather than reaching into ragdoll internals.

---

# Milestone 3 — Define Explicit RL Dimensions

Add:

```gdscript
func get_observation_size() -> int
func get_action_size() -> int
```

The action size is currently:

```text
12
```

Do not hardcode observation dimensions in several different places.

Determine the observation size from the current observation layout and expose it through one authoritative API.

Every observation must satisfy:

```text
observation.size() == get_observation_size()
```

Every action must satisfy:

```text
action.size() == get_action_size()
```

Add tests for both.

---

# Milestone 4 — Normalize Observation Values

Keep the existing observation information.

Do not redesign it yet.

Normalize quantities that can have substantially different magnitudes.

Examples:

```text
pelvis up / forward:
already approximately [-1, 1]

quaternion:
already approximately [-1, 1]

contact flags:
already 0 / 1

pelvis height:
divide by expected standing height

linear velocity:
divide by a sensible velocity scale

angular velocity:
divide by a sensible angular velocity scale

foot positions:
divide by character-size scale

COM positions / offsets:
divide by character-size scale
```

Clamp extreme normalized values if necessary.

Example:

```text
normalized velocity → clamp to [-5, 5]
```

Avoid aggressive clipping to `[-1,1]` if useful state information would disappear.

### Verification

Run the ragdoll through:

```text
neutral
falling
large joint movement
reset
```

and verify:

```text
no NaN
no infinity
no absurdly huge values
fixed observation size
```

---

# Milestone 5 — Create a Single Policy-Step Result

Introduce a small data contract representing one RL transition boundary.

Conceptually:

```text
PolicyStepResult

observations
rewards
terminated
truncated
```

For each arena:

```text
terminated = has_failed()
truncated  = has_timed_out()
```

Keep these separate.

Do not reduce them to one `done` value inside Godot.

Python/SB3 can later adapt them as necessary.

---

# Milestone 6 — Add Batched Reward Collection

Extend `BalanceTrainingManager` with:

```gdscript
func get_rewards() -> PackedFloat32Array
```

Result:

```text
rewards[arena_index]
```

For example with 9 arenas:

```text
observations → [9][observation_size]
rewards      → [9]
terminated   → [9]
truncated    → [9]
```

The manager should be able to gather all four pieces consistently at the same policy boundary.

---

# Milestone 7 — Replace the Current Policy Signal With a Clean Step Boundary

Currently `BalanceTrainingManager` owns a 60 Hz scheduler and emits a signal when a policy step is required.

Prepare it for external control instead.

Create an explicit concept such as:

```gdscript
func begin_policy_step(actions: Array) -> void
```

or equivalent.

Its logical behavior should be:

```text
receive action batch

apply actions to all arenas

hold those actions for exactly 4 physics ticks

after tick 4:
    collect observations
    collect rewards
    collect terminated flags
    collect truncated flags
```

Do not add networking yet.

The important change is that:

> one policy step becomes a clearly defined unit of simulation.

---

# Milestone 8 — Do Not Reset Before Transition Data Is Collected

This is important.

For an arena that falls during the four-tick interval:

```text
action
↓
simulate
↓
fall detected
↓
collect:
    final observation
    reward
    terminated = true
↓
only then reset
```

Do not reset the arena before its terminal state has been captured.

Otherwise the future Python trainer could accidentally receive the reset state as the final state of the previous episode.

---

# Milestone 9 — Store the Terminal Observation

When an arena terminates or truncates, preserve:

```text
terminal_observation
```

before resetting it.

You do not need to expose this over TCP yet.

Just make sure the training manager has access to it.

This will later map cleanly into the `info` dictionary expected by SB3's vector environment behavior.

---

# Milestone 10 — Reset Finished Arenas Individually

After transition data has been captured:

```text
Arena 0 alive → continue

Arena 1 failed → reset

Arena 2 alive → continue

Arena 3 timed out → reset
```

Only reset finished arenas.

After reset, their next observation should represent the beginning of the new episode.

Do not reset the whole training batch.

---

# Milestone 11 — Make Policy Stepping Independent of Rendering

The balance training system must work without:

```text
Camera3D
WorldEnvironment
UI
debug visualization
```

Keep:

```text
balance_training_arena.tscn
```

simulation-only.

Keep rendering/debugging in dedicated scenes.

The eventual TCP training process should be able to run Godot headless.

---

# Milestone 12 — Add Random-Action Stress Testing

Create an automated test that behaves like a fake RL trainer.

Run multiple arenas.

For every policy step:

```text
generate random actions in [-1, 1]

apply action batch

run one policy interval

collect transition
```

Run at least several thousand policy steps.

Verify continuously:

```text
observation dimensions never change

action dimensions never change

all observations finite

all rewards finite

terminal flags valid

truncated flags valid

arenas reset independently

no ragdoll produces NaN transforms

no runaway velocities

one arena failing does not affect others
```

This is the most important test before networking.

---

# Milestone 13 — Test Neutral Policy Separately

Run the same training loop using:

```text
get_neutral_action()
```

for every arena.

Measure:

```text
average survival duration
reward over time
failure reason
```

This gives you a baseline.

Later, PPO should clearly outperform this baseline.

---

# Milestone 14 — Add Minimal Training Statistics

Do not build a HUD.

Track only useful debugging values:

```text
episode count

average episode duration

average episode reward

failed episode count

timed-out episode count
```

These can initially be printed occasionally.

They will later help verify that the Python side reports the same behavior.

---

# Milestone 15 — Remove RL-Specific Logic From the Ragdoll

Verify that none of these know about training:

```text
ActiveRagdoll

ActiveRagdollPD3D

RagdollTargetController

BalanceController
```

They should only know:

```text
state
targets
actions
physics
```

RL ownership should remain above them:

```text
BalanceStateProvider
BalanceReward
BalanceEpisode
BalanceEnvironment
BalanceTrainingManager
```

This separation should remain when TCP is added.

---

# Milestone 16 — Define the Future TCP Contract on Paper Only

Do not implement it yet.

Document the future protocol.

Startup metadata:

```text
protocol_version
arena_count
observation_size
action_size
```

STEP input:

```text
[num_arenas, action_size] float32
```

STEP output:

```text
observations
[num_arenas, observation_size] float32

rewards
[num_arenas] float32

terminated
[num_arenas] bool

truncated
[num_arenas] bool
```

Possible commands:

```text
HELLO
RESET
STEP
CLOSE
```

Keep the protocol deliberately minimal.

---

# Final Godot Architecture

```text
BalanceTrainingManager
│
├── BalanceTrainingArena 0
│   ├── ActiveRagdoll
│   ├── BalanceController
│   ├── BalanceStateProvider
│   ├── BalanceReward
│   └── BalanceEpisode
│
├── BalanceTrainingArena 1
│   └── ...
│
└── ...
```

The manager should now be able to perform conceptually:

```text
step(actions)
    ↓
simulate 4 × physics ticks
    ↓
return:
    observations
    rewards
    terminated
    truncated
```

without TCP and without Python.

---

# Stop Point

Stop after the random-action and neutral-action tests pass.

Do **not** implement PPO yet.

At this point the next milestone can be extremely focused:

```text
BalanceTrainingManager
        ↕
BalanceTrainingServer
        ↕ TCP
Python RetroBoxingVecEnv
        ↕
Stable-Baselines3 PPO
```

The networking layer should then contain almost no game or RL logic; it should mostly serialize and deserialize the already-working environment step.