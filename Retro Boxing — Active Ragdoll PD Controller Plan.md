# Retro Boxing — Active Ragdoll PD Controller Plan

## Goal

Build a generic joint-space PD controller for the existing `PhysicalBone3D` ragdoll.

The controller should:

- keep the boxer completely physics driven;
- never directly set simulated bone transforms;
- produce torque from orientation and angular-velocity errors;
- accept parent-relative quaternion rotation targets;
- be independent from boxing/gameplay/RL logic;
- later support:
  - learned boxing stance;
  - learned balance;
  - hands following targets;
  - punches;
  - spine/torso dodging.

The project is already configured for **120 Hz physics**, so the PD controller should run once per physics tick at that rate.

---

# 1. Architecture

```text
                    TARGET SOURCES
                          |
          +---------------+----------------+
          |               |                |
      Debug Pose       Future RL       Future IK /
       / Stance          Agent          Gameplay
          |               |                |
          +---------------+----------------+
                          |
                 joint target rotations
                          |
                          v
                 ActiveRagdollPD3D
                    GDExtension C++
                          |
                    PD calculation
                          |
                    world torque
                          |
                          v
       PhysicsServer3D.body_apply_torque()
                          |
                          v
                   PhysicalBone3D
                          |
                          v
                     Jolt Physics
```

The PD controller should know nothing about:

- boxing stance;
- hand targets;
- dodging;
- punches;
- RL rewards.

Its only responsibility is:

> Given a physical joint and desired relative orientation, calculate and apply the torque needed to approach that orientation.

---

# 2. Target Rotation Convention

Targets should be **parent-relative rotations**.

Do not pass desired world rotations into the controller.

For every controlled joint:

```text
parent PhysicalBone3D
        |
       joint
        |
child PhysicalBone3D
```

Capture the relative rotation at initialization:

```text
reference_relative_rotation
```

A target quaternion represents an offset from this reference pose.

Therefore:

```text
Quaternion.IDENTITY
```

means:

> Hold the joint at its captured reference orientation.

The actual desired relative orientation becomes:

```text
q_desired =
    q_reference * q_target
```

This means the same pose remains meaningful regardless of whether the boxer:

- turns around;
- falls;
- leans;
- moves through the ring;
- gets hit.

---

# 3. Runtime Joint Structure

Use a lightweight C++ runtime structure rather than Nodes for every controller:

```cpp
struct PDJoint {
    StringName bone_name;

    PhysicalBone3D *child = nullptr;
    PhysicalBone3D *parent = nullptr;

    RID child_rid;
    RID parent_rid;

    Quaternion reference_relative_rotation;
    Quaternion target_rotation = Quaternion();

    Vector3 target_angular_velocity = Vector3();

    float stiffness = 0.0f;
    float damping = 0.0f;
    float max_torque = 0.0f;
    float strength = 1.0f;

    bool enabled = true;
};
```

Caching the body RIDs is useful because torque will ultimately be sent through `PhysicsServer3D`.

---

# 4. ActiveRagdollPD3D

Create:

```text
ActiveRagdollPD3D : Node
```

in:

```text
Addon/retro_boxing/src/active_ragdoll_pd.hpp
Addon/retro_boxing/src/active_ragdoll_pd.cpp
```

It should receive/reference:

```text
Skeleton3D
PhysicalBoneSimulator3D
```

and automatically build its list of controlled joints.

---

# 5. Initialization

Initialize the controller before starting ragdoll simulation.

High-level flow:

```text
ActiveRagdoll._ready()

    apply collision jitter fix

    pd_controller.initialize(
        skeleton,
        physical_bone_simulator
    )

    pd_controller.capture_reference_pose()

    physical_bones_start_simulation()

    pd_controller.enabled = true
```

Keep `active_ragdoll.gd` responsible for setup/orchestration.

Keep the actual PD implementation in C++.

---

# 6. Automatic Physical Bone Discovery

During initialization:

