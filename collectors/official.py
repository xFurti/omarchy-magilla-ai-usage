"""Bridge to Omarchy's first-party usage collectors.

Claude, Codex, and Fireworks already ship as `omarchy-agent-usage-<id>`.
Magilla reuses those binaries when present and otherwise copies any record
already sitting in Omarchy's usage directory.
"""

from __future__ import annotations

import os
import subprocess
from pathlib import Path
from typing import Any

import lib

OFFICIAL_AGENTS = (
  ("claude", "Claude Code"),
  ("codex", "Codex"),
  ("fireworks", "Fireworks"),
)


def _collector_path(agent_id: str) -> Path | None:
  name = f"omarchy-agent-usage-{agent_id}"
  which = lib.which(name)
  if which:
    return Path(which)
  packaged = lib.omarchy_path() / "bin" / name
  if packaged.is_file() and os.access(packaged, os.X_OK):
    return packaged
  return None


_MAX_STDOUT = 262_144


def _run_collector(path: Path, force: bool, limits_only: bool) -> dict[str, Any] | None:
  command = [str(path)]
  if force:
    command.append("--force")
  if limits_only:
    command.append("--limits-only")
  try:
    proc = subprocess.Popen(
      command,
      stdout=subprocess.PIPE,
      stderr=subprocess.DEVNULL,
    )
  except OSError:
    return None
  try:
    stdout, _stderr = proc.communicate(timeout=20)
  except subprocess.TimeoutExpired:
    proc.kill()
    try:
      proc.communicate(timeout=2)
    except Exception:
      pass
    return None
  if proc.returncode != 0 or not stdout:
    return None
  if len(stdout) > _MAX_STDOUT:
    return None
  try:
    import json
    payload = json.loads(stdout.decode("utf-8", errors="replace"))
  except json.JSONDecodeError:
    return None
  return payload if isinstance(payload, dict) else None


def collect_official(agent_id: str, name: str, force: bool, limits_only: bool) -> dict[str, Any]:
  path = _collector_path(agent_id)
  if path is not None:
    record = _run_collector(path, force, limits_only)
    if record:
      record.setdefault("id", agent_id)
      record.setdefault("name", name)
      return record

  existing = lib.read_json(lib.omarchy_usage_dir() / f"{agent_id}.json")
  if existing:
    existing.setdefault("id", agent_id)
    existing.setdefault("name", name)
    return existing

  record = lib.base_record(agent_id, name)
  record["usageStatusText"] = f"{name} collector unavailable"
  record["authHelpText"] = f"Install the {name} CLI, or wait for Omarchy's usage updater."
  return record


def collect_all(force: bool, limits_only: bool) -> list[dict[str, Any]]:
  return [collect_official(agent_id, name, force, limits_only) for agent_id, name in OFFICIAL_AGENTS]
