# Future TCP protocol

This is a design note only; networking is not implemented yet.

- Startup metadata: `protocol_version`, `arena_count`, `observation_size`, `action_size`.
- Commands: `HELLO`, `RESET`, `STEP`, `CLOSE`.
- `STEP` input: float32 actions shaped `[arena_count, action_size]`.
- `STEP` output: float32 observations `[arena_count, observation_size]`, float32 rewards `[arena_count]`, bool terminated `[arena_count]`, and bool truncated `[arena_count]`.

Terminated means the ragdoll failed. Truncated means its time limit expired without failure. Exported flags are mutually exclusive; failure takes precedence.

The local stepping contract is implemented and documented in [RL_ENVIRONMENT.md](RL_ENVIRONMENT.md). A future STEP response must also carry final pre-reset terminal observations for finished arenas. Its regular observations contain post-reset states for those arenas. Observation size is now 175, including the 12 last-applied action values.