1. Iterate through children of `PhysicalBoneSimulator3D`.
2. Find every `PhysicalBone3D`.
3. Get its Skeleton bone ID.
4. Find its parent Skeleton bone.
5. Find the `PhysicalBone3D` belonging to that parent.
6. Build a `PDJoint`.
7. Cache both PhysicalBone RIDs.

Do not depend on Node names.

Use bone IDs internally.

Bone names should mainly exist for:

- debugging;
- editor-facing APIs;
- gameplay APIs.

---

# 7. Root / Pelvis

Do **not** drive the hips/root toward a world orientation.

The root has no physical parent and should remain a free rigid body.

```text
Hips:
    no orientation PD

All other controlled bones:
    relative joint PD
```

This becomes very important for RL balance.

Otherwise the controller would effectively cheat by applying an invisible upright motor to the entire character.

---

# 8. Orientation Error

For each joint obtain:

```text
q_parent_world
q_child_world
```

Compute current parent-relative orientation:

```text
q_current =
    inverse(q_parent_world)
    * q_child_world
```

Desired orientation:

```text
q_desired =
    q_reference
    * q_target
```

Compute error:

```text
q_error =
    q_desired
    * inverse(q_current)
```

Normalize the quaternion.

Force the shortest quaternion representation:

```text
if q_error.w < 0:
    q_error = -q_error
```

Then convert it into a rotation vector:

```text
rotation_error =
    axis * angle
```

Keep the angle on the shortest path.

---

# 9. Angular Velocity Error

Use the angular velocities of the two PhysicalBones.

Initially:

```text
relative_angular_velocity =
    child.angular_velocity
    - parent.angular_velocity
```

With a stationary target:

```text
target_angular_velocity =
    Vector3.ZERO
```

Therefore:

```text
angular_velocity_error =
    target_angular_velocity
    - relative_angular_velocity
```

Keep target angular velocity in the API even if it initially stays zero.

Later it can help with:

- fast punches;
- pose transitions;
- explicitly moving targets.

---

# 10. PD Torque

Calculate:

```text
torque =
    Kp * rotation_error
    +
    Kd * angular_velocity_error
```

Then:

```text
torque *= strength
```

and clamp:

```text
|torque| <= max_torque
```

`max_torque` should always exist.

The controller should not compensate for large errors by producing unlimited torque.

---

# 11. Apply Torque Through PhysicsServer3D

This should be the standard torque application path.

Do **not** change transforms.

Do **not** rotate the PhysicalBones manually.

Use:

```cpp
PhysicsServer3D::get_singleton()->body_apply_torque(
    body_rid,
    torque
);
```

or the equivalent Godot API binding.

The important rule is:

```text
PD calculates torque
        ↓
PhysicsServer3D.body_apply_torque()
        ↓
Jolt integrates the rigid body
```

The PD system should therefore operate using the `PhysicalBone3D` body RIDs.

---

# 12. Equal and Opposite Joint Torque

A joint motor acts internally between two rigid bodies.

For calculated world-space torque:

```text
child:
    +torque

parent:
    -torque
```

Use:

```cpp
PhysicsServer3D::get_singleton()->body_apply_torque(
    child_rid,
    torque
);

PhysicsServer3D::get_singleton()->body_apply_torque(
    parent_rid,
    -torque
);
```

This is preferable to applying torque only to the child.

It means the actuator behaves like a physical joint motor and does not simply create angular momentum from nowhere.

For example, rotating an arm should create an opposite reaction through the torso.

That will matter considerably for:

- punches;
- balance;
- dodging;
- recovering from impacts.

---

# 13. Coordinate Spaces

The clean pipeline should be:

```text
relative joint orientation
        ↓
joint/local orientation error
        ↓
convert error axis into world space
        ↓
world-space torque
        ↓
PhysicsServer3D.body_apply_torque()
```

Be very explicit about conversions between:

```text
Skeleton space
parent-body local space
child-body local space
world space
```

The final torque passed to `body_apply_torque()` should be in the appropriate world-space direction.

Do not fix space errors by arbitrarily negating individual axes.

---

# 14. Public API

