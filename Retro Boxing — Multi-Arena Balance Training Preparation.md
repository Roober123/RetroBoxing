# Retro Boxing — Multi-Arena Balance Training Preparation

## Goal

Prepare the balance system for RL training with:

- multiple independent balance arenas inside one Godot scene
- configurable gravity per arena
- 240 Hz physics
- 60 Hz policy/action updates
- clean batched access to observations and actions
- no HUD or unnecessary visualization
- current manual/debug testing preserved

Do **not** add PPO or a complicated reward system yet.

The result should be a clean simulation structure that can later run many ragdolls simultaneously for training.

---

# Target Architecture

```text
BalanceTrainingScene
│
├── TrainingArena 0
│   ├── Ground
│   ├── ActiveRagdoll
│   ├── BalanceStateProvider
│   ├── BalanceController
│   └── BalanceEpisode
│
├── TrainingArena 1
│   └── ...
│
├── TrainingArena 2
│   └── ...
│
└── BalanceTrainingManager
    ├── gathers observations
    ├── distributes actions
    ├── tracks policy ticks
    └── resets individual arenas
```

Each arena must be self-contained and independent.

---

# Milestone 1 — Turn `test.tscn` Into an Instantiable Arena

The current `test.tscn` already contains almost everything needed:

```text
ground
ragdoll
state provider
balance controller
balance episode
manual test
debug targets
```

Extract the actual simulation portion into:

```text
balance_training_arena.tscn
```

Root:

```text
BalanceTrainingArena : Node3D
```

Suggested contents:

```text
BalanceTrainingArena
├── Ground
├── ActiveRagdoll
├── BalanceStateProvider
├── BalanceController
└── BalanceEpisode
```

The arena should represent **one RL environment instance**.

Do not include:

```text
camera
WorldEnvironment
lighting
HUD
global training manager
```

Those belong to the outer training scene if needed.

---

# Milestone 2 — Keep Manual Testing Separate

Do not make manual/debug controls part of every training arena.

The current:

```text
balance_manual_test.gd
ragdoll_debug_targets.gd
```

should remain useful for development, but attach them only in a dedicated manual test scene.

For example:

```text
balance_manual_test.tscn
│
├── BalanceTrainingArena
├── Camera3D
├── WorldEnvironment
├── DirectionalLight3D
├── ManualActionTest
└── DebugTargets
```

This keeps the actual training arena minimal.

The same `BalanceTrainingArena` is therefore usable by:

```text
manual testing
automated tests
RL training
future evaluation
```

---

# Milestone 3 — Replace the Infinite Ground With a Local Arena Platform

The current test scene uses a `WorldBoundaryShape3D`.

Do not duplicate an infinite world boundary for every arena.

Give each arena its own finite platform.

For example:

```text
StaticBody3D
└── BoxShape3D
```

Around:

```text
8–10 m wide
```

The exact dimensions are not important yet.

The important property is:

> Every arena owns only the collision geometry around its own ragdoll.

This makes multiple instantiated arenas cleaner and easier to reason about.

---

# Milestone 4 — Add Gravity Scale to the Arena Environment

Gravity curriculum should **not** be part of `BalanceController`.

`BalanceController` should remain:

```text
RL action
    ↓
joint target rotations
```

Add gravity configuration to the arena/environment instead.

For example in `BalanceEnvironment` or the new arena root:

```gdscript
@export_range(0.0, 2.0, 0.05)
var gravity_scale := 1.0
```

Expose:

```text
set_gravity_scale(value)
get_gravity_scale()
```

On initialization, cache each physical body's original gravity scale.

Then apply:

```text
body.gravity_scale =
    original_gravity_scale * environment.gravity_scale
```

This lets each arena independently run at:

```text
0.1 g
0.25 g
0.5 g
1.0 g
```

even though all arenas exist in the same Godot world.

---

# Milestone 5 — Make Gravity Survive Reset Correctly

`BalanceEpisode.reset()` must not restore gravity to `1.0`.

Gravity is an environment parameter, not episode state.

Example:

```text
arena gravity = 0.25

reset()

arena gravity must remain 0.25
```

Test:

```text
set gravity = 0.1
reset 10 times
→ still 0.1
```

This will later allow curriculum changes without interfering with episode resets.

---

# Milestone 6 — Move Gravity Debugging Onto the Arena API

The current manual test directly modifies each `PhysicalBone3D`.

Remove that ownership.

Instead use something like:

```text
arena.set_gravity_scale(0.0)
```

for gravity-free joint testing.

And:

```text
arena.set_gravity_scale(1.0)
```

to restore normal gravity.

There should be only one implementation responsible for applying gravity scale.

---

# Milestone 7 — Give the Arena a Small Public API

The outer training manager should not access internal ragdoll nodes directly.

Expose a compact interface.

For example:

```text
reset()

get_observation()

apply_action(action)

get_action_size()

get_neutral_action()

has_failed()

has_timed_out()

is_terminal()

set_gravity_scale(scale)

get_gravity_scale()
```

