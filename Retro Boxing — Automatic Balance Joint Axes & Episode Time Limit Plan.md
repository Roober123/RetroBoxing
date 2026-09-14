# Retro Boxing — Automatic Balance Joint Axes & Episode Time Limit Plan

## Goal

Prepare the current balance system for RL by:

1. Automatically deriving useful rotation axes from the actual `PhysicalBone3D` joints instead of hardcoding `Vector3.RIGHT`, `UP`, or `FORWARD`.
2. Verifying that the generated balance actions move the intended joints correctly.
3. Adding a 10-second episode time limit.

Do **not** add rewards, PPO, curriculum, boxing stance, walking, punching, or other RL functionality yet.

---

# Milestone 1 — Remove Hardcoded Anatomical Axes

## Current Problem

`BalanceController` currently assumes things such as:

```text
pitch → local X
roll  → local Z
```

This makes the controller depend on how a particular imported skeleton happens to orient its bones.

Instead, the physical ragdoll should provide the axes.

`BalanceController` should only know things such as:

```text
left hip:
    bend forward/backward
    bend sideways

left knee:
    bend

left ankle:
    bend forward/backward
    tilt sideways
```

It should not need to know whether those movements happen around local X, Y, or Z.

---

# Milestone 2 — Add a Joint Axis Resolver

Create a small helper responsible for inspecting the physical ragdoll once during initialization.

For example:

```text
BalanceJointAxisResolver
```

Its input should be:

```text
Skeleton3D
PhysicalBoneSimulator3D
PhysicalBone3D nodes
reference/rest pose
```

Its output should be resolved rotation axes for the balance joints.

Conceptually:

```text
left hip:
    pitch_axis
    roll_axis

right hip:
    pitch_axis
    roll_axis

left knee:
    flexion_axis

right knee:
    flexion_axis

left ankle:
    pitch_axis
    roll_axis

right ankle:
    pitch_axis
    roll_axis

spine:
    pitch_axis
    roll_axis
```

Resolve these once.

Do not recalculate them every physics frame.

---

# Milestone 3 — Scan Physical Bone and Joint Frames

For every controlled `PhysicalBone3D`, gather:

```text
bone name
bone id
parent bone
child bone(s)

reference/rest transform
physical body transform
joint_offset
joint_rotation
joint type
joint constraint information
```

The resolver should primarily use the **joint frame**, because that represents how the physical connection itself is oriented.

The skeleton/rest-pose geometry should then be used to determine which of the joint-frame axes corresponds to the desired movement.

Do not assume skeleton-local X/Y/Z directly represent anatomical axes.

---

# Milestone 4 — Determine Segment Directions

For each relevant body, derive its reference segment direction.

For example:

```text
upper leg direction:
    hip → knee

lower leg direction:
    knee → ankle

foot direction:
    ankle → toe

spine direction:
    pelvis → upper spine
```

Use reference/rest positions so the result is deterministic.

Normalize these directions.

These directions provide enough geometry to decide what "forward bending" and "sideways bending" mean relative to the actual skeleton.

---

# Milestone 5 — Build a Character Reference Frame

Determine the reference character directions once:

```text
up
forward
right
```

Prefer deriving them from the ragdoll/skeleton reference pose rather than assuming the imported bones use specific local axes.

For the current upright training character:

```text
up
    roughly pelvis → head

right
    roughly left hip → right hip

forward
    right × up
```

Normalize and orthogonalize the resulting basis.

This gives the resolver a stable anatomical character frame.

---

# Milestone 6 — Resolve Hip Axes Automatically

The hip is a multi-axis joint.

Desired actions are:

```text
hip pitch
    leg forward/back

hip roll
    leg sideways
```

Determine candidate rotation axes from the hip physical joint frame.

For each candidate joint axis, determine what movement it causes to the upper-leg direction.

Choose:

```text
pitch axis
    axis whose rotation moves the thigh most strongly
    in the character forward/back plane

roll axis
    axis whose rotation moves the thigh most strongly
    sideways
```

Store those axes in the coordinate space expected by `RagdollTargetController`.

Do this independently for left and right hips.

The resulting axes may have opposite signs because the skeleton is mirrored.

That is acceptable.

---

# Milestone 7 — Resolve Knee Flexion Axis Automatically

For the knee:

```text
upper segment = hip → knee
lower segment = knee → ankle
```

The knee bending plane can be derived from those segment directions and the character reference frame.

