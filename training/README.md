# Python TCP training bridge

Run commands from the repository root. Requires Godot with the existing
GDExtension built, Python 3.10+, and NumPy:

```powershell
python -m pip install -r training/requirements.txt
```

Start a small headless server (two arenas, gravity scale 0.1):

```powershell
godot --headless --path . --script training/run_server.gd -- --arenas=2 --port=7000
```

Alternatively run `balance_training.tscn` in Godot; its existing arena count is
preserved and its TCP server listens on port 7000. Only one client is accepted.
Close the Godot process when finished; Python CLOSE intentionally leaves it
available for another connection. Do not run the two server entry points on the
same port.

In another terminal:

```powershell
python -m training.random_client --steps 10000
python -m training.test_transport
```

The random client validates HELLO, reset shape/dtype/neutral action, every STEP
payload and action history, terminal auto-resets, a final reset, and reconnect.
It prints batch steps/second and completed episodes every 1000 steps. Multiply
batch steps/second by arena count for environment transitions/second.
The transport test checks fragmented/coalesced requests, malformed commands,
invalid actions, duplicate steps, a second client, and abrupt mid-step disconnect.
Use `--port` on either client if needed. Random actions use a repeatable NumPy
seed (`--seed`); the protocol does not currently set Godot random seeds.

Local checks:

```powershell
python -m unittest training.test_protocol
godot --headless --path . --log-file .godot/tcp-protocol-test.log --script Addon/retro_boxing/tests/tcp_protocol_test.gd --quit-after 1000
```

Godot must print `TCP protocol tests passed` with no `SCRIPT ERROR:`. That test
also runs in `Addon/retro_boxing/tests/run_tests.ps1`. It verifies physical reset,
lifetime statistics, header metadata, action validation, and terminal encoding
without a Python process.

The bridge uses the existing manager for all simulation decisions. See
[TCP_PROTOCOL.md](../TCP_PROTOCOL.md) for the byte layout.

## Stable-Baselines3

After the TCP checks pass, install the optional training dependencies:

```powershell
python -m venv .venv
.venv/Scripts/python -m pip install -r training/requirements-sb3.txt
.venv/Scripts/python -m unittest training.test_protocol training.test_vec_env
.venv/Scripts/python -m training.check_vec_env --steps 1000
.venv/Scripts/python -m training.train_ppo --timesteps 2048
```

Keep the headless server at two arenas and gravity 0.1 for the smoke test.
PPO uses a small MLP, CPU execution, 512 rollout steps per arena, and batches of
64. Requested timesteps are rounded up to complete rollouts. The default model
is `training/models/ppo_balance_v2.zip`. Logs go to `training/runs/ppo_v2` in CSV and
TensorBoard formats. All these outputs are gitignored.

Stop/restart Godot, then continue training in a new Python process:

```powershell
.venv/Scripts/python -m training.train_ppo --resume training/models/ppo_balance_v2.zip --model training/models/ppo_balance_v2_resumed --timesteps 2048 --log-dir training/runs/resumed
.venv/Scripts/python -m training.evaluate --model training/models/ppo_balance_v2_resumed.zip --episodes 10
.venv/Scripts/tensorboard --logdir training/runs
```

Evaluation reports average episode reward and duration for neutral actions and
the deterministic PPO policy, with equal episode quotas per arena where possible.
A successful smoke test verifies the pipeline; it does not establish that PPO
has learned to balance. Use longer training and this comparison to assess that.
Do not change rewards or increase arena count to address protocol problems.

