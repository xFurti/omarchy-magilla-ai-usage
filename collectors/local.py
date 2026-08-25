"""Lightweight collectors for tools that leave CLI / config traces.

Gemini, Copilot, Crush, and Pi rarely expose a public quota API from the
desktop. Magilla still lists them when they are installed and records any
local session totals we can read without touching credentials.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import lib


def _scan_jsonl_tokens(root: Path, glob: str = "**/*.jsonl") -> dict[str, Any]:
  acc = lib.StatsAcc()
  if not root.is_dir():
    return acc.as_fields()
  for path in root.glob(glob):
    if not path.is_file():
      continue
    session_id = path.parent.name or path.stem
    day = lib.local_date_from_timestamp(path.stat().st_mtime)
    had_usage = False
    try:
      lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
      continue
    for line in lines:
      line = line.strip()
      if not line:
        continue
      try:
        payload = json.loads(line)
      except json.JSONDecodeError:
        continue
      if not isinstance(payload, dict):
        continue
      usage = payload.get("usage") if isinstance(payload.get("usage"), dict) else None
      if usage is None and isinstance(payload.get("message"), dict):
        usage = payload["message"].get("usage") if isinstance(payload["message"].get("usage"), dict) else None
      if not usage:
        continue
      model = str(payload.get("model") or payload.get("modelId") or path.stem)
      stamp = payload.get("timestamp") or payload.get("time") or payload.get("createdAt")
      prompt_day = lib.local_date_from_timestamp(stamp) if stamp is not None else day
      acc.add_prompt(session_id=session_id, day=prompt_day, model=model, usage=usage)
      had_usage = True
    if had_usage:
      acc.add_session_day(session_id, day)
  return acc.as_fields()


def collect_gemini(force: bool = False, limits_only: bool = False) -> dict[str, Any]:
  del force, limits_only
  record = lib.base_record("gemini", "Gemini", scope="device")
  homes = [
    lib.expand("~/.gemini"),
    lib.xdg_config() / "gemini",
    lib.xdg_config() / "gemini-cli",
  ]
  stats = lib.empty_stats()
  for home in homes:
    for child in ("tmp", "sessions", "projects"):
      found = _scan_jsonl_tokens(home / child)
      if found.get("hasLocalStats"):
        stats = found
        break
    if stats.get("hasLocalStats"):
      break
  record.update(stats)
  record["ready"] = bool(record.get("hasLocalStats"))
  if not record["ready"]:
    record["usageStatusText"] = "Gemini CLI detected" if lib.which("gemini") else "Gemini not signed in"
    record["authHelpText"] = "Run `gemini` and sign in. Quota meters are not published by the CLI yet."
  return record


def collect_copilot(force: bool = False, limits_only: bool = False) -> dict[str, Any]:
  del force, limits_only
  record = lib.base_record("copilot", "GitHub Copilot", scope="account")
  record["ready"] = False
  record["usageStatusText"] = "Copilot CLI detected" if lib.which("copilot") else "Copilot not signed in"
  record["authHelpText"] = "GitHub does not expose Copilot quota to this widget yet. Detection still tracks the install."
  return record


def collect_crush(force: bool = False, limits_only: bool = False) -> dict[str, Any]:
  del force, limits_only
  record = lib.base_record("crush", "Crush", scope="device")
  homes = [lib.xdg_data() / "crush", lib.xdg_config() / "crush", lib.expand("~/.crush")]
  stats = lib.empty_stats()
  for home in homes:
    found = _scan_jsonl_tokens(home)
    if found.get("hasLocalStats"):
      stats = found
      break
  record.update(stats)
  record["ready"] = bool(record.get("hasLocalStats"))
  if not record["ready"]:
    record["usageStatusText"] = "Crush CLI detected" if lib.which("crush") else "Crush not signed in"
    record["authHelpText"] = "Session totals appear here once Crush writes local logs."
  return record


def collect_pi(force: bool = False, limits_only: bool = False) -> dict[str, Any]:
  del force, limits_only
  record = lib.base_record("pi", "Pi", scope="device")
  sessions = lib.expand("~/.pi/agent/sessions")
  stats = _scan_jsonl_tokens(sessions)
  record.update(stats)
  record["ready"] = bool(record.get("hasLocalStats"))
  if not record["ready"]:
    record["usageStatusText"] = "Pi detected" if lib.which("pi") else "Pi not signed in"
    record["authHelpText"] = "Run `pi` to create a session. Magilla reads local token totals only."
  return record
