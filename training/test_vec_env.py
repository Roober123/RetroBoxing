import unittest
from unittest.mock import patch, MagicMock

import numpy as np

from .protocol import StepResult
from .retro_boxing_vec_env import RetroBoxingVecEnv


class VecEnvTests(unittest.TestCase):
    def test_terminal_mapping_and_episode_accounting(self):
        client = MagicMock()
        client.arena_count = 3
        obs = np.zeros((3, 175), dtype=np.float32)
        terminal = np.ones_like(obs)
        client.reset.return_value = obs
        client.step_wait.return_value = StepResult(
            obs, np.array([1, 2, 3], dtype=np.float32),
            np.array([True, False, False]), np.array([False, True, False]),
            np.array([True, True, False]), terminal)
        with patch("training.retro_boxing_vec_env.RetroBoxingTCPClient") as factory:
            factory.return_value.connect.return_value = client
            env = RetroBoxingVecEnv()
        try:
            env.reset()
            _, _, dones, infos = env.step(np.zeros((3, 12)))
            np.testing.assert_array_equal(dones, [True, True, False])
            self.assertFalse(infos[0]["TimeLimit.truncated"])
            self.assertTrue(infos[1]["TimeLimit.truncated"])
            self.assertNotIn("terminal_observation", infos[2])
            self.assertEqual(infos[0]["episode"], {"r": 1.0, "l": 1, "duration": 1 / 60})
            np.testing.assert_array_equal(infos[1]["terminal_observation"], terminal[1])
            terminal.fill(0)
            self.assertTrue(infos[1]["terminal_observation"].all())
            np.testing.assert_array_equal(env._episode_rewards, [0, 0, 3])
            env.step_async(np.zeros((3, 12)))
            env.reset()
            with self.assertRaises(RuntimeError):
                env.step_wait()
            np.testing.assert_array_equal(env._episode_lengths, [0, 0, 0])
        finally:
            env.close()
            env.close()


if __name__ == "__main__":
    unittest.main()