Keep this API simple.

The future PPO bridge should interact mainly with this interface.

---

# Milestone 8 — Define the 60 Hz Policy Rate

Keep:

```text
Godot physics = 240 Hz
policy = 60 Hz
```

Therefore:

```text
240 / 60 = 4
```

One policy action is held for exactly:

```text
4 physics ticks
```

Sequence:

```text
physics tick 0
    request/apply new policy action

physics tick 1
    hold action

physics tick 2
    hold action

physics tick 3
    hold action

physics tick 4
    request/apply next action
```

Do not run the future neural network at 240 Hz.

---

# Milestone 9 — Make Policy Timing Explicit

Do not rely on an arbitrary floating-point timer such as:

```text
if accumulated_time > 1 / 60
```

because physics is already known to be 240 Hz.

Use a physics tick counter.

For example:

```text
PHYSICS_HZ = 240
POLICY_HZ = 60
POLICY_INTERVAL = 4
```

Conceptually:

```gdscript
physics_tick += 1

if physics_tick % 4 == 0:
    policy_step()
```

This guarantees deterministic 60 Hz policy timing.

---

# Milestone 10 — Keep the 60 Hz Scheduler Outside BalanceController

Do not put policy cadence into:

```text
BalanceController
```

The controller should immediately accept whatever action it is given.

The 60 Hz scheduling belongs to the training layer.

Preferred ownership:

```text
BalanceTrainingManager
```

because later the manager can update **all arenas together**.

---

# Milestone 11 — Create `BalanceTrainingManager`

Create a manager responsible for multiple arena instances.

Conceptually:

```text
BalanceTrainingManager
```

Responsibilities:

```text
spawn/register arenas

keep array of arenas

count physics ticks

every fourth physics tick:
    collect observations

accept/distribute actions

reset terminated arenas
```

Do not put ragdoll physics logic into this class.

---

# Milestone 12 — Spawn Arenas in a Grid

Add configurable arena count.

For example:

```gdscript
@export var arena_count := 8
@export var arena_spacing := 12.0
```

Spawn in a grid rather than a straight line.

Example with 9:

```text
A0     A1     A2


A3     A4     A5


A6     A7     A8
```

Arena positions might therefore be:

```text
(0, 0, 0)
(12, 0, 0)
(24, 0, 0)

(0, 0, 12)
(12, 0, 12)
(24, 0, 12)
```

Exact spacing can be adjusted.

---

# Milestone 13 — Ensure Arenas Cannot Interact

Current episode failure already limits horizontal displacement to approximately:

```text
4 m
```

Use arena spacing comfortably greater than twice that distance.

For example:

```text
12–15 m
```

This avoids:

```text
ragdoll-to-ragdoll collisions
foot rays finding another arena
bodies entering neighboring platforms
```

Do not use separate collision layers per arena.

Godot has a limited number of collision layers, so that architecture would not scale to many environments.

Use spatial separation.

---

# Milestone 14 — Verify Reset Uses Each Arena's Own Initial Position

This is particularly important with multiple instances.

Arena 0 might begin at:

```text
(0, 0, 0)
```

while Arena 20 might begin at:

```text
(48, 0, 36)
```

`BalanceEpisode` already captures the initial physical-body transforms.

Verify that resetting arena 20 restores it to arena 20's own location and does not move it toward the origin.

Also verify its:

```text
maximum_distance
```

is measured relative to that arena's own initial pelvis position.

---

# Milestone 15 — Add Batched Observation Collection

The training manager should be able to produce:

```text
observations[arena_index]
```

Conceptually:

```gdscript
func get_observations() -> Array:
    var result := []

    for arena in arenas:
        result.append(arena.get_observation())

    return result
```

Later this can map naturally to a Python tensor shaped something like:

```text
[num_arenas, observation_size]
```

Do not concatenate all arenas into one logical observation.

Each arena represents an independent environment.

---

# Milestone 16 — Add Batched Action Distribution

Likewise expose:

```text
actions[arena_index]
```

Conceptually:

```gdscript
func apply_actions(actions) -> void:
    assert(actions.size() == arenas.size())

    for i in arenas.size():
        arenas[i].apply_action(actions[i])
```

This is the interface the future RL bridge should use.

---

# Milestone 17 — Handle Episodes Individually

Do not reset every arena when one character falls.

Example:

```text
Arena 0 → still balancing
Arena 1 → falls
Arena 2 → still balancing
Arena 3 → timeout
```

Only reset:

```text
Arena 1
Arena 3
```

The others continue their episodes.

This independence is important for efficient parallel training.

---

# Milestone 18 — Expose Per-Arena Terminal State

The manager should be able to collect:

```text
failed[]
timed_out[]
```

For example:

```text
arena 0:
    failed = false
    timed_out = false

arena 1:
    failed = true
    timed_out = false

arena 2:
    failed = false
    timed_out = true
```

Do not collapse timeout and failure into the same signal internally.

