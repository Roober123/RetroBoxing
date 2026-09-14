"""Integration checks against an idle Godot server.

Run: python -m training.test_transport --port 7000
"""
import argparse
import socket
import time

import numpy as np

from . import protocol as p
from .tcp_client import RetroBoxingTCPClient


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=7000)
    args = parser.parse_args()

    def connect():
        time.sleep(0.1)
        return RetroBoxingTCPClient(port=args.port).connect()

    client = connect()
    try:
        initial = client.reset()
        count = client.arena_count
        # Fragment a STEP into single-byte writes, then coalesce two requests.
        wire = p.packet(p.STEP, p.encode_actions(np.tile(p.NEUTRAL_ACTION, (count, 1)), count))
        for byte in wire:
            client.socket.sendall(bytes([byte]))
        p.decode_step(client._receive(p.STEP), count)
        client.socket.sendall(p.packet(p.HELLO) + p.packet(p.RESET))
        p.decode_hello(client._receive(p.HELLO))
        np.testing.assert_array_equal(p.decode_observations(client._receive(p.RESET), count), initial)
        with socket.create_connection(("127.0.0.1", args.port), 2) as extra:
            assert extra.recv(1) == b""
    finally:
        client.close()

    time.sleep(0.1)
    with socket.create_connection(("127.0.0.1", args.port), 2) as raw:
        raw.sendall(p.packet(p.RESET))
        unvalidated = RetroBoxingTCPClient()
        unvalidated.socket = raw
        command, size = p.unpack_header(unvalidated._read_exact(p.HEADER.size))
        assert command == p.ERROR
        unvalidated._read_exact(size)

    malformed = [
        p.HEADER.pack(p.MAGIC, 99, p.HELLO, 0),
        p.HEADER.pack(0, p.VERSION, p.HELLO, 0),
        p.packet(99),
        p.packet(p.STEP, b"\x00" * 4),
        p.packet(p.RESET, b"\x00"),
        p.HEADER.pack(p.MAGIC, p.VERSION, p.STEP, p.MAX_PAYLOAD + 1),
    ]
    for value in (np.nan, np.inf, 1.1):
        malformed.append(p.packet(p.STEP, np.full((count, 12), value, dtype="<f4").tobytes()))
    for wire in malformed:
        client = connect()
        try:
            client.socket.sendall(wire)
            command, size = p.unpack_header(client._read_exact(p.HEADER.size))
            assert command == p.ERROR and size > 0
            client._read_exact(size)
            assert client.socket.recv(1) == b""
        finally:
            client.close()

    client = connect()
    try:
        wire = p.packet(p.STEP, p.encode_actions(np.zeros((count, 12)), count))
        client.socket.sendall(wire + wire)
        command, size = p.unpack_header(client._read_exact(p.HEADER.size))
        assert command == p.ERROR
        client._read_exact(size)
    finally:
        client.close()

    # Abruptly drop the socket during a policy step, without sending CLOSE.
    client = connect()
    client.step_async(np.zeros((count, 12)))
    client._disconnect()
    time.sleep(0.2)
    client = connect()
    try:
        np.testing.assert_array_equal(client.reset(), initial)
        result = client.step(np.tile(p.NEUTRAL_ACTION, (count, 1)))
        assert np.isfinite(result.observations).all()
    finally:
        client.close()
    print("Transport tests passed: fragmentation, coalescing, malformed packets, busy STEP, disconnect and reconnect")


if __name__ == "__main__":
    main()
