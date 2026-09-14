"""Compare neutral action and a saved PPO policy under the same server settings."""
import argparse
import json

import numpy as np
import torch
from stable_baselines3 import PPO

from .protocol import NEUTRAL_ACTION
from .retro_boxing_vec_env import RetroBoxingVecEnv


def evaluate(env, model, episodes):
    obs = env.reset()
    results = []
    # Equal episode quotas per arena avoid bias toward short-lived arenas.
    targets = np.array([(episodes + i) // env.num_envs for i in range(env.num_envs)])
    counts = np.zeros(env.num_envs, dtype=int)
    while (counts < targets).any():
        actions = (np.tile(NEUTRAL_ACTION, (env.num_envs, 1)) if model is None
                   else model.predict(obs, deterministic=True)[0])
        obs, _, dones, infos = env.step(actions)
        for i, done in enumerate(dones):
            if done and counts[i] < targets[i]:
                results.append(infos[i]["episode"])
                counts[i] += 1
    return {"episodes": len(results),
            "success_rate": float(np.mean([x["success"] for x in results])),
            "failure_rate": float(np.mean([not x["success"] for x in results])),
            "average_episode_duration": float(np.mean([x["duration"] for x in results])),
            "average_episode_reward": float(np.mean([x["r"] for x in results]))}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=7000)
    parser.add_argument("--episodes", type=int, default=10)
    parser.add_argument("--model", required=True)
    args = parser.parse_args()
    if args.episodes < 1:
        parser.error("--episodes must be positive")
    torch.set_num_threads(1)
    env = RetroBoxingVecEnv(port=args.port)
    try:
        baseline = evaluate(env, None, args.episodes)
        print("Neutral:", json.dumps(baseline), flush=True)
        policy = evaluate(env, PPO.load(args.model, env=env, device="cpu"), args.episodes)
        policy["ready_to_advance"] = policy["success_rate"] >= 0.85 and policy["average_episode_duration"] >= 9.0
        print("PPO:", json.dumps(policy), flush=True)
        print("PPO survived longer:", policy["average_episode_duration"] > baseline["average_episode_duration"])
    finally:
        env.close()


if __name__ == "__main__":
    main()