Select the joint-frame axis that best represents rotation of the lower leg within the natural forward/back bending plane.

The resolver should output:

```text
knee.flexion_axis
```

Also determine the sign corresponding to natural knee flexion.

Store:

```text
flexion_sign
```

so the action interface does not need to care about left/right bone orientation.

---

# Milestone 8 — Prevent Knee Hyperextension

Once the resolver knows the natural flexion direction, change knee action semantics.

Instead of:

```text
-35° ... +35°
```

represent:

```text
action = -1
    approximately straight knee

action = +1
    maximum permitted flexion
```

The exact flexion range can remain simple for now.

Example:

```text
0° ... 35°
```

or whatever range works comfortably with the reference pose.

The RL agent should not be given useful backwards knee bending as an action.

---

# Milestone 9 — Resolve Ankle Axes Automatically

Use:

```text
lower leg direction:
    knee → ankle

foot direction:
    ankle → toe
```

Desired actions:

```text
ankle pitch:
    toes up/down

ankle roll:
    sole tilts side-to-side
```

Inspect the ankle physical joint frame.

For each candidate joint-frame axis, evaluate how rotating the reference foot direction around it would move the foot.

Choose:

```text
pitch axis
    best matches toe up/down movement

roll axis
    best matches side-to-side sole tilt
```

Do this independently for both ankles.

Store resolved axis and sign information.

---

# Milestone 10 — Resolve Spine Axes Automatically

Use the character reference frame and spine direction.

Desired actions:

```text
spine pitch:
    torso forward/back

spine roll:
    torso sideways
```

Inspect the spine joint frame.

Choose:

```text
pitch axis
    produces forward/back torso bending

roll axis
    produces sideways torso bending
```

Avoid selecting the axis that predominantly produces vertical-axis torso twist.

Twist/yaw is not part of the initial balance action space.

---

# Milestone 11 — Keep BalanceController Simple

`BalanceController` should consume the resolved configuration rather than deciding axes itself.

Conceptually:

```text
BalanceJointAxes
    left_hip_pitch_axis
    left_hip_roll_axis

    right_hip_pitch_axis
    right_hip_roll_axis

    left_knee_axis
    right_knee_axis

    left_ankle_pitch_axis
    left_ankle_roll_axis

    right_ankle_pitch_axis
    right_ankle_roll_axis

    spine_pitch_axis
    spine_roll_axis
```

Then:

```text
normalized action
    ↓
angle limit
    ↓
resolved axis
    ↓
Quaternion(axis, angle)
```

`BalanceController` remains an action mapper.

It should still contain no actual balancing intelligence.

---

# Milestone 12 — Resolve Once and Print the Result

When the training scene starts, resolve all axes once.

In debug builds, print a compact summary such as:

```text
Balance joint axes:

LeftHip
    pitch: (...)
    roll:  (...)

RightHip
    pitch: (...)
    roll:  (...)

LeftKnee
    flexion: (...)

LeftAnkle
    pitch: (...)
    roll:  (...)

Spine
    pitch: (...)
    roll: (...)
```

Also print any detected sign inversion.

This makes problems easy to inspect without putting axis knowledge into the controller.

---

# Milestone 13 — Add Resolver Sanity Checks

The resolver should detect obviously invalid results.

Examples:

```text
axis length approximately 1

pitch and roll axes are not nearly parallel

left/right joints were successfully found

required parent/child bones exist

foot direction is valid

spine direction is valid
```

If resolution fails, produce a clear error containing the bone name.

Do not silently fall back to arbitrary hardcoded axes.

---

# Milestone 14 — Add a Gravity-Free Verification Mode

Even with automatic resolution, perform one visual verification of the resolver.

Add a debug-only option to the balance test scene that temporarily sets:

```gdscript
physical_bone.gravity_scale = 0.0
```

for the ragdoll.

This must remain test/debug functionality.

Do not add it to normal `ActiveRagdoll` behavior.

---

# Milestone 15 — Automatically Cycle Through Actions

Improve `balance_manual_test.gd` or add a tiny dedicated test.

Allow cycling through:

```text
left hip pitch
left hip roll
right hip pitch
right hip roll
left knee
right knee
left ankle pitch
left ankle roll
right ankle pitch
right ankle roll
spine pitch
spine roll
```

For each action allow:

```text
-1
0
+1
```

The resolver decides the axis.

The user should only need to verify that the resulting anatomical movement makes sense.

---

# Milestone 16 — Visual Verification

The expected results are:

