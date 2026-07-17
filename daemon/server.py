#!/usr/bin/env python3
"""Threaded localhost HTTP and SSE server for Code CCTV."""

from __future__ import annotations

import hmac
import json
import queue
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from threading import Lock
from typing import Any
from urllib.parse import urlparse

from .store import StateStore


MAX_BODY_BYTES = 1_000_000


class CodeCCTVServer(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True

    def __init__(self, address: tuple[str, int], token: str, store: StateStore) -> None:
        super().__init__(address, CodeCCTVHandler)
        self.token = token
        self.store = store
        self.subscribers: set[queue.Queue[dict[str, Any]]] = set()
        self.subscriber_lock = Lock()

    def subscribe(self) -> queue.Queue[dict[str, Any]]:
        subscriber: queue.Queue[dict[str, Any]] = queue.Queue(maxsize=4)
        with self.subscriber_lock:
            self.subscribers.add(subscriber)
        return subscriber

    def unsubscribe(self, subscriber: queue.Queue[dict[str, Any]]) -> None:
        with self.subscriber_lock:
            self.subscribers.discard(subscriber)

    def publish(self, state: dict[str, Any]) -> None:
        message = {"type": "state", "state": state}
        with self.subscriber_lock:
            subscribers = list(self.subscribers)
        for subscriber in subscribers:
            try:
                subscriber.put_nowait(message)
            except queue.Full:
                try:
                    subscriber.get_nowait()
                    subscriber.put_nowait(message)
                except queue.Empty:
                    pass


class CodeCCTVHandler(BaseHTTPRequestHandler):
    server: CodeCCTVServer
    protocol_version = "HTTP/1.1"

    def log_message(self, format: str, *args: object) -> None:
        return

    def authorized(self) -> bool:
        supplied = self.headers.get("X-Code-CCTV-Token", "")
        return bool(supplied) and hmac.compare_digest(supplied, self.server.token)

    def send_json(self, payload: dict[str, Any], status: int = HTTPStatus.OK) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def require_auth(self) -> bool:
        if self.authorized():
            return True
        self.send_json({"error": "unauthorized"}, HTTPStatus.UNAUTHORIZED)
        return False

    def do_OPTIONS(self) -> None:
        self.send_response(HTTPStatus.NO_CONTENT)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, X-Code-CCTV-Token")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.end_headers()

    def do_GET(self) -> None:
        route = urlparse(self.path).path
        if route == "/health":
            self.send_json({"ok": True, "service": "code-cctv"})
            return
        if not self.require_auth():
            return
        if route == "/api/state":
            self.send_json(self.server.store.state())
            return
        if route == "/api/stream":
            self.stream_state()
            return
        self.send_json({"error": "not found"}, HTTPStatus.NOT_FOUND)

    def do_POST(self) -> None:
        if not self.require_auth():
            return
        route = urlparse(self.path).path
        if route != "/api/events":
            self.send_json({"error": "not found"}, HTTPStatus.NOT_FOUND)
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            length = 0
        if length <= 0 or length > MAX_BODY_BYTES:
            self.send_json({"error": "invalid body size"}, HTTPStatus.BAD_REQUEST)
            return
        try:
            payload = json.loads(self.rfile.read(length).decode("utf-8"))
            if not isinstance(payload, dict):
                raise ValueError("event must be an object")
            state = self.server.store.ingest(payload)
        except (UnicodeDecodeError, json.JSONDecodeError, ValueError) as error:
            self.send_json({"error": str(error)}, HTTPStatus.BAD_REQUEST)
            return
        self.server.publish(state)
        self.send_json({"ok": True, "state": state}, HTTPStatus.ACCEPTED)

    def stream_state(self) -> None:
        subscriber = self.server.subscribe()
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", "text/event-stream; charset=utf-8")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "keep-alive")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        try:
            self.write_sse({"type": "state", "state": self.server.store.state()})
            while True:
                try:
                    message = subscriber.get(timeout=20)
                except queue.Empty:
                    self.wfile.write(b": heartbeat\n\n")
                    self.wfile.flush()
                    continue
                self.write_sse(message)
        except (BrokenPipeError, ConnectionResetError, OSError):
            pass
        finally:
            self.server.unsubscribe(subscriber)

    def write_sse(self, payload: dict[str, Any]) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.wfile.write(b"data: " + body + b"\n\n")
        self.wfile.flush()