Expose a readable API:

```text
set_joint_target(
    bone_name: StringName,
    rotation: Quaternion
)
```

Also:

```text
set_joint_strength(
    bone_name: StringName,
    strength: float
)

reset_joint_target(
    bone_name: StringName
)

reset_all_targets()

get_controlled_bones()
```

`reset_joint_target()` means:

```text
target_rotation = Quaternion.IDENTITY
```

therefore returning that joint to the captured reference orientation.

---

# 15. Indexed API for RL

The RL system should not perform StringName lookup every simulation step.

Create a fixed ordering:

```text
0 -> Spine
1 -> Spine1
2 -> Spine2
3 -> LeftArm
4 -> LeftForeArm
...
```

Expose:

```text
get_joint_count()

get_joint_name(index)

set_joint_target_by_index(
    index,
    Quaternion
)
```

The ordering must remain deterministic.

Names are useful for debugging.

Indices are useful for simulation/training.

---

# 16. RL Action Representation

The **PD controller should consume quaternions**.

The future RL policy should **not output raw quaternion components**.

Avoid:

```text
qx
qy
qz
qw
```

because:

```text
|q| = 1
```

must be maintained and:

```text
q
```

and:

```text
-q
```

represent exactly the same rotation.

Instead use a rotation vector:

```text
rx
ry
rz
```

representing:

```text
axis * angle
```

Then:

```text
RL action
    ↓
bounded rotation vector
    ↓
Quaternion
    ↓
PD target
```

For a hinge-like joint such as an elbow, the future action representation may use only one scalar.

---

# 17. Pose + Residual Control

Design the rotation convention so this remains possible:

```text
final_target =
    base_pose
    *
    control_offset
```

For example:

```text
boxing_stance
      *
RL_balance_adjustment
```

or:

```text
boxing_guard
      *
dodge_adjustment
```

Do not implement a complex pose stack yet.

Just ensure the quaternion convention supports composition cleanly.

---

# 18. Joint Parameters

Initially each joint needs:

```text
stiffness
damping
max_torque
strength
```

Start with global defaults:

```text
default_stiffness
default_damping
default_max_torque
```

Then allow optional overrides.

Later useful categories will probably be:

```text
legs
spine
arms
neck
```

Do not overbuild this configuration system now.

---

# Milestone 1 — Quaternion / PD Math

Implement standalone helpers for:

```text
quaternion shortest-path handling
quaternion -> rotation vector
PD torque calculation
torque magnitude limiting
```

Tests:

```text
identity -> identity     = zero error
identity -> +30° X       = +X
identity -> -30° X       = -X
+179° -> -179°           = ~2° error
q and -q                 = equivalent
```

Stop here until these are predictable.

---

# Milestone 2 — One Joint Only

Pick one simple joint, preferably:

```text
LeftForeArm
```

Control only this joint.

Set:

```text
q_target = Quaternion.IDENTITY
```

first.

Then provide a manually constructed rotation target.

PD should:

1. compute orientation error;
2. compute relative angular velocity;
3. calculate torque;
4. clamp it;
5. convert to world space;
6. call:

```text
PhysicsServer3D.body_apply_torque(child_rid, torque)
PhysicsServer3D.body_apply_torque(parent_rid, -torque)
```

### Verify

- It moves toward the desired orientation.
- It takes the shortest rotational path.
- It does not directly manipulate transforms.
- An external collision can move it away.
- It naturally tries to recover.
- Increasing damping reduces oscillation.
- `max_torque` actually limits motor strength.

If rotation direction is wrong, fix the quaternion/coordinate-space convention here.

---

# Milestone 3 — Automatic Skeleton Discovery

Build:

```text
Vector<PDJoint>
```

automatically.

Log something like:

```text
Spine -> Hips
Spine1 -> Spine
Spine2 -> Spine1
LeftArm -> ...
LeftForeArm -> LeftArm
...
```

Verify hierarchy manually before enabling all motors.

---

# Milestone 4 — Full Ragdoll PD

Enable PD on:

