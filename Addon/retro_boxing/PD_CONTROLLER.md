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

## Balance action interface

`BalanceJointAxisResolver` inspects the seven balance joints once at scene startup,
using rest geometry for anatomical directions and physical joint frames for candidate
axes. Offsets are expressed in the reference child body's axes, matching
`reference * target` in PD. `joint_rotation` is already included in `joint_offset`.
The current Mixamo bone names and cone joints are the supported rig contract;
missing geometry, locked cone spans, and unsupported joint types fail explicitly.
This is not a general-purpose anatomical retargeter.

The action order remains the 12 entries in `BalanceController.ACTION_NAMES`.
Positive hip/spine pitch moves forward; positive roll moves toward character right.
Positive ankle pitch lifts the toes. Ankle roll uses the sole normal as its movement
probe, since rotating about the foot's length barely moves the toes. Knee flexion
moves the lower leg backward. Signs are resolved independently per joint.

Knees map `[-1, 0, +1]` to `[0, 17.5, 35]` degrees of additional reference-pose
flexion. Consequently **neutral is `[0,0,0,0,-1,-1,0,0,0,0,0,0]`**, available through
`get_neutral_action()`. An all-zero policy action bends both knees halfway.
Reset restores identity offsets, smoothing state, motor targets, velocities, and
elapsed time. The reference knees are already slightly bent; actions do not command
extension beyond that reference. The existing cone constraints still allow passive
hyperextension under external forces; this change restricts commanded targets.

Exported angle limits are capped conservatively by the smaller cone span, divided
between a joint's action axes. The current spine swing span is 7 degrees, so its
effective pitch/roll limits are 3.5 degrees each. This preserves the physical rig;
constraint/profile tuning can be done separately during balance training.

`BalanceEpisode` advances `elapsed_time` using physics delta and caps it at the
exported `maximum_episode_duration` (10 seconds). `has_failed()` and
`has_timed_out()` are separate queries, also exposed by `BalanceEnvironment`;
`is_terminal()` combines them. The caller ends/resets an episode; timeout does not
freeze simulation or automatically reset it. RL code can map failure to termination
and timeout to truncation (failure takes precedence when both occur).

### Verification

In debug builds, the test scene supports `G` to toggle gravity and `C` to cycle all
12 actions through -1, 0, +1, resetting between samples. The inspector also exposes
`gravity_free`, `auto_cycle`, and `cycle_seconds`. Normal gravity defaults to 1;
the helper restores each body's original value. `[` / `]` select, `-` / `=` adjust,
`0` restores neutral, and `R` resets the episode. Gravity changes live only in this
test helper, not `ActiveRagdoll`.

The test runner includes resolver normalization/independence, joint-frame
permutation, knee mapping, repeated resets, exact 10-second boundaries at 60/240 Hz,
and separate failure/timeout checks. The action runtime test exercises every action
with real collisions and no gravity, then compares five balance input groups against
neutral under normal gravity. These check actuator response, not learned stability.

For a rendered contact sheet of all 12 positive actions:

```powershell
godot --path . --rendering-method gl_compatibility --script Addon/retro_boxing/tests/balance_action_runtime_test.gd -- --capture
```

The image is saved to `.godot/balance-actions.png`. Fixed policy frequency, rewards,
PPO integration, and balance training remain the next stage.