```text
hip pitch
    thigh forward/back

hip roll
    thigh sideways

knee
    natural knee bend

ankle pitch
    toes up/down

ankle roll
    sole side-to-side

spine pitch
    torso forward/back

spine roll
    torso sideways
```

If any of these are wrong, fix the **axis resolver**.

Do not patch that individual joint inside `BalanceController` with a manually chosen X/Y/Z axis.

That keeps skeleton-specific interpretation in one place.

---

# Milestone 17 — Restore Gravity and Check Control Authority

Restore:

```text
gravity_scale = 1
```

Run the normal balance scene.

Try:

```text
both ankle pitch
both hip pitch
hip roll
knee flexion
spine pitch
```

Confirm that changing the target rotations causes a noticeable physical response.

The character does not need to remain standing manually.

The test only needs to establish:

> The resolved action space can meaningfully influence the body's balance.

---

# Milestone 18 — Add Episode Time Tracking

Extend `BalanceEpisode`.

Add:

```text
elapsed_time
maximum_episode_duration
```

Start with:

```text
maximum_episode_duration = 10.0 seconds
```

On reset:

```text
elapsed_time = 0
```

Advance the timer using physics delta.

Do not derive episode duration from an assumed number of frames.

Physics currently runs at 240 Hz, but the episode timer should remain correct if that changes later.

---

# Milestone 19 — Separate Failure From Timeout

Keep failure detection separate from reaching the time limit.

Conceptually:

```gdscript
func has_failed() -> bool:
    return (
        pelvis_too_low
        or head_too_low
        or pelvis_tilt_too_large
        or moved_too_far
    )

func has_timed_out() -> bool:
    return elapsed_time >= maximum_episode_duration

func is_terminal() -> bool:
    return has_failed() or has_timed_out()
```

This matters later because:

```text
falling
```

and:

```text
surviving the entire episode
```

should not be treated identically by the RL training code.

---

# Milestone 20 — Reset Tests

Extend the existing balance preparation tests.

After reset verify:

```text
elapsed_time == 0

action vector == neutral

joint targets == neutral

physical velocities == zero
```

Test:

```text
reset
simulate
reset
simulate
reset
```

and confirm no state leaks between episodes.

---

# Milestone 21 — Automated Resolver Tests

Add structural tests for the automatic axis system.

Verify:

```text
all required balance joints resolve

all resolved axes are normalized

two-axis joints receive two non-parallel axes

left/right counterparts resolve

knee flexion direction is defined

ankle pitch and roll differ

spine pitch and roll differ

no balance action relies on a hardcoded skeleton-local X/Y/Z choice
```

Do not attempt to automatically test whether a movement "looks human."

That final semantic check remains a small visual validation.

---

# Final Architecture

```text
Physical Skeleton
      |
      | rest transforms
      | physical bones
      | joint frames
      | hierarchy
      v
BalanceJointAxisResolver
      |
      | resolved anatomical axes
      v
BalanceController
      |
      | 12 bounded target actions
      v
RagdollTargetController
      |
      v
ActiveRagdollPD3D
      |
      v
Physical Ragdoll
```

Alongside:

```text
BalanceEpisode
      |
      +-- failure detection
      +-- elapsed time
      +-- 10 second timeout
```

---

# Keep the Existing 12 Actions

Do not change the action count yet.

```text
left_hip_pitch
left_hip_roll

right_hip_pitch
right_hip_roll

left_knee_flexion
right_knee_flexion

left_ankle_pitch
left_ankle_roll

right_ankle_pitch
right_ankle_roll

spine_pitch
spine_roll
```

The difference is that these actions now describe **anatomical intent**, while their actual quaternion axes come from the physical ragdoll.

---

# Stop Point

Stop when:

```text
✓ BalanceController contains no skeleton-specific axis assumptions

✓ physical bones and their joint frames are scanned automatically

✓ character forward/right/up reference frame is derived

✓ hip axes are resolved

✓ knee flexion axes and signs are resolved

✓ ankle axes are resolved

✓ spine axes are resolved

✓ knee hyperextension is not exposed as a useful action

✓ all 12 actions visually produce the expected movement

✓ normal-gravity actions visibly affect the ragdoll

✓ episode time is tracked

✓ reset clears episode time

✓ timeout occurs at 10 seconds

✓ failure and timeout can be distinguished

✓ automated tests pass
```

After this, move on to:

```text
fixed RL policy frequency
reward function
PPO integration
standing-balance training
```