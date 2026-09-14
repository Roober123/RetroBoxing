"""One synchronous request at a time, with split send/receive for VecEnv."""
import socket

from . import protocol as p


class RetroBoxingTCPClient:
    def __init__(self, host="127.0.0.1", port=7000, timeout=30.0):
        self.host, self.port, self.timeout = host, port, timeout
        self.socket = None
        self.metadata = None
        self._step_pending = False

    def connect(self):
        if self.socket is not None:
            raise RuntimeError("Already connected")
        self.socket = socket.create_connection((self.host, self.port), self.timeout)
        self.socket.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        try:
            self.hello()
        except Exception:
            self._disconnect()
            raise
        return self

    @property
    def arena_count(self):
        if self.metadata is None:
            raise RuntimeError("Connect and validate HELLO first")
        return self.metadata["arena_count"]

    def _read_exact(self, size):
        data = bytearray()
        while len(data) < size:
            chunk = self.socket.recv(size - len(data))
            if not chunk:
                raise ConnectionError("Godot disconnected")
            data.extend(chunk)
        return bytes(data)

    def _send(self, command, payload=b""):
        if self.socket is None:
            raise RuntimeError("Not connected")
        try:
            self.socket.sendall(p.packet(command, payload))
        except OSError:
            self._disconnect()
            raise

    def _receive(self, expected):
        try:
            command, size = p.unpack_header(self._read_exact(p.HEADER.size))
            expected_size = {p.HELLO: 24, p.RESET: (self.metadata or {}).get("arena_count", 0) * 175 * 4,
                             p.STEP: (self.metadata or {}).get("arena_count", 0) * (175 * 8 + 7)}[expected]
            if command != p.ERROR and (command != expected or size != expected_size):
                raise p.ProtocolError("Unexpected response command or length")
            data = self._read_exact(size)
            if command == p.ERROR:
                raise p.ProtocolError(data.decode("utf-8", errors="replace"))
            return data
        except (OSError, p.ProtocolError):
            self._disconnect()
            raise

    def _idle(self):
        if self._step_pending:
            raise RuntimeError("A STEP response is pending")

    def hello(self):
        self._idle()
        self._send(p.HELLO)
        try:
            self.metadata = p.decode_hello(self._receive(p.HELLO))
        except p.ProtocolError:
            self._disconnect()
            raise
        return self.metadata

    def reset(self):
        self._idle()
        count = self.arena_count
        self._send(p.RESET)
        try:
            return p.decode_observations(self._receive(p.RESET), count)
        except p.ProtocolError:
            self._disconnect()
            raise

    def step_async(self, actions):
        self._idle()
        self._send(p.STEP, p.encode_actions(actions, self.arena_count))
        self._step_pending = True

    def step_wait(self):
        if not self._step_pending:
            raise RuntimeError("No STEP is pending")
        try:
            return p.decode_step(self._receive(p.STEP), self.arena_count)
        except p.ProtocolError:
            self._disconnect()
            raise
        finally:
            self._step_pending = False

    def step(self, actions):
        self.step_async(actions)
        return self.step_wait()

    def _disconnect(self):
        if self.socket is not None:
            self.socket.close()
        self.socket = None
        self.metadata = None
        self._step_pending = False

    def close(self):
        try:
            if self.socket is not None:
                self._send(p.CLOSE)
        except OSError:
            pass
        finally:
            self._disconnect()

    def __enter__(self):
        return self.connect()

    def __exit__(self, *_):
        self.close()
