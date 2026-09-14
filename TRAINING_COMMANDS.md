# Training Command Cheat Sheet

Run every command from the repository root. Training uses two terminals: keep
the Godot server running in terminal 1 and run Python commands in terminal 2.

## One-time setup

```powershell
python -m venv .venv
.venv/Scripts/python -m pip install -r training/requirements-sb3.txt
```

If you only need the TCP client and protocol tests (not PPO), install the
smaller dependency set instead:

```powershell
python -m pip install -r training/requirements.txt
```

## Start the training server (terminal 1)

```powershell
godot --headless --path . --script training/run_server.gd -- --arenas=28 --gravity=0.10 --port=7000
```

Server options:

- `--arenas=N` — parallel arenas, from 1 to 1024 (default: 2)
- `--gravity=N` — gravity scale, from 0.0 to 2.0
- `--port=N` — TCP port (default: 7000)

Stop the server with `Ctrl+C`. Stop and restart it to change arena count,
gravity, or port. Do not start two servers on the same port.

## Train a fresh model (terminal 2)

```powershell
.venv/Scripts/python -m training.train_ppo --timesteps 200000 --model training/models/balance_v2_g010 --log-dir training/runs/v2_g010
```

Training options:

- `--timesteps N` — requested training transitions (default: 10000)
- `--model PATH` — new output checkpoint path; `.zip` is added automatically
- `--log-dir PATH` — CSV and TensorBoard output directory
- `--seed N` — Python/PPO seed for a fresh model (default: 0)
- `--host HOST` — server host (default: `127.0.0.1`)
- `--port N` — server port (default: 7000)
- `--resume PATH.zip` — load a checkpoint and continue training

The output model must not already exist. Choose a new `--model` name for every
run so an earlier checkpoint is not overwritten. PPO completes whole rollouts,
so the actual timestep count can be higher than the requested count.

## Resume training into a new checkpoint

Restart the Godot server with the desired gravity first, then run:

```powershell
.venv/Scripts/python -m training.train_ppo --resume training/models/balance_v2_g010.zip --model training/models/balance_v2_g015 --log-dir training/runs/v2_g015 --timesteps 200000
```

Do not resume a checkpoint created before Balance v2; the action semantics,
masses, and reward changed.

## Evaluate a checkpoint

```powershell
.venv/Scripts/python -m training.evaluate --model training/models/balance_v2_g010.zip --episodes 280
```

Add `--port N` when the server is not on port 7000. Evaluation compares neutral
actions with the deterministic PPO policy and prints `ready_to_advance`.

## Gravity curriculum

Use these gravity scales in order:

```text
0.10 -> 0.15 -> 0.20 -> 0.25 -> 0.35 -> 0.50 -> 0.70 -> 1.00
```

At each stage:

1. Start/restart the server at the new gravity.
2. Resume the previous checkpoint into a newly named checkpoint.
3. Evaluate the new checkpoint, preferably more than once.
4. Advance only after consistent results. The evaluator recommends advancing
   at 85% or more timeouts and at least 9 seconds mean episode duration.

Example naming: `balance_v2_g010`, `balance_v2_g015`, `balance_v2_g020`, etc.

## Watch TensorBoard

```powershell
.venv/Scripts/tensorboard --logdir training/runs
```

Open the local URL printed by TensorBoard. It can run in a third terminal.

## Pipeline checks

Start the Godot server before checks that connect over TCP.

```powershell
# Random TCP stress check
python -m training.random_client --steps 10000

# Transport/error-handling check
python -m training.test_transport

# Stable-Baselines3 VecEnv check
.venv/Scripts/python -m training.check_vec_env --steps 1000

# Python unit tests (no running server needed)
.venv/Scripts/python -m unittest training.test_protocol training.test_vec_env

# Godot TCP protocol test (no running server needed)
godot --headless --path . --log-file .godot/tcp-protocol-test.log --script Addon/retro_boxing/tests/tcp_protocol_test.gd --quit-after 1000

# Complete native/Godot test suite (also rebuilds its C++ math test)
powershell -ExecutionPolicy Bypass -File Addon/retro_boxing/tests/run_tests.ps1
```

Client flags:

- `random_client`: `--host`, `--port`, `--steps`, `--seed`
- `test_transport`: `--port`
- `check_vec_env`: `--port`, `--steps`

## Manual balance check

Open and run `balance_manual_test.tscn` in Godot. Controls:

- `0` — send the neutral action (8-degree knees)
- `P` — toggle the PD controller
- `R` — reset and enable the PD controller
- `G` — toggle gravity

## Get built-in help

```powershell
.venv/Scripts/python -m training.train_ppo --help
.venv/Scripts/python -m training.evaluate --help
python -m training.random_client --help
python -m training.test_transport --help
.venv/Scripts/python -m training.check_vec_env --help
```
