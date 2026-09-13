# Retro Boxing — RL Balance Preparation Plan

## Goal

Prepare the current active ragdoll system so it is ready to later train an RL balance policy.

The first future learning task will simply be:

> Keep the ragdoll upright.

This plan does **not** implement or design the RL training itself.

Do not work on:

- rewards;
- PPO or another algorithm;
- training framework integration;
- curriculum;
- boxing stance learning;
- punching;
- walking;
- dodging;
- hand tracking.

The objective of this plan is only to leave the project with a clean physical character and a clear interface that an RL system can later use.

The existing low-level architecture remains:

```text
Target Rotation
      ↓
ActiveRagdollPD3D
      ↓
PD Torque
      ↓
PhysicsServer3D.body_apply_torque()
      ↓
PhysicalBone3D
```

Physics should run at:

```text
240 Hz
```

The high physics frequency is intentional for active-ragdoll stability.

---

# Milestone 1 — Clean Up `ActiveRagdoll`

The current `active_ragdoll.gd` still contains code that was useful while developing and testing the PD system but should not belong to the reusable ragdoll.

## Remove Temporary Pose Generation

Remove:

```text
test_pose
boxing_pose
make_pose()
```

The active ragdoll should not contain knowledge about:

```text
test poses
boxing poses
guards
punches
balance behavior
```

These will belong to higher-level systems later.

---

## Use the Skeleton Starting Pose as the Base Pose

Do not create a separate standing/base pose.

The physical skeleton's initial configuration is the reference pose for the first balance experiments.

Conceptually:

```text
Skeleton starting pose
        ↓
captured PD reference pose
        ↓
zero target offset
```

Therefore the neutral target remains:

```text
Quaternion.IDENTITY
```

for every controlled joint.

Future RL actions will provide small offsets from this starting configuration.

---

## Remove Automatic Debug Target Setup

Remove automatic creation of:

```text
ragdoll_debug_targets.gd
```

from `ActiveRagdoll`.

Debug visualization should belong to the test/training scene.

The active ragdoll itself should not care whether debugging is enabled.

---

## Remove Gravity Isolation From `ActiveRagdoll`

Remove:

```text
isolate_gravity
```

and the associated code that changes `gravity_scale`.

The runtime active ragdoll should behave normally under gravity.

Any isolated PD tests that require gravity disabled should configure that explicitly from the test code.

---

## Keep `ActiveRagdoll` Small

Its responsibilities should become approximately:

```text
ActiveRagdoll
    |
    +-- obtain skeleton / physical bone simulator
    |
    +-- initialize ActiveRagdollPD3D
    |
    +-- discover controlled joints
    |
    +-- capture reference pose
    |
    +-- configure PD body profiles
    |
    +-- initialize RagdollTargetController
    |
    +-- start physical simulation
```

The ragdoll should not contain balance logic.

---

## Verify

After cleanup:

- the ragdoll loads normally;
- all expected joints are discovered;
- the hips/root remain uncontrolled;
- body profiles still work;
- the target controller initializes with neutral offsets;
- gravity works normally;
- the ragdoll falls naturally if it cannot maintain itself;
- existing low-level PD tests remain valid.

---

# Milestone 2 — Convert the Existing Test Scene Into the Balance/Training Scene

Do not create another separate scene unnecessarily.

The existing active-ragdoll test scene can evolve into the future training environment.

Its purpose becomes:

> A minimal sandbox in which the ragdoll can later be controlled by an RL agent.

Keep the scene simple.

Conceptually:

```text
Ragdoll Test / Training Scene
|
+-- Floor
|
+-- ActiveRagdoll
|
+-- BalanceStateProvider
|
+-- BalanceController
|
+-- BalanceEpisode
|
+-- optional debug visualization
```

This scene is where future RL integration will happen.

The actual game scene should remain separate.

---

# Milestone 3 — Confirm the Initial Physical Pose

The ragdoll should start from the skeleton's existing pose.

Do not procedurally create a standing pose.

Do not create a `StandingPose` resource.

Do not modify the skeleton specifically for RL unless the existing starting pose is physically unusable.

The expected initial setup is simply:

```text
skeleton initial transforms
        ↓
physical bones initialized
        ↓
PD reference captured
        ↓
all target offsets = identity
```

