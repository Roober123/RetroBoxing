# Retro Boxing — Active Ragdoll Refinement Plan

## Goal

Refine the current working PD controller into a stable full-body actuator system that can later support:

- boxing stances;
- learned balance;
- hand targeting;
- punches;
- torso dodging;
- RL residual control.

The current PD architecture should remain intact:

```text
Quaternion target
      ↓
ActiveRagdollPD3D
      ↓
PD torque
      ↓
PhysicsServer3D.body_apply_torque()
      ↓
PhysicalBone3D
```

The next phase focuses on:

1. body profiles;
2. full-body pose holding;
3. PD tuning;
4. smooth target transitions;
5. preparing pose composition for future RL.

---

# Milestone 1 — Body Profiles

The current system uses the same PD parameters for every controlled joint.

Replace this with a simple **body profile API**.

A profile is not a separate object or Resource.

It is simply a function call containing:

```text
Array of bone names
response_frequency
damping
max_torque
```

Conceptually:

```gdscript
set_body_profile(
    bones: Array[StringName],
    response_frequency: float,
    damping: float,
    max_torque: float
)
```

Example:

```gdscript
set_body_profile(
    [
        &"mixamorig_LeftArm",
        &"mixamorig_LeftForeArm",
        &"mixamorig_RightArm",
        &"mixamorig_RightForeArm"
    ],
    arm_frequency,
    arm_damping,
    arm_max_torque
)
```

Then another call can configure the legs:

```gdscript
set_body_profile(
    [
        &"mixamorig_LeftUpLeg",
        &"mixamorig_LeftLeg",
        &"mixamorig_RightUpLeg",
        &"mixamorig_RightLeg"
    ],
    leg_frequency,
    leg_damping,
    leg_max_torque
)
```

Recommended initial groups:

```text
arms
spine
legs
feet
neck/head
```

Do not create a complicated profile inheritance or Resource system yet.

The purpose of the profile function is only:

> Apply the same physically meaningful motor parameters to a group of joints.

---

## Frequency-Based PD Parameters

The external tuning API should use:

```text
response_frequency
damping
max_torque
```

rather than asking gameplay code to directly choose arbitrary `Kp` and `Kd`.

Internally, the PD controller can convert these parameters into gains.

Conceptually:

```text
response_frequency
        ↓
        ω

effective rotational inertia
        ↓

Kp ≈ I_eff * ω²

Kd ≈ 2 * damping * I_eff * ω
```

Where:

```text
response_frequency
```

controls how quickly the joint tries to reach its target.

```text
damping
```

controls oscillation / overshoot.

```text
max_torque
```

limits the physical strength of the motor.

The first implementation does not need perfect inertia estimation if that makes the system significantly more complicated.

The important architectural requirement is that body profiles already expose:

```text
frequency
damping
max torque
```

so inertia-aware tuning can improve internally later without changing the external API.

---

## Profile Ownership

Keep profile setup outside the low-level PD calculation.

For example:

```text
ActiveRagdoll
      ↓
configure body groups
      ↓
ActiveRagdollPD3D
```

The PD controller should expose a function capable of configuring multiple bones.

It should not contain knowledge such as:

```text
"these are arms"
"these are legs"
```

The caller provides the bone array.

This keeps the GDExtension reusable.

---

## Verify

Enable every motor except the hips/root.

Initially use gravity disabled or otherwise isolate the PD behavior.

Verify:

- every requested bone receives the profile;
- invalid bone names produce a useful error;
- joints outside the provided array are unchanged;
- all controlled joints remain finite;
- no region violently oscillates;
- changing response frequency clearly changes responsiveness;
- increasing damping reduces oscillation;
- `max_torque` visibly limits motor authority.

Stop here if the complete body becomes unstable.

---

# Milestone 2 — Full-Body Test Pose

Create one intentional whole-body pose.

Do not start with balance.

Do not start with punching.

Use a simple pose such as:

```text
slightly bent knees
slightly bent elbows
arms somewhat forward
small torso bend
```

Store the target using the existing `RagdollPose` concept.

Architecture:

```text
RagdollPose
      ↓
joint quaternion targets
      ↓
ActiveRagdollPD3D
```

For this test either:

```text
disable gravity
```

or temporarily support the pelvis.

The purpose is to isolate joint control from balance.

---

## Verify

The entire body should converge toward the requested pose.

Success means:

- the pose is recognizable;
- limbs reach approximately the intended orientation;
- there is little continuous shaking;
- the pose remains stable for several seconds;
- no body receives unrealistic infinite or extremely large torque.

---

# Milestone 3 — Tune Body Profiles

Tune the profiles one region at a time.

Recommended order:

```text
1. arms
2. spine
3. legs
4. feet
5. neck/head
```

For each region:

### Response Frequency

Increase until the body responds quickly enough.

Avoid making frequency unnecessarily high simply to force joints into place.

### Damping

Tune until:

```text
fast response
+
little overshoot
+
little sustained oscillation
```

### Maximum Torque

Limit the maximum torque so the motor remains physical.

The desired behavior is:

```text
strong enough to hold the pose
but
weak enough that collisions can move it
```

---

# Milestone 4 — Disturbance Testing

