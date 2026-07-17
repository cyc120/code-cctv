from __future__ import annotations

import json
import tempfile
import threading
import unittest
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from daemon.server import CodeCCTVServer
from daemon.store import StateStore


class StateStoreTests(unittest.TestCase):
    def test_ingest_builds_global_project_summary(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            workspace = Path(directory) / "demo"
            workspace.mkdir()
            store = StateStore(Path(directory) / "state.sqlite3")
            state = store.ingest(
                {
                    "workspace": str(workspace),
                    "event_type": "progress",
                    "source": "test",
                    "status": "验证中",
                    "phase": "测试",
                    "focus": "检查服务",
                    "note": "只保存摘要",
                    "files": ["src/main.py"],
                }
            )

            self.assertEqual(state["summary"]["total_projects"], 1)
            self.assertEqual(state["summary"]["active_projects"], 1)
            self.assertEqual(state["projects"][0]["name"], "demo")
            self.assertEqual(state["projects"][0]["recent_events"][0]["files"], ["src/main.py"])
            store.close()

    def test_watching_status_stays_active_after_event_timeout(self) -> None:
        self.assertTrue(StateStore.is_watching("监听中"))
        self.assertTrue(StateStore.is_watching("Watching"))
        self.assertFalse(StateStore.is_watching("完成"))


class ServerTests(unittest.TestCase):
    def test_http_api_authenticates_and_ingests_event(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            store = StateStore(Path(directory) / "state.sqlite3")
            server = CodeCCTVServer(("127.0.0.1", 0), "test-token", store)
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            base_url = f"http://127.0.0.1:{server.server_address[1]}"
            try:
                request = Request(f"{base_url}/api/state")
                with self.assertRaises(HTTPError) as error:
                    try:
                        urlopen(request, timeout=1)
                    except HTTPError as raised:
                        raised.close()
                        raise
                self.assertEqual(error.exception.code, 401)

                payload = json.dumps({"workspace": directory, "status": "侦察中"}).encode()
                request = Request(
                    f"{base_url}/api/events",
                    data=payload,
                    method="POST",
                    headers={"Content-Type": "application/json", "X-Code-CCTV-Token": "test-token"},
                )
                with urlopen(request, timeout=1) as response:
                    body = json.loads(response.read())
                self.assertTrue(body["ok"])
                self.assertEqual(body["state"]["summary"]["total_projects"], 1)
            finally:
                server.shutdown()
                server.server_close()
                store.close()
                thread.join(timeout=1)


if __name__ == "__main__":
    unittest.main()
