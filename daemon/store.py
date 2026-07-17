#!/usr/bin/env python3
"""SQLite-backed project summaries for the Code CCTV service."""

from __future__ import annotations

import json
import sqlite3
import threading
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any


DEFAULT_RETENTION = 2000


def utc_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def clean_text(value: Any, limit: int = 1200) -> str:
    if value is None:
        return ""
    text = " ".join(str(value).split())
    return text[:limit]


def clean_files(value: Any) -> list[str]:
    if not isinstance(value, list):
        return []
    return [clean_text(item, 500) for item in value if clean_text(item, 500)]


class StateStore:
    def __init__(self, path: Path, retention: int = DEFAULT_RETENTION) -> None:
        self.path = path.expanduser().resolve()
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.retention = max(retention, 100)
        self.connection = sqlite3.connect(self.path, check_same_thread=False)
        self.path.chmod(0o600)
        self.connection.row_factory = sqlite3.Row
        self.lock = threading.RLock()
        self.connection.execute("PRAGMA journal_mode=WAL")
        self.connection.execute("PRAGMA synchronous=NORMAL")
        self.connection.executescript(
            """
            CREATE TABLE IF NOT EXISTS projects (
                workspace TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                status TEXT NOT NULL,
                phase TEXT NOT NULL,
                focus TEXT NOT NULL,
                note TEXT NOT NULL,
                evidence TEXT NOT NULL,
                event_type TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                event_count INTEGER NOT NULL DEFAULT 0
            );
            CREATE TABLE IF NOT EXISTS events (
                id TEXT PRIMARY KEY,
                workspace TEXT NOT NULL,
                event_type TEXT NOT NULL,
                source TEXT NOT NULL,
                timestamp TEXT NOT NULL,
                phase TEXT NOT NULL,
                status TEXT NOT NULL,
                focus TEXT NOT NULL,
                note TEXT NOT NULL,
                evidence TEXT NOT NULL,
                files_json TEXT NOT NULL
            );
            CREATE INDEX IF NOT EXISTS events_workspace_timestamp
                ON events(workspace, timestamp DESC);
            """
        )
        self.connection.commit()

    def ingest(self, payload: dict[str, Any]) -> dict[str, Any]:
        workspace_raw = clean_text(payload.get("workspace"), 1000)
        if not workspace_raw:
            raise ValueError("event.workspace is required")
        workspace = str(Path(workspace_raw).expanduser().resolve())
        name = clean_text(payload.get("workspace_name"), 200) or Path(workspace).name or workspace
        event_type = clean_text(payload.get("event_type"), 80) or "progress"
        source = clean_text(payload.get("source"), 80) or "code-cctv"
        timestamp = clean_text(payload.get("timestamp"), 80) or utc_now()
        phase = clean_text(payload.get("phase"), 120)
        status = clean_text(payload.get("status"), 120) or "侦察中"
        focus = clean_text(payload.get("focus"), 500)
        note = clean_text(payload.get("note"), 1200)
        evidence = clean_text(payload.get("evidence"), 1200)
        files = clean_files(payload.get("files"))
        event_id = uuid.uuid4().hex

        with self.lock:
            self.connection.execute(
                """
                INSERT INTO events (
                    id, workspace, event_type, source, timestamp, phase,
                    status, focus, note, evidence, files_json
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    event_id,
                    workspace,
                    event_type,
                    source,
                    timestamp,
                    phase,
                    status,
                    focus,
                    note,
                    evidence,
                    json.dumps(files, ensure_ascii=False),
                ),
            )
            self.connection.execute(
                """
                INSERT INTO projects (
                    workspace, name, status, phase, focus, note, evidence,
                    event_type, updated_at, event_count
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 1)
                ON CONFLICT(workspace) DO UPDATE SET
                    name=excluded.name,
                    status=excluded.status,
                    phase=excluded.phase,
                    focus=excluded.focus,
                    note=excluded.note,
                    evidence=excluded.evidence,
                    event_type=excluded.event_type,
                    updated_at=excluded.updated_at,
                    event_count=projects.event_count + 1
                """,
                (workspace, name, status, phase, focus, note, evidence, event_type, timestamp),
            )
            self.connection.execute(
                """
                DELETE FROM events
                WHERE id IN (
                    SELECT id FROM events
                    ORDER BY timestamp DESC
                    LIMIT -1 OFFSET ?
                )
                """,
                (self.retention,),
            )
            self.connection.commit()
            return self.state_locked()

    def state(self) -> dict[str, Any]:
        with self.lock:
            return self.state_locked()

    def state_locked(self) -> dict[str, Any]:
        rows = self.connection.execute(
            """
            SELECT workspace, name, status, phase, focus, note, evidence,
                   event_type, updated_at, event_count
            FROM projects
            ORDER BY updated_at DESC
            """
        ).fetchall()
        now = datetime.now(timezone.utc)
        projects: list[dict[str, Any]] = []
        for row in rows:
            events = self.connection.execute(
                """
                SELECT id, event_type, source, timestamp, phase, status,
                       focus, note, evidence, files_json
                FROM events
                WHERE workspace = ?
                ORDER BY timestamp DESC
                LIMIT 8
                """,
                (row["workspace"],),
            ).fetchall()
            project = dict(row)
            project["active"] = self.is_active(row["updated_at"], now) or self.is_watching(row["status"])
            project["recent_events"] = [self.event_dict(event) for event in events]
            projects.append(project)

        active = sum(1 for project in projects if project["active"])
        blocked = sum(1 for project in projects if "阻塞" in project["status"] or "blocked" in project["status"].lower())
        return {
            "generated_at": utc_now(),
            "summary": {
                "total_projects": len(projects),
                "active_projects": active,
                "blocked_projects": blocked,
                "event_count": sum(project["event_count"] for project in projects),
            },
            "projects": projects,
        }

    @staticmethod
    def is_active(value: str, now: datetime) -> bool:
        try:
            timestamp = datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError:
            return False
        if timestamp.tzinfo is None:
            timestamp = timestamp.replace(tzinfo=timezone.utc)
        return now - timestamp <= timedelta(seconds=120)

    @staticmethod
    def is_watching(status: str) -> bool:
        lowered = status.casefold()
        return "监听" in status or "watch" in lowered or "running" in lowered

    @staticmethod
    def event_dict(row: sqlite3.Row) -> dict[str, Any]:
        try:
            files = json.loads(row["files_json"])
        except json.JSONDecodeError:
            files = []
        return {
            "id": row["id"],
            "event_type": row["event_type"],
            "source": row["source"],
            "timestamp": row["timestamp"],
            "phase": row["phase"],
            "status": row["status"],
            "focus": row["focus"],
            "note": row["note"],
            "evidence": row["evidence"],
            "files": files if isinstance(files, list) else [],
        }

    def close(self) -> None:
        with self.lock:
            self.connection.close()
