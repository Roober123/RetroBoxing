"""Manual VecEnv contract check: python -m training.check_vec_env."""
import argparse

import numpy as np

from .protocol import NEUTRAL_ACTION
from .retro_boxing_vec_env import RetroBoxingVecEnv


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=7000)
    parser.add_argument("--steps", type=int, default=1000)
    args = parser.parse_args()
    env = RetroBoxingVecEnv(port=args.port)
    rng = np.random.default_rng(0)
    completed = 0
    try:
        initial = env.reset()
        for _ in range(args.steps):
            actions = rng.uniform(-1, 1, (env.num_envs, 12)).astype(np.float32)
            obs, rewards, dones, infos = env.step(actions)
            assert obs.shape == (env.num_envs, 175) and obs.dtype == np.float32
            assert rewards.shape == dones.shape == (env.num_envs,)
            assert rewards.dtype == np.float32 and dones.dtype == bool
            assert np.isfinite(obs).all() and np.isfinite(rewards).all()
            assert len(infos) == env.num_envs and np.all(np.abs(obs) <= 5)
            for i, info in enumerate(infos):
                assert isinstance(info["TimeLimit.truncated"], bool)
                if dones[i]:
                    np.testing.assert_array_equal(info["terminal_observation"][-12:], actions[i])
                    np.testing.assert_array_equal(obs[i, -12:], NEUTRAL_ACTION)
                    assert info["episode"]["l"] > 0
                    completed += 1
        env.step_async(actions)
        np.testing.assert_array_equal(env.reset(), initial)
        try:
            env.step_wait()
        except RuntimeError:
            pass
        else:
            raise AssertionError("reset did not cancel pending step")
    finally:
        env.close()
    print(f"VecEnv check passed: {args.steps} steps, {completed} completed episodes")


if __name__ == "__main__":
    main()