The hips/root remain free.

There must be no artificial root controller keeping the character upright.

---

# Milestone 4 — Add `BalanceStateProvider`

Create a component such as:

```text
BalanceStateProvider
```

Its purpose is to expose the physical state of the ragdoll in a clean and reusable form.

It should contain no decision-making and no RL-specific code.

Later an RL environment will read this state.

---

## Pelvis State

Expose at least:

```text
pelvis orientation
pelvis angular velocity
pelvis linear velocity
pelvis height
```

Useful orientation representations include:

```text
pelvis up vector
pelvis forward vector
```

Avoid making observations dependent on absolute world heading where possible.

---

## Joint State

For relevant joints expose:

```text
relative joint rotation
relative angular velocity
```

Use the same deterministic joint ordering already provided by the PD controller.

This is important because future observation and action arrays need stable indexing.

---

## Foot State

Expose simple information for both feet:

```text
left foot position relative to pelvis
right foot position relative to pelvis

left foot contact
right foot contact
```

Use a simple and reliable contact check.

Do not build sophisticated foot-pressure simulation yet.

---

## Center of Mass

Calculate approximate whole-body center of mass using physical-bone masses.

Expose:

```text
COM position relative to pelvis
COM velocity
```

Also calculate a simple support reference:

```text
support center =
midpoint between left and right foot
```

Then expose:

```text
horizontal COM offset from support center
```

Do not implement a full support polygon yet.

---

# Milestone 5 — Add `BalanceController`

Create:

```text
BalanceController
```

This component becomes the high-level action interface.

It should not know whether its commands come from:

```text
keyboard
debug tools
RL
future gameplay controller
```

Its job is simply:

```text
normalized control values
        ↓
joint target offsets
        ↓
RagdollTargetController
```

---

## Actions Control Target Rotations

The future RL policy should not directly output torques.

The final architecture remains:

```text
future RL action
      ↓
BalanceController
      ↓
small quaternion target offsets
      ↓
RagdollTargetController
      ↓
ActiveRagdollPD3D
      ↓
PhysicsServer3D.body_apply_torque()
```

The PD controller remains the actuator.

---

# Milestone 6 — Define the Initial Balance Action Set

Do not expose all 19 controlled joints immediately.

Create an explicit list of joints intended for balance control.

Start around:

```text
LeftUpLeg
RightUpLeg

LeftLeg
RightLeg

LeftFoot
RightFoot

Spine
```

Possibly add another spine joint later if required.

The arms, hands, neck and head can remain at zero target offset.

---

## Restrict Useful Degrees of Freedom

Do not automatically provide arbitrary XYZ control for every joint.

Define useful axes explicitly.

Example:

```text
hips
    pitch
    roll

knees
    flexion

ankles
    pitch
    roll

spine
    pitch
    roll
```

Yaw can be introduced later if it proves necessary.

The result should be a relatively small, understandable action vector.

---

## Normalize the Interface

`BalanceController` should accept values such as:

```text
-1 ... +1
```

and map them into bounded angular offsets.

For example:

```text
hip     → limited residual rotation
knee    → limited flexion offset
ankle   → limited pitch/roll
spine   → small limited correction
```

Exact angle ranges can be tuned later.

The important part now is that the interface exists and remains bounded.

---

# Milestone 7 — Connect Balance Actions to `control_offset`

Reuse the existing:

```text
RagdollTargetController
```

and its:

```text
control_offset
```

architecture.

Because the skeleton starting pose is already the reference pose:

```text
base target = identity
```

Balance control becomes:

```text
identity/reference pose
        *
balance residual
        ↓
final PD target
```

The future policy therefore learns only deviations from the physical character's original pose.

Do not add another pose layer for this stage.

---

# Milestone 8 — Add Manual Action Testing

Before RL integration exists, provide a simple way to drive `BalanceController`.

This can be:

```text
keyboard controls
debug sliders
small debug script
```

The goal is not to manually balance the character successfully.

The goal is to verify that each action produces a sensible physical response.

Examples:

```text
ankle pitch
    → body lean changes

hip roll
    → lateral COM movement

knee flexion
    → body height changes

spine pitch
    → torso mass shifts
```

Check every exposed action individually.

If an action does not meaningfully influence the body, fix the action mapping before RL work begins.