```text
spine
upper legs
lower legs
feet
upper arms
forearms
```

Initially leave:

```text
hips/root
```

uncontrolled.

Neck/head can be added afterward.

Do not expect the character to stand yet.

The important test is:

> Does every joint correctly attempt to hold its local target while the entire boxer remains a physically simulated ragdoll?

Falling over is still valid at this stage.

---

# Milestone 5 — Debug Target Controller

Create a very small GDScript testing layer.

Allow manually changing targets such as:

```text
bend left elbow
bend right elbow
raise one arm
rotate thigh
rotate spine
reset pose
```

The debugger should call the same public API future systems will call.

Avoid building an animation system.

---

# Milestone 6 — Pose Container

Add a lightweight concept:

```text
RagdollPose
```

containing one quaternion per controlled joint.

Conceptually:

```text
RagdollPose
    joint[0] -> Quaternion
    joint[1] -> Quaternion
    joint[2] -> Quaternion
```

This can later represent:

```text
neutral
boxing stance
guard
RL output
```

The PD controller still only sees target rotations.

---

# Milestone 7 — PD Tuning / Stability

Once basic control works, tune:

```text
Kp
Kd
max_torque
```

per body region if necessary.

Avoid solving instability simply by using enormous `Kp`.

The target behavior is:

```text
strong
responsive
physically movable
limited torque
low oscillation
```

Later investigate inertia-aware damping.

Conceptually:

```text
Kd ≈ 2 * ζ * sqrt(Kp * I)
```

where `I` is an effective rotational inertia and `ζ` controls damping.

This can make joints with very different body masses behave more consistently.

---

# Milestone 8 — RL Adapter Boundary

Only after the entire PD system behaves correctly, create:

```text
RagdollActionAdapter
```

Its responsibility:

```text
RL normalized action
        ↓
joint-specific angular limits
        ↓
rotation vector
        ↓
Quaternion
        ↓
ActiveRagdollPD3D
```

The RL code should never need to know how torque is calculated.

The PD controller should never need to know where the target came from.

---

# Later — Learned Boxing Stance

The first useful RL task should likely be:

> Maintain a boxing stance while remaining balanced against gravity and small disturbances.

Policy outputs:

```text
joint rotation offsets
```

not torque.

PD turns those targets into physical torques.

Useful observations later:

```text
joint relative rotations
joint angular velocities
pelvis orientation
pelvis velocity
pelvis angular velocity
foot contacts
head height/orientation
possibly COM information
```

The hips/root remain physically free.

---

# Later — Hand Target Tracking

Once stance works, give the policy:

```text
left hand target
right hand target
```

preferably in boxer/pelvis-local coordinates.

Reward hand proximity.

The policy still only outputs joint rotation targets.

Therefore the PD layer does not change.

---

# Last Goal — Spine / Head Dodging

Later give the policy information about:

```text
incoming attack
desired dodge direction
desired head displacement
```

and allow it to modify:

```text
Spine
Spine1
Spine2
```

targets.

The same pipeline remains:

```text
task
 ↓
RL
 ↓
joint rotation targets
 ↓
PD
 ↓
body_apply_torque()
 ↓
physical movement
```

No separate dodge physics system should be necessary.

---

# What To Do Next

The immediate implementation should be:

```text
1. Create ActiveRagdollPD3D in C++.
2. Implement quaternion error -> rotation vector.
3. Create PDJoint.
4. Cache PhysicalBone3D RIDs.
5. Initialize one elbow joint.
6. Calculate Kp/Kd torque.
7. Clamp torque.
8. Apply it using PhysicsServer3D.body_apply_torque().
9. Apply equal and opposite torque to parent and child.
10. Verify one joint completely before controlling the entire ragdoll.
```

The **first success criterion** should not be "the boxer stands."

It should be:

> I can give one physical joint a parent-relative quaternion target, and the two rigid bodies physically torque themselves toward that target using only `PhysicsServer3D.body_apply_torque()`.

Once that is reliable, expand to the full skeleton.