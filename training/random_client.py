"""Run with: python -m training.random_client --steps 10000."""
import argparse
import time

import numpy as np

from .tcp_client import RetroBoxingTCPClient
from .protocol import NEUTRAL_ACTION


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=7000)
    parser.add_argument("--steps", type=int, default=10000)
    parser.add_argument("--seed", type=int, default=0)
    args = parser.parse_args()
    rng = np.random.default_rng(args.seed)
    completed = 0
    start = time.perf_counter()
    with RetroBoxingTCPClient(args.host, args.port) as client:
        print(client.metadata, flush=True)
        initial = client.reset()
        assert initial.dtype == np.float32 and np.all(initial[:, -12:] == NEUTRAL_ACTION)
        for step in range(args.steps):
            actions = rng.uniform(-1, 1, (client.arena_count, 12)).astype(np.float32)
            result = client.step(actions)
            done = result.terminated | result.truncated
            assert np.all(result.observations[done, -12:] == NEUTRAL_ACTION)
            np.testing.assert_array_equal(result.terminal_observations[done, -12:], actions[done])
            np.testing.assert_array_equal(result.observations[~done, -12:], actions[~done])
            completed += int(done.sum())
            if (step + 1) % 1000 == 0:
                print(f"{step + 1} steps, {completed} episodes, {(step + 1) / (time.perf_counter() - start):.1f} batch steps/s", flush=True)
        np.testing.assert_array_equal(client.reset(), initial)
    # The server polls disconnects once per frame.
    time.sleep(0.1)
    with RetroBoxingTCPClient(args.host, args.port) as client:
        np.testing.assert_array_equal(client.reset(), initial)
        client.step(np.tile(NEUTRAL_ACTION, (client.arena_count, 1)))
    print(f"Random TCP test passed: {args.steps} steps; reconnect passed", flush=True)


if __name__ == "__main__":
    main()
