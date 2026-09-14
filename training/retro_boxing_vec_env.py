"""SB3 adaptation only; Godot owns rewards, terminal states and auto-reset."""
import numpy as np
from gymnasium import spaces
from stable_baselines3.common.vec_env import VecEnv

from .tcp_client import RetroBoxingTCPClient


class RetroBoxingVecEnv(VecEnv):
    render_mode = None

    def __init__(self, host="127.0.0.1", port=7000, timeout=30.0):
        self.client = RetroBoxingTCPClient(host, port, timeout).connect()
        try:
            super().__init__(self.client.arena_count,
                             spaces.Box(-5, 5, shape=(175,), dtype=np.float32),
                             spaces.Box(-1, 1, shape=(12,), dtype=np.float32))
        except Exception:
            self.client.close()
            raise
        self._waiting = False
        self._episode_rewards = np.zeros(self.num_envs, dtype=np.float64)
        self._episode_lengths = np.zeros(self.num_envs, dtype=np.int64)

    def reset(self):
        # Complete and discard any in-flight step before RESET, as VecEnv
        # permits reset() to cancel an outstanding asynchronous step.
        if self._waiting:
            try:
                self.client.step_wait()
            finally:
                self._waiting = False
        observations = self.client.reset()
        self._episode_rewards.fill(0)
        self._episode_lengths.fill(0)
        self.reset_infos = [{} for _ in range(self.num_envs)]
        return observations

    def step_async(self, actions):
        if self._waiting:
            raise RuntimeError("A STEP is already pending")
        self.client.step_async(actions)
        self._waiting = True

    def step_wait(self):
        if not self._waiting:
            raise RuntimeError("No STEP is pending")
        try:
            result = self.client.step_wait()
        finally:
            self._waiting = False
        dones = result.terminated | result.truncated
        self._episode_rewards += result.rewards
        self._episode_lengths += 1
        infos = []
        for i in range(self.num_envs):
            info = {"TimeLimit.truncated": bool(result.truncated[i] and not result.terminated[i])}
            if dones[i]:
                info["terminal_observation"] = result.terminal_observations[i].copy()
                info["episode"] = {"r": float(self._episode_rewards[i]),
                                   "l": int(self._episode_lengths[i]),
                                   "duration": float(self._episode_lengths[i] / 60),
                                   "success": info["TimeLimit.truncated"]}
                self._episode_rewards[i] = 0
                self._episode_lengths[i] = 0
            infos.append(info)
        return result.observations, result.rewards, dones, infos

    def close(self):
        self.client.close()
        self._waiting = False

    def get_attr(self, attr_name, indices=None):
        if attr_name not in ("render_mode", "observation_space", "action_space"):
            raise AttributeError(f"TCP environment does not expose {attr_name!r}")
        return [getattr(self, attr_name) for _ in self._get_indices(indices)]

    def set_attr(self, attr_name, value, indices=None):
        raise NotImplementedError("Protocol v1 does not support changing Godot attributes")

    def env_method(self, method_name, *method_args, indices=None, **method_kwargs):
        raise NotImplementedError("Protocol v1 does not support remote method calls")

    def env_is_wrapped(self, wrapper_class, indices=None):
        return [False for _ in self._get_indices(indices)]

    def seed(self, seed=None):
        # Resets in Godot are deterministic; v1 has no remote RNG seed command.
        self.action_space.seed(seed)
        return [None] * self.num_envs

    def set_options(self, options=None):
        if options and (not isinstance(options, list) or any(options)):
            raise NotImplementedError("Protocol v1 does not support reset options")