Later:

```text
failed     → RL terminated
timed_out  → RL truncated
```

---

# Milestone 19 — Prepare Gravity Curriculum Per Arena

Initially it is okay to set every arena to the same gravity:

```text
0.1
```

But design the API so each arena can eventually have a different gravity.

Example:

```text
Arena 0 = 0.25
Arena 1 = 0.25
Arena 2 = 0.30
Arena 3 = 0.20
```

This enables later curriculum/randomization without changing architecture.

For now the training manager may expose:

```text
set_all_gravity_scale(scale)
```

while the actual value remains stored per arena.

---

# Milestone 20 — Starting Gravity Curriculum

Support a simple manually controlled curriculum.

Possible stages:

```text
0.10
0.20
0.35
0.50
0.70
0.85
1.00
```

Do not implement automatic promotion yet unless needed.

For the first RL experiment:

```text
start around 0.1–0.2
```

to verify that the policy can learn anything at all.

Then increase gravity fairly quickly.

The actual target remains:

```text
1.0 gravity
10 second survival
```

Reduced gravity is only a learning aid.

---

# Milestone 21 — Create a Minimal Multi-Arena Test Scene

Create something like:

```text
balance_training.tscn
```

Containing:

```text
BalanceTrainingScene
├── BalanceTrainingManager
├── WorldEnvironment
└── optional lighting
```

The manager instantiates the arena scene.

No camera is required for headless training.

A camera can be added temporarily when visually inspecting multiple arenas.

Do not make rendering a dependency of the training simulation.

---

# Milestone 22 — Add a Small Parallel Simulation Test

Before RL, instantiate for example:

```text
4 arenas
```

Give them different gravity:

```text
Arena 0 = 0.1
Arena 1 = 0.3
Arena 2 = 0.6
Arena 3 = 1.0
```

Run all simultaneously.

Verify:

```text
✓ every arena simulates

✓ every arena has its own observation

✓ gravity differs correctly

✓ resetting one does not reset others

✓ one ragdoll cannot collide with another

✓ timeout is tracked independently

✓ failure is tracked independently
```

---

# Milestone 23 — Test 60 Hz Action Timing

Add a test counter.

Over:

```text
240 physics ticks
```

there should be exactly:

```text
60 policy steps
```

Over:

```text
960 physics ticks
```

there should be exactly:

```text
240 policy steps
```

The action should remain unchanged for the four physics frames between decisions.

---

# Milestone 24 — Keep Target Smoothing at Physics Rate

Do not move `RagdollTargetController` to 60 Hz.

The structure should be:

```text
POLICY
60 Hz
   |
   | new target
   v
BalanceController
   |
   v
RagdollTargetController
240 Hz smoothing
   |
   v
PD Controller
240 Hz
   |
   v
Physics
240 Hz
```

This is desirable.

The network decides relatively slowly while the physical controller remains responsive.

---

# Milestone 25 — Do Not Add Reward Yet

At the end of this milestone, stop before implementing PPO.

The environment infrastructure should first prove that:

```text
many arenas can run

observations can be collected

actions can be distributed

policy steps occur at 60 Hz

gravity can be configured

episodes can reset independently
```

Then add the reward function.

---

# Final Structure

```text
balance_training.tscn
│
├── BalanceTrainingManager
│
├── Arena 0
│   └── BalanceTrainingArena
│
├── Arena 1
│   └── BalanceTrainingArena
│
├── Arena 2
│   └── BalanceTrainingArena
│
└── ...
```

Each:

```text
BalanceTrainingArena
│
├── finite Ground
├── ActiveRagdoll
├── BalanceStateProvider
├── BalanceController
└── BalanceEpisode
```

Control timing:

```text
Physics
240 Hz

Target smoothing
240 Hz

PD
240 Hz

RL policy
60 Hz
    =
new action every 4 physics ticks
```

---

# Stop Point

Stop when all of the following work:

```text
✓ current test simulation extracted into reusable arena scene

✓ arena owns one isolated ragdoll environment

✓ finite ground replaces duplicated infinite boundaries

✓ gravity_scale belongs to environment/arena, not BalanceController

✓ gravity can be independently changed per arena

✓ manual gravity testing uses the same arena API

✓ multi-arena manager exists

✓ arenas spawn in a spaced grid

✓ at least 4 arenas simulate simultaneously

✓ observations can be gathered per arena

✓ actions can be supplied per arena

✓ one arena can reset without affecting another

✓ timeout/failure remain independent per arena

✓ physics remains 240 Hz

✓ policy cadence is exactly 60 Hz

✓ each action is held for exactly 4 physics ticks

✓ target smoothing and PD remain at 240 Hz

✓ automated tests pass
```

## Next Step After This

Once this infrastructure works, the next milestone should be:

```text
simple standing reward
        ↓
Python/Godot RL bridge
        ↓
PPO
        ↓
train multiple arenas in parallel
        ↓
gravity curriculum toward 1.0 g
```