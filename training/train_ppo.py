"""Small PPO training entry point with CSV/TensorBoard logging and resume."""
import argparse
from pathlib import Path

import numpy as np
import torch
from stable_baselines3 import PPO
from stable_baselines3.common.callbacks import BaseCallback
from stable_baselines3.common.logger import configure

from .retro_boxing_vec_env import RetroBoxingVecEnv


class EpisodeLogging(BaseCallback):
    def __init__(self):
        super().__init__()
        self.failed = self.timed_out = 0

    def _on_step(self):
        for done, info in zip(self.locals["dones"], self.locals["infos"]):
            if done:
                self.logger.record_mean("rollout/episode_duration_seconds", info["episode"]["duration"])
                self.logger.record_mean("rollout/episode_reward", info["episode"]["r"])
                self.logger.record_mean("rollout/success_rate", float(info["TimeLimit.truncated"]))
                self.logger.record_mean("rollout/failure_rate", float(not info["TimeLimit.truncated"]))
                self.timed_out += int(info["TimeLimit.truncated"])
                self.failed += int(not info["TimeLimit.truncated"])
        self.logger.record("rollout/failed_episodes", self.failed)
        self.logger.record("rollout/timed_out_episodes", self.timed_out)
        # Training diagnostics from the previous update must remain finite.
        for key, value in self.logger.name_to_value.items():
            if key.startswith("train/") and isinstance(value, (int, float, np.number)):
                if not np.isfinite(value):
                    raise FloatingPointError(f"Non-finite PPO metric: {key}")
        return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=7000)
    parser.add_argument("--timesteps", type=int, default=10000)
    parser.add_argument("--seed", type=int, default=0)
    parser.add_argument("--model", default="training/models/ppo_balance_v2")
    parser.add_argument("--resume", help="Saved PPO zip to continue training")
    parser.add_argument("--log-dir", default="training/runs/ppo_v2")
    args = parser.parse_args()
    if Path(args.model).with_suffix(".zip").exists():
        parser.error("Output model already exists; choose a new --model path to preserve checkpoints")
    torch.set_num_threads(1)
    env = RetroBoxingVecEnv(args.host, args.port)
    try:
        if args.resume:
            model = PPO.load(args.resume, env=env, device="cpu", n_steps=512, gamma=0.997, gae_lambda=0.95)
        else:
            model = PPO("MlpPolicy", env, n_steps=512, batch_size=64, gamma=0.997, gae_lambda=0.95,
                        verbose=1, seed=args.seed, device="cpu")
        model.set_logger(configure(args.log_dir, ["stdout", "csv", "tensorboard"]))
        model.learn(total_timesteps=args.timesteps, callback=EpisodeLogging(),
                    reset_num_timesteps=not bool(args.resume))
        if not all(torch.isfinite(value).all() for value in model.policy.state_dict().values()):
            raise FloatingPointError("Non-finite policy weights")
        for key, value in model.logger.name_to_value.items():
            if key.startswith("train/") and isinstance(value, (int, float, np.number)) and not np.isfinite(value):
                raise FloatingPointError(f"Non-finite final PPO metric: {key}")
        model.logger.dump(model.num_timesteps)
        Path(args.model).parent.mkdir(parents=True, exist_ok=True)
        model.save(args.model)
        print(f"Saved PPO model to {args.model}")
    finally:
        env.close()


if __name__ == "__main__":
    main()