The adapter follows the [SB3 VecEnv contract](https://stable-baselines3.readthedocs.io/en/master/guide/vec_envs.html):
`done = terminated OR truncated`, post-reset observations plus final
`terminal_observation`, and `TimeLimit.truncated` for timeouts. Observation bounds
are [-5,5], matching the existing state provider. Episode duration is counted in
policy steps / 60 (simulation seconds); it is not wall-clock time. No VecMonitor
is necessary because the adapter provides episode statistics directly.

Protocol v1 does not expose remote attributes, method calls, seed changes,
rendered frames, or reset options. The deterministic Godot reset is unchanged;
Python's seed controls PPO and action sampling only. The seed method returns
None per arena to make this explicit.

Only after learning improves over neutral, try `--arenas=4`, then 8 and 16 in the
server command. Compare transitions/second (not just batch steps/second), SB3 FPS,
and process CPU usage; inspect Godot's profiler for frame/physics cost. Choose
the measured useful throughput rather than maximizing arena allocation.

## Verification in this workspace

- Godot protocol/reset tests and existing training transition tests passed.
- Python protocol and VecEnv unit tests passed (5 tests).
- Real TCP fragmentation, coalescing, invalid input, busy-step and reconnect checks passed.
- Random TCP stress: 10,000 batch steps / 20,000 arena transitions, 86 completed
  episodes, approximately 20 batch steps/second with two arenas.
- VecEnv: 1,000 random batch steps passed, including cancellation by reset.
- PPO: 2,048 timesteps completed with finite metrics and saved weights.
- Godot and Python were restarted; the saved model loaded and continued for
  another 512 timesteps, reaching 2,560 total, and saved again.
- Tested versions: Python 3.13.5, NumPy 2.3.2, SB3 2.9.0, PyTorch 2.14.0 CPU,
  TensorBoard 2.21.0, Godot 4.7.2. No reward, ragdoll or PD changes were required.

Smoke outputs are `training/models/ppo_smoke.zip`,
`training/models/ppo_resumed.zip`, and `training/runs/{smoke,resumed}`.

Four-episode evaluation of the 2,048-step smoke model at gravity 0.1:
neutral averaged 6.35 simulation seconds and reward 1040.41; PPO averaged 3.825
seconds and reward 634.36. The smoke model has **not** beaten neutral. Longer
learning is still required; arena scaling was not attempted before this gate.


## Balance v2: fresh policy and manual gravity curriculum

No training is started by implementation or tests. Existing checkpoints are
comparison artifacts: do not resume a pre-v2 policy because knee semantics,
masses and reward changed. The default fresh output is `ppo_balance_v2`;
existing output checkpoints are rejected to avoid overwriting your baseline.
PPO uses gamma 0.997, GAE lambda 0.95, 512 steps per arena and batch size 64.
At 28 arenas a rollout is 14,336 transitions, so timestep requests round up
by that amount. Resume applies these horizon settings too.

Before training, run `balance_manual_test.tscn`: `0` sends neutral (8 degree
knees), `P` toggles PD, `R` resets (and enables PD), `G` toggles gravity.
Inspect natural falls with PD off, reference-pose holding with PD on, and
foot sliding during small corrections. Strong-force sliding still needs a
manual physics check; no push disturbances were added to training.
The body totals 76 kg; feet are 1.5 kg each with friction 0.8.

Start the server and a fresh policy yourself:

```powershell
godot --headless --path . --script training/run_server.gd -- --arenas=28 --gravity=0.10 --port=7000
.venv/Scripts/python -m training.train_ppo --timesteps 200000 --model training/models/balance_v2_g010 --log-dir training/runs/v2_g010
.venv/Scripts/python -m training.evaluate --model training/models/balance_v2_g010.zip --episodes 280
```

Godot exclusively owns gravity. The Python training and evaluation processes do
not accept, transmit, or report it; protocol v1 does not expose gravity.
Evaluation reports success/failure rates, average duration/reward and a
`ready_to_advance` recommendation (at least 85% timeouts and 9 seconds mean).
Use repeated evaluations before advancing: resets are deterministic and
many identical arenas do not establish robustness by themselves.

Restart the server at the next gravity only after consistent success, then
resume the same v2 model into a new checkpoint and log directory:

```powershell
godot --headless --path . --script training/run_server.gd -- --arenas=28 --gravity=0.15 --port=7000
.venv/Scripts/python -m training.train_ppo --resume training/models/balance_v2_g010.zip --model training/models/balance_v2_g015 --log-dir training/runs/v2_g015 --timesteps 200000
```

Follow 0.10, 0.15, 0.20, 0.25, 0.35, 0.50, 0.70, 1.00. Stop/restart the
previous server before each command; progression is never automatic.
At 0.25 record duration, timeout percentage and reward and visually inspect
ankle/hip/knee/spine coordination. Compare duration and success with your old
experiment. Raw rewards across reward-function versions are not comparable;
keep the original code/settings with the old checkpoint for a valid baseline.
The historical verification figures above describe the old environment.
