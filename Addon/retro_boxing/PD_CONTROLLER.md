# Active ragdoll PD

Build with `scons`, then run `test.tscn`. All 19 joints are enabled by default;
the hips have no motor. Gravity is disabled to isolate pose control. Set
`isolate_gravity = false` to restore gravity; this system does not balance yet.
The character meshes are visible so the targets can be inspected directly.

## Controls

- T: full-body test pose (the initial pose).
- B: boxing stance, with bent knees and hands beside the head.
- R: neutral reference pose.
- V: toggle calculated target angular velocity for comparison.
- 1 / 2 / 3 / 4: torque impulse on left forearm / upper arm / thigh / spine.
- Shift + number: twice the impulse.

Set `debug_targets = false` to disable these controls. An empty `motor_bones`
array enables all joints; a populated array isolates selected motors.

## Body profiles

`ActiveRagdoll` owns the bone groups and calls:

```gdscript
pd_controller.set_body_profile(
    [&"mixamorig_LeftArm", &"mixamorig_LeftForeArm"],
    2.0, # response frequency in Hz
    1.0, # damping ratio
    0.5  # maximum torque in Nm
)
```

Profiles configure initialized joints, without changing targets, enabled state,
or strength. The whole request is validated before any joint is changed.
Unknown names (including the unmotorized hips) produce an error naming the bone
and return false. Values must be finite and nonnegative. Empty arrays are a no-op.
Reapply profiles after reinitializing the controller.

The initial inertia proxy is reduced body mass times a squared 10 cm radius of
gyration: `I = 0.01 / (1 / child_mass + 1 / parent_mass)`. Gains are
`Kp = I * (TAU * frequency)^2` and `Kd = 2 * damping * I * TAU * frequency`.
This is deliberately approximate, especially for tiny neck/head bodies;
damping ratios are tuning inputs, not guaranteed critical damping.
`get_joint_parameters(name)` returns `(Kp, Kd, max_torque)` for inspection.
The original raw gain/default setters remain available for compatibility.

Initial profile values `(Hz, damping ratio, Nm)`:

| Group | Values |
| --- | --- |
| Arms, shoulders, hands | (2, 1, 0.5) |
| Spine | (1.5, 1, 2) |
| Legs | (2, 1, 1) |
| Feet | (1.5, 1, 0.3) |
| Neck/head | (1, 0.2, 0.2) |

## Targets and pose composition

`RagdollPose` stores quaternion offsets in `get_joint_name(index)` order.
Use poses with the same initialized skeleton ordering. `neutral(count)` makes
identity offsets. `blended(other, weight)` uses shortest-path slerp; `composed`
returns `base * offset`. Both return a new pose without modifying their inputs.

```gdscript
var targets := ragdoll.target_controller
targets.base_pose = ragdoll.neutral_pose.blended(ragdoll.boxing_pose, 0.7)
targets.control_offset = residual_pose # Same joint ordering; identity means no offset.
```

`RagdollTargetController` composes the base and residual pose, then applies
exponential quaternion smoothing each physics tick. `smoothing_speed` defaults
to 8 per second (zero freezes the target). It runs before PD, differentiates the
shortest quaternion step, and converts that velocity from reference-child axes
into parent-body axes. `use_target_velocity = false` sends zero velocities.

The low-level controller still accepts immediate quaternion and angular velocity
targets. Disable the target controller's physics processing before driving PD
directly, otherwise it will overwrite those targets on the next tick.
`RagdollPose.apply_to(pd)` applies an immediate stationary pose and clears target
velocities. PD reset methods also clear both target rotation and velocity.

Desired relative orientation is `reference * target`. The reference includes
physical body offsets. PD computes orientation error in the parent frame,
transforms it into world space, and uses child-minus-parent angular velocity.
Torque is magnitude-limited and applied once per 120 Hz tick as child `+torque`
and parent `-torque`, without multiplying by delta. Zero strength or torque
limit disables output. No root correction is applied.

Initialize and capture the reference before starting physical simulation.
Discovery uses direct physical parents and ascending skeleton IDs; bones with
no physical parent or no joint are skipped. The sample poses are generated once
at startup from this reference, including mirrored arm directions.

## Validation

```powershell
./Addon/retro_boxing/tests/run_tests.ps1
```

Native math checks cover signed angles, quaternion sign equivalence, the
179/-179 crossing, world-frame conversion, damping, strength, and torque limits.
Headless Jolt checks cover profile isolation, atomic rejection of invalid inputs, gain scaling, pose composition,
elbow convergence and recovery, full-body pose convergence, four-region impulse
recovery, boxing convergence, 30-degree arm velocity feed-forward comparison, gravity/collision
finite simulation, and freed-body safety. Convergence tests disable collisions
and gravity to isolate actuators. The rendered boxing pose was also inspected
with scene collisions enabled. The profile API test intentionally prints three
rejected-input errors; its success marker distinguishes them from test failures.

On the included skeleton, the full-body test and boxing stance converged within
7 degrees per joint. Calculated velocity reduced mean tracking error on the
30-degree arm test from about 10.5 to 4.7 degrees. Large whole-body transitions
can saturate torque limits; feed-forward does not guarantee better tracking in
that case. Reduce target speed or tune the profiles for such movements.

This remains an actuator test, not learned balance, IK, punching, or an animation
graph. The free body can rotate or drift after an impulse. Profile inertia and
stance parameters will need further tuning when adding those later systems.
