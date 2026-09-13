# Active ragdoll PD

Build with `scons`, then run `test.tscn`. The scene starts with only
`mixamorig_LeftForeArm` driven. The hips have no motor. Falling is expected.

On the ActiveRagdoll inspector, enable `debug_targets`: keys 1/2 bend the elbows,
3 targets the left arm, 4 the left thigh, 5 the spine, and R resets all targets.
Each numbered key also enables that joint. These are simple 30-degree body-local
X offsets, not anatomically calibrated poses. Clear `motor_bones` to enable all
19 discovered joints; per-region tuning is still needed for useful full-body control.

`active_ragdoll.gd` applies the existing collision fix, creates the controller,
sets defaults, initializes joints, captures the reference pose, starts simulation,
then enables PD. Initialize/capture before simulation, and reinitialize after
changing the skeleton. Joint indices follow ascending skeleton bone IDs. Discovery
uses direct physical parents; bones with no physical parent or no joint are skipped.

Targets are normalized quaternion offsets: `desired = reference * target`.
Identity holds the captured relative body orientation, including body offsets.
The target offset axes are the reference child-body axes. Orientation error lives
in the parent-body frame and is rotated to world space before applying torque.
`set_joint_target_angular_velocity(name, velocity)` accepts parent-body-local
radians/second. Angular velocity feedback is child minus parent in world space.
Torque is applied once per 120 Hz physics tick, without multiplying by delta,
using equal and opposite `PhysicsServer3D.body_apply_torque` calls.

The name-based API supports targets, strength, enabling individual joints,
angular velocity targets, and `set_joint_parameters(name, stiffness, damping,
max_torque)`. Defaults are copied during initialization; use joint parameters
to tune an initialized controller. Gains, strength, and torque limits must be
finite and nonnegative. Zero strength or torque limit disables motor output.
Reset methods clear both rotation offsets and target angular velocities.

For indexed callers, use `get_joint_count()`, `get_joint_name(index)` and
`set_joint_target_by_index(index, quaternion)`. `get_controlled_bones()` includes
all discovered joints, even individually disabled ones. `RagdollPose` is just
an ordered quaternion array and `apply_to(controller)`; use it with the same
skeleton ordering. Compose pose and residual offsets before passing the target.

## Validation

After building, run from the project root:

```powershell
./Addon/retro_boxing/tests/run_tests.ps1
```

Native math checks cover signed angles, the 179/-179 crossing, quaternion sign
equivalence, world-frame conversion, damping, strength and magnitude limits.
The headless Jolt test checks the actual skeleton hierarchy, elbow convergence,
impulse disturbance recovery, reset, all-motor finite simulation and freed-body
safety. The elbow convergence test removes gravity and collisions to isolate
the motor, then restores both for the all-motor smoke test.

The conservative defaults (Kp 2, Kd 0.08, maximum torque 0.5) were checked on
this scene's elbow at 120 Hz. Full-body balance, collision recovery tuning,
anatomical debug poses, and RL action limits/adapters remain later work, as in
the plan. No upright root motor, pose stack, IK, or learned policy is included.