---

# Milestone 9 — Add Reliable Episode Reset

Create a small component such as:

```text
BalanceEpisode
```

It should be able to reset the complete physical system.

This is required before any future RL training.

Store the initial state of each relevant `PhysicalBone3D`.

A reset should restore:

```text
physical bone transforms
linear velocities
angular velocities
PD target offsets
BalanceController action state
```

The ragdoll should return to the same initial physical configuration.

The result should conceptually be:

```text
reset
  ↓
same skeleton pose
  ↓
zero velocities
  ↓
zero control residuals
  ↓
physics resumes
```

---

## Verify Reset Stability

Repeatedly:

```text
reset
wait briefly
reset
wait briefly
reset
```

Verify:

- no accumulated velocity;
- no position drift between resets;
- no stale target rotations;
- no explosive joint correction;
- no bodies remain sleeping incorrectly;
- the starting configuration is repeatable.

This is one of the most important prerequisites for future RL training.

---

# Milestone 10 — Add Simple Episode Termination Detection

Prepare a function that determines whether the character has clearly fallen.

Do not design rewards.

Only prepare basic termination information.

Possible conditions:

```text
pelvis below minimum height
head below minimum height
pelvis excessively tilted
body moved extremely far from start
```

Expose something conceptually similar to:

```text
is_fallen()
```

or:

```text
is_terminal()
```

The exact thresholds can be tuned later during RL work.

---

# Milestone 11 — Add a Clean RL-Facing Environment Interface

Do not connect an RL library yet.

Simply expose the operations that a future integration will need.

Conceptually:

```text
reset()
get_observation()
apply_action(action)
is_terminal()
```

These can delegate to:

```text
BalanceEpisode
BalanceStateProvider
BalanceController
```

Do not add:

```text
get_reward()
training loops
network inference
PPO
Python communication
```

yet.

The objective is only to make the Godot side clean enough that those systems can later be attached without restructuring the ragdoll.

---

# Milestone 12 — Configure Physics for Training Preparation

Set the project physics tick rate to:

```text
240 Hz
```

The PD motor should execute every physics tick.

For now there is no RL policy update frequency because RL integration is outside this plan.

Future architecture may eventually look like:

```text
RL Policy       lower frequency
     ↓
BalanceController
     ↓
RagdollTargetController
     ↓
ActiveRagdollPD3D
     ↓
Physics         240 Hz
```

But do not implement the policy scheduling yet.

---

# Final Prepared Architecture

```text
              FUTURE RL POLICY
                     |
                normalized actions
                     |
                     v
              BalanceController
             - bounded actions
             - DOF mapping
             - quaternion offsets
                     |
                     v
                control_offset
                     |
                     v
          RagdollTargetController
              - target smoothing
              - target velocity
                     |
                     v
            ActiveRagdollPD3D
              - PD calculation
              - torque limiting
                     |
                     v
    PhysicsServer3D.body_apply_torque()
                     |
                     v
               PhysicalBone3D
                     |
                     |
       +-------------+-------------+
       |                           |
       v                           v
BalanceStateProvider         BalanceEpisode
- pelvis                    - reset
- joints                    - fall detection
- feet                      - episode state
- COM
       |
       v
 FUTURE RL OBSERVATION
```

---

# Final Stop Point

Stop before implementing RL.

The project is ready for the next phase when:

```text
✓ ActiveRagdoll contains only reusable ragdoll/PD setup
✓ temporary test/boxing pose generation is removed
✓ gravity-isolation logic is removed from ActiveRagdoll
✓ debug visualization is owned by the test/training scene
✓ skeleton starting pose is used as the reference pose
✓ physics runs at 240 Hz
✓ existing test scene acts as the balance/training sandbox
✓ BalanceStateProvider exposes useful physical state
✓ COM can be calculated
✓ foot contacts can be queried
✓ BalanceController exposes a small bounded action vector
✓ actions become quaternion control offsets
✓ action effects can be tested manually
✓ the ragdoll can be reliably reset
✓ basic fall/termination detection exists
✓ reset / observation / action / terminal interfaces are available
```

At that point, stop.

The next separate phase can decide:

```text
RL framework
training process
reward function
policy frequency
curriculum
randomization
```

without needing to redesign the active-ragdoll architecture.