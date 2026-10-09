# RetroBoxing

**A physics-driven active-ragdoll and reinforcement-learning prototype built with Godot.**

RetroBoxing explores physics-based character control, balance, and reinforcement-learning (RL) workflows. Instead of relying solely on authored animation, the project uses a physically simulated ragdoll with joint targets and a controller that can be driven by external policies.

This is an engineering prototype focused on simulation, control, and training infrastructure—not a finished boxing game.

## Technical highlights

- **Active-ragdoll control in C++:** A Godot GDExtension provides proportional-derivative (PD) joint control for physical bones, including configurable joint targets, gains, torque limits, and per-joint control.
- **Procedural balance control in GDScript:** Joint-axis resolution, pose targets, normalized actions, observation collection, reward calculation, and episode management.
- **High-frequency physics:** Godot runs at **240 Hz**. The RL environment advances four physics ticks per policy action, for a **60 Hz policy rate**.
- **Parallel training environments:** A manager coordinates multiple ragdoll arenas, policy-step timing, resets, and terminal observations.
- **Python training bridge:** A local binary TCP protocol connects Godot to Python. The Python side includes a vectorized environment adapter compatible with Stable-Baselines3, PPO training and evaluation tools, and protocol/stress tests.
- **Automated checks:** C++ math tests plus Godot runtime, controller, training-transition, and TCP tests help validate simulation and environment behavior.

## Technology stack

| Area | Tools |
| --- | --- |
| Engine and physics | Godot 4.7, Jolt Physics |
| Native extension | C++, GDExtension, `godot-cpp`, SCons |
| Simulation and controllers | GDScript |
| RL tooling | Python, NumPy, Stable-Baselines3, PPO |
| Integration | Local TCP protocol, binary `float32` observations/actions |

## Getting started

### 1. Clone the repository

Clone with submodules so the `godot-cpp` dependency is available:

```powershell
git clone --recurse-submodules https://github.com/Roober123/RetroBoxing.git
cd RetroBoxing
```

For an existing clone:

```powershell
git submodule update --init --recursive
```

### 2. Build the GDExtension

From the repository root, build the native extension:

```powershell
scons
```

The current SCons defaults target a 64-bit Windows debug build using MinGW and Godot 4.7 bindings. A release build can be requested with:

```powershell
scons target=template_release
```

Open the project in Godot 4.7. The `balance_manual_test.tscn` scene provides a manual balance/controller test scene; see [TRAINING_COMMANDS.md](TRAINING_COMMANDS.md) for its controls and additional commands.

## Reinforcement-learning workflow

The RL bridge runs locally. Start the Godot server in one terminal, then connect a Python client from another.

Install the base Python dependencies:

```powershell
python -m pip install -r training/requirements.txt
```

Start a headless server with two arenas:

```powershell
godot --headless --path . --script training/run_server.gd -- --arenas=2 --port=7000
```

In a second terminal, run a TCP smoke test:

```powershell
python -m training.random_client --steps 10000
```

For PPO training, install the optional dependencies from `training/requirements-sb3.txt`, then follow [TRAINING_COMMANDS.md](TRAINING_COMMANDS.md) and [training/README.md](training/README.md). The simulation contract and observation/action layout are documented in [RL_ENVIRONMENT.md](RL_ENVIRONMENT.md) and [TCP_PROTOCOL.md](TCP_PROTOCOL.md).

**Training status:** The infrastructure supports training and evaluation experiments, but a working pipeline does not by itself mean a policy has learned robust balance. Consult the training notes for the latest measured results and limitations.

## Tests

The full Godot/C++ test suite can be run on Windows from PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File Addon/retro_boxing/tests/run_tests.ps1
```

Python protocol and vectorized-environment unit tests:

```powershell
python -m unittest training.test_protocol training.test_vec_env
```

TCP integration and stress tests require the Godot server to be running. Further test commands and expectations are listed in [TRAINING_COMMANDS.md](TRAINING_COMMANDS.md).

## Project structure

- `Addon/retro_boxing/` — C++ GDExtension source and native/Godot tests.
- `Ragdoll/` — physical ragdoll setup, PD control integration, balance controller, state/reward logic, and training manager.
- `training/` — Python TCP client, Stable-Baselines3 environment adapter, PPO training/evaluation scripts, and Python tests.
- `*.md` — build notes, protocol specification, environment contract, and training instructions.

## Human–AI development

This project was developed through a human–AI collaboration. **AI was used as an independent coder and treated as an equal development partner alongside the human developer**, contributing directly to implementation and technical problem-solving—not merely autocomplete or passive code suggestions. The human developer set project goals, evaluated behavior, and remains responsible for project direction and the final integrated result.

This describes the actual development workflow; it does not imply that an AI system is a legal person or rights holder.

## License

Original project materials are dedicated to the public domain under **[CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/)**. See [LICENSE](LICENSE).

The `godot-cpp` submodule and any other third-party dependencies or separately licensed material are **not** relicensed by this dedication; they remain under their respective licenses.
