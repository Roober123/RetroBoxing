# Local RL stepping contract

`BalanceTrainingManager` owns pausing for a dedicated training SceneTree. Use one
manager per tree. It starts in `WAITING_FOR_ACTION`, with all arenas explicitly
pausable. The manager uses `PROCESS_MODE_ALWAYS`; a future transport can use the
same mode to poll while physics is paused. Removing the manager restores the
previous tree pause state. Do not independently toggle the tree pause state while
training is active.

Call `begin_policy_step(actions)` with one normalized 12-value action per arena.
The manager enters `RUNNING_POLICY_STEP`, unpauses, and advances four physics ticks
at 240 Hz (60 Hz policy rate). At the next physics-frame boundary, after the fourth
integration is synchronized, it pauses before a fifth simulation tick and emits
`policy_step_completed(result)`. At emission, `last_step_result` is populated and
`is_waiting_for_action()` is true. Callers can submit the next action immediately
or wait arbitrarily long. `physics_tick` counts active simulation ticks only.

Each result contains observations, rewards, terminated, truncated, and
terminal_observations. Failure takes precedence over timeout in exported flags and
statistics; the episode's raw failure and timeout queries remain independent.
Finished arenas contribute a final pre-reset terminal observation and reward,
then reset and contribute a fresh next observation. Survivors have an empty
terminal observation. Returned observations match the states used by the next action.

Observations contain 175 float32 values: the existing 163 physical-state values
followed by the 12 last-applied normalized controller actions, in
`BalanceController.ACTION_NAMES` order. Following reset, this suffix is neutral:
`[0,0,0,0,-1,-1,0,0,0,0,0,0]`. This adds action history but does not expose every
internal smoothing quaternion.

Run all regression checks with:

```powershell
powershell -ExecutionPolicy Bypass -File Addon/retro_boxing/tests/run_tests.ps1
```

`training_transition_test.gd` exercises startup/waiting freeze, real engine ticks,
failure, timeout, simultaneous failure and timeout, terminal observation capture,
post-reset state/action equality, and resume. `training_checks.gd` compares exact
body transforms, velocities, observations (including contacts), target smoothing
rotations, timers, and counters across physics and idle frames while waiting.
`rl_environment_stress_test.gd` runs 1,000 random steps and a separate fresh 1,000-step
neutral baseline with two arenas at gravity scale 1.0, checking transitions and
periodic freezes. Baseline statistics include only completed episodes.

No transport, Python training, curriculum, or new ragdoll mechanics are implemented.

## Verified baseline (2026-09-14)

Godot 4.7.2, headless, two arenas, gravity scale 1.0, 240 Hz physics,
60 Hz policy, 1,000 neutral policy steps following fresh initialization:

| Metric | Value |
| --- | ---: |
| Completed episodes | 82 |
| Average episode duration | 0.400 seconds |
| Average episode reward | 64.519524 |
| Failed episodes | 82 |
| Timed-out episodes | 0 |

The preceding independent 1,000-step random run (seed 12345) completed 75 episodes,
with average duration 0.438667 seconds and average reward 69.864136; all 75 failed.
All per-step transition, observation, tick-count, and periodic freeze checks passed.
These short episodes are a smoke-test baseline, not evidence of a stable balance policy.
