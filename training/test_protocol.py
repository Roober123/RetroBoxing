import socket
import threading
import unittest

import numpy as np

from . import protocol as p
from .tcp_client import RetroBoxingTCPClient


class ProtocolTests(unittest.TestCase):
    def test_header_and_metadata(self):
        self.assertEqual(p.packet(p.HELLO), b"RBX1\x01\x00\x01\x00\x00\x00\x00\x00")
        self.assertEqual(p.decode_hello(p.METADATA.pack(1, 2, 175, 12, 240, 60))["arena_count"], 2)
        for values in [(2, 2, 175, 12, 240, 60), (1, 0, 175, 12, 240, 60), (1, 2, 174, 12, 240, 60)]:
            with self.assertRaises(p.ProtocolError):
                p.decode_hello(p.METADATA.pack(*values))

    def test_actions(self):
        self.assertEqual(len(p.encode_actions(np.zeros((2, 12)), 2)), 96)
        for actions in [np.zeros((1, 12)), np.full((2, 12), np.nan), np.full((2, 12), np.inf), np.full((2, 12), 1.1)]:
            with self.assertRaises(ValueError):
                p.encode_actions(actions, 2)

    def test_terminal_layout(self):
        obs = np.zeros((2, 175), dtype="<f4")
        terminal = np.ones_like(obs)
        payload = obs.tobytes() + np.array([1, 2], dtype="<f4").tobytes() + bytes([1, 0, 0, 1, 1, 1]) + terminal.tobytes()
        result = p.decode_step(payload, 2)
        np.testing.assert_array_equal(result.terminated, [True, False])
        np.testing.assert_array_equal(result.truncated, [False, True])
        np.testing.assert_array_equal(result.terminal_observations, terminal)
        with self.assertRaises(p.ProtocolError):
            p.decode_step(payload[:-1], 2)

    def test_fragmented_response_and_eof(self):
        receiver, sender = socket.socketpair()
        receiver.settimeout(2)
        client = RetroBoxingTCPClient()
        client.socket = receiver
        payload = p.METADATA.pack(1, 2, 175, 12, 240, 60)

        def send():
            try:
                for byte in p.packet(p.HELLO, payload):
                    sender.sendall(bytes([byte]))
            finally:
                sender.close()

        worker = threading.Thread(target=send)
        worker.start()
        try:
            self.assertEqual(client._receive(p.HELLO), payload)
            with self.assertRaises(ConnectionError):
                client._receive(p.HELLO)
            self.assertIsNone(client.socket)
        finally:
            client.close()
            worker.join()


if __name__ == "__main__":
    unittest.main()