Once the full-body pose is stable, deliberately disturb it.

Apply torque impulses to:

```text
forearm
upper arm
thigh
torso
```

Expected behavior:

```text
external impulse
      ↓
joint leaves target
      ↓
PD reacts
      ↓
joint smoothly returns
```

Verify that:

- stronger impulses move the body further;
- motors do not completely cancel collisions;
- joints recover without large oscillations;
- the whole body remains stable;
- equal/opposite joint torque still behaves correctly.

Do not proceed until disturbance recovery looks believable.

---

# Milestone 5 — Target Smoothing Layer

The PD controller should continue accepting immediate quaternion targets.

Do not add interpolation inside the low-level PD controller.

Instead create a higher-level target controller:

```text
RagdollTargetController
```

Architecture:

```text
desired pose
      ↓
RagdollTargetController
      ↓
smoothed quaternion target
      ↓
ActiveRagdollPD3D
```

Its responsibility is to transition targets over time.

Use quaternion interpolation such as:

```text
slerp
```

rather than linearly interpolating quaternion components.

---

## Why

Changing a joint target instantly from:

```text
0°
```

to:

```text
90°
```

can immediately produce maximum motor torque.

Smoothing gives the PD controller a physically reasonable trajectory to follow.

This will matter later for:

- guards;
- punches;
- dodges;
- hand targeting.

---

# Milestone 6 — Target Angular Velocity

The PD controller already supports target angular velocity.

Use the movement of the smoothed target to determine the desired joint angular velocity.

Conceptually:

```text
previous quaternion
        +
current quaternion
        +
delta
        ↓
target angular velocity
```

Then pass:

```text
target rotation
target angular velocity
```

to the PD controller.

This means the motor knows the difference between:

```text
hold this orientation
```

and:

```text
move through this orientation at this speed
```

This becomes especially useful for fast boxing motions.

---

## Verify

Test the same quick arm movement twice:

```text
A. target angular velocity = zero
B. calculated target angular velocity
```

The second version should follow moving targets more naturally and require less brute-force positional correction.

---

# Milestone 7 — Boxing Stance

Once the generic test pose works, create the first actual boxing stance.

For example:

```text
knees slightly bent
feet planted
torso slightly forward
elbows bent
hands near the head
shoulders engaged
lead side slightly forward
```

Do not make the pelvis artificially upright.

The hips/root remain physically free.

The objective at this stage is only:

> Can the PD system reproduce and maintain the joint configuration of a boxing stance?

It does not need to balance itself yet.

---

# Milestone 8 — Pose Blending

Support transitions such as:

```text
neutral
   ↓
boxing stance
```

and later:

```text
boxing stance
   ↓
guard variation
```

Keep this system small.

Do not build a general animation graph.

Desired architecture:

```text
Pose A
Pose B
  ↓
pose interpolation
  ↓
RagdollTargetController
  ↓
ActiveRagdollPD3D
```

---

# Milestone 9 — Base Pose + Residual Control

Prepare the target system for future RL.

Final targets should support composition:

```text
final_target =
    base_pose
    *
    control_offset
```

Example:

```text
boxing_stance
      *
balance_adjustment
```

Later:

```text
boxing_stance
      *
RL residual
```

or:

```text
guard_pose
      *
hand_tracking_offset
```

The PD controller must not know where these targets came from.

Its input remains:

```text
target quaternion
target angular velocity
```

---

# Final Architecture

```text
        Gameplay / RL / IK
                |
                v
            Base Pose
                |
         Residual Offset
                |
                v
       Pose Composition
                |
                v
     RagdollTargetController
       - pose blending
       - target smoothing
       - angular velocity
                |
                v
        Quaternion Targets
                |
                v
       ActiveRagdollPD3D
       - rotation error
       - velocity error
       - frequency → gains
       - damping
       - torque limiting
                |
                v
 PhysicsServer3D.body_apply_torque()
      child +τ / parent -τ
                |
                v
          PhysicalBone3D
```

---

# Body Profile API Summary

The important configuration interface should remain very small:

```gdscript
set_body_profile(
    bones: Array[StringName],
    response_frequency: float,
    damping: float,
    max_torque: float
)
```

Typical setup:

```text
set_body_profile(arms, ...)
set_body_profile(spine, ...)
set_body_profile(legs, ...)
set_body_profile(feet, ...)
set_body_profile(neck, ...)
```

No dedicated `ArmProfile`, `LegProfile`, or other profile class is required.

The grouping exists only in the caller.

The PD controller simply receives:

```text
bone array
frequency
damping
max torque
```

and applies those settings to the requested joints.

---

# Stop Point Before Balance / RL

Do not begin learned balance until:

```text
✓ full-body motors work simultaneously
✓ body profiles work correctly
✓ frequency-based tuning behaves predictably
✓ damping produces stable joints
✓ maximum torque provides believable strength limits
✓ complete poses can be held
✓ collisions can displace the body
✓ joints recover after disturbances
✓ target smoothing works
✓ moving-target angular velocity works
✓ a boxing stance can be represented
✓ hips/root remain physically free
```

Once these are working, the actuator system is mature enough to start building the **balance layer** and eventually train an RL policy on top of it.