"""Codex plan windows via the local app-server.

Omarchy's collector asks `account/read` before the rate-limit method. On
current Codex builds that call does not answer, so the 5-hour and weekly
windows never arrive. This module reads `account/rateLimits/read` directly
and keeps only percents, plan name, and reset times.
"""

from __future__ import annotations

import json
import os
import re
import select
import shutil
import subprocess
import time
from datetime import datetime, timedelta, timezone
from typing import Any

import lib

PROBE_MIN_INTERVAL_SECONDS = 30
_PLAN_LABELS = {
  "plus": "Plus",
  "pro": "Pro",
  "team": "Team",
  "business": "Business",
  "enterprise": "Enterprise",
  "free": "Free",
}
# The packaged collector leaves this text in place even after a successful read.
_STALE_AUTH = {
  "account/read",
  "Run `codex login` to authenticate.",
}
_HOUR = re.compile(r"(\d+)\s*h(?:our)?")
_MINUTE = re.compile(r"(\d+)\s*m(?:in)?")


def _env() -> dict[str, str]:
  home = str(lib.home())
  env = os.environ.copy()
  parts = [
    env.get("PATH", ""),
    home + "/.local/bin",
    home + "/.npm-global/bin",
    home + "/.local/share/mise/shims",
  ]
  env["PATH"] = os.pathsep.join(part for part in parts if part)
  return env


def _rpc(proc: subprocess.Popen[str], request_id: int, method: str, params: dict[str, Any] | None, timeout: float) -> dict[str, Any] | None:
  assert proc.stdin is not None and proc.stdout is not None
  proc.stdin.write(json.dumps({"id": request_id, "method": method, "params": params or {}}) + "\n")
  proc.stdin.flush()
  deadline = time.time() + timeout
  while time.time() < deadline:
    ready, _, _ = select.select([proc.stdout], [], [], 0.25)
    if not ready:
      continue
    line = proc.stdout.readline()
    if not line:
      break
    try:
      message = json.loads(line)
    except json.JSONDecodeError:
      continue
    if message.get("id") == request_id and isinstance(message, dict):
      return message
  return None


def _iso(unix_seconds: float) -> str:
  return datetime.fromtimestamp(unix_seconds, timezone.utc).isoformat()


def _window(raw: dict[str, Any]) -> dict[str, Any] | None:
  try:
    used = float(raw.get("usedPercent"))
    mins = int(raw.get("windowDurationMins") or 0)
  except (TypeError, ValueError):
    return None
  if used != used:
    return None
  # Codex reports whole percentages: 9 means 9%, not a 0–1 fraction.
  percent = min(1.0, max(0.0, used / 100.0))
  resets_at = ""
  starts_at = ""
  try:
    reset = float(raw.get("resetsAt") or 0)
  except (TypeError, ValueError):
    reset = 0
  if reset > 1e12:
    reset = reset / 1000.0
  if reset > 0:
    resets_at = _iso(reset)
    if mins > 0:
      starts_at = _iso(reset - mins * 60)
  if mins == 10080:
    label, title, kind = "Weekly (7-day)", "Weekly", "weekly"
  elif mins and mins % 60 == 0:
    hours = mins // 60
    label = f"{hours}h window"
    title = "5-hour" if hours == 5 else f"{hours}-hour"
    kind = "5-hour" if hours == 5 else "session"
  elif mins:
    label, title, kind = f"{mins}m window", f"{mins}m", "session"
  else:
    label, title, kind = "Limit", "Limit", ""
  entry = {
    "label": label,
    "title": title,
    "percent": percent,
    "resetsAt": resets_at,
    "startsAt": starts_at,
  }
  if kind:
    entry["kind"] = kind
  return entry


def _infer(label: str, title: str, kind: str) -> tuple[str, str, int]:
  """Return title, kind, and window length in seconds."""
  if kind == "weekly":
    return title or "Weekly", "weekly", 7 * 24 * 3600
  if kind == "5-hour":
    return title or "5-hour", "5-hour", 5 * 3600
  text = f"{label} {title}".lower().replace("-", "")
  if "week" in text or kind == "weekly":
    return "Weekly", "weekly", 7 * 24 * 3600
  hours = _HOUR.search(text)
  if hours:
    count = int(hours.group(1))
    if count == 5:
      return "5-hour", "5-hour", 5 * 3600
    return f"{count}-hour", "session", count * 3600
  minutes = _MINUTE.search(text)
  if minutes:
    count = int(minutes.group(1))
    return f"{count}m", "session", count * 60
  return title or "Limit", kind, 0


def complete_window(entry: dict[str, Any]) -> dict[str, Any] | None:
  """Fill kind and startsAt on a window that already has a percent.

  Omarchy's collector stores the percent and the reset, but not the kind or
  the window start. The pace line needs both.
  """
  if not isinstance(entry, dict) or "percent" not in entry:
    return None
  try:
    percent = float(entry["percent"])
  except (TypeError, ValueError):
    return None
  if percent != percent:
    return None
  if percent > 1:
    percent = percent / 100.0
  percent = min(1.0, max(0.0, percent))
  label = str(entry.get("label") or "")
  title = str(entry.get("title") or "")
  kind = str(entry.get("kind") or "")
  title, kind, duration = _infer(label, title, kind)
  resets_at = str(entry.get("resetsAt") or "")
  starts_at = str(entry.get("startsAt") or "")
  if not starts_at and resets_at and duration > 0:
    try:
      reset = datetime.fromisoformat(resets_at)
      starts_at = (reset - timedelta(seconds=duration)).isoformat()
    except ValueError:
      starts_at = ""
  completed = {
    "label": label or title or "Limit",
    "title": title or "Limit",
    "percent": percent,
    "resetsAt": resets_at,
    "startsAt": starts_at,
  }
  if kind:
    completed["kind"] = kind
  return completed


def _has_percent(limits: Any) -> bool:
  return isinstance(limits, list) and any(isinstance(item, dict) and "percent" in item for item in limits)


def windows_from_result(result: dict[str, Any]) -> tuple[list[dict[str, Any]], str]:
  rate = result.get("rateLimits") if isinstance(result.get("rateLimits"), dict) else {}
  raw_windows: list[dict[str, Any]] = []
  for slot in ("primary", "secondary"):
    window = rate.get(slot)
    if isinstance(window, dict):
      raw_windows.append(window)
  if not raw_windows and isinstance(result.get("rateLimitsByLimitId"), dict):
    for bucket in result["rateLimitsByLimitId"].values():
      if not isinstance(bucket, dict):
        continue
      for slot in ("primary", "secondary"):
        window = bucket.get(slot)
        if isinstance(window, dict):
          raw_windows.append(window)
  limits: list[dict[str, Any]] = []
  seen: set[tuple[Any, Any]] = set()
  for raw in raw_windows:
    entry = _window(raw)
    if not entry:
      continue
    key = (raw.get("windowDurationMins"), raw.get("resetsAt"))
    if key in seen:
      continue
    seen.add(key)
    limits.append(entry)
  plan = str(rate.get("planType") or "")
  return limits, _PLAN_LABELS.get(plan.strip().lower(), lib.safe_display_text(plan))


def _read_cached(force: bool) -> dict[str, Any] | None:
  if force:
    return None
  cached = lib.read_json(lib.magilla_cache_dir() / "codex-limits.json") or {}
  fetched = lib.number(cached.get("fetchedAtMs")) / 1000
  limits = cached.get("limits")
  if not isinstance(limits, list) or not limits:
    return None
  if lib.time_now() - fetched >= PROBE_MIN_INTERVAL_SECONDS:
    return None
  return cached


def _probe() -> dict[str, Any] | None:
  env = _env()
  binary = shutil.which("codex", path=env.get("PATH"))
  if not binary:
    return None
  try:
    proc = subprocess.Popen(
      [binary, "-s", "read-only", "-a", "on-request", "app-server"],
      stdin=subprocess.PIPE,
      stdout=subprocess.PIPE,
      stderr=subprocess.DEVNULL,
      text=True,
      env=env,
    )
  except OSError:
    return None
  try:
    init = _rpc(proc, 1, "initialize", {"clientInfo": {"name": "magilla-ai-usage", "version": "1"}}, 8)
    if not init or "error" in init:
      return None
    assert proc.stdin is not None
    proc.stdin.write(json.dumps({"method": "initialized", "params": {}}) + "\n")
    proc.stdin.flush()
    message = _rpc(proc, 2, "account/rateLimits/read", {}, 12)
  finally:
    try:
      proc.terminate()
      proc.wait(timeout=1)
    except Exception:
      try:
        proc.kill()
      except Exception:
        pass
  if not message or not isinstance(message.get("result"), dict):
    return None
  limits, tier = windows_from_result(message["result"])
  if not limits:
    return None
  return {"limits": limits, "tierLabel": tier}


def _apply(record: dict[str, Any], fresh: dict[str, Any]) -> dict[str, Any]:
  completed: list[dict[str, Any]] = []
  for item in fresh.get("limits") or []:
    if not isinstance(item, dict):
      continue
    entry = complete_window(item)
    if entry:
      completed.append(entry)
  if not completed:
    return record
  record["limits"] = completed
  raw_tier = str(fresh.get("tierLabel") or record.get("tierLabel") or "")
  pretty = _PLAN_LABELS.get(raw_tier.strip().lower())
  if pretty:
    record["tierLabel"] = pretty
  elif raw_tier and not record.get("tierLabel"):
    record["tierLabel"] = lib.safe_display_text(raw_tier)
  if record.get("usageStatusText") in ("", "Codex limits unavailable"):
    record["usageStatusText"] = ""
  if record.get("authHelpText") in _STALE_AUTH:
    record["authHelpText"] = ""
  record["ready"] = True
  return record


def fill_windows(record: dict[str, Any], force: bool = False) -> dict[str, Any]:
  """Add Codex quota windows when the official collector returned none."""
  if _has_percent(record.get("limits")):
    return _apply(record, {"limits": record.get("limits"), "tierLabel": record.get("tierLabel") or ""})
  cached = _read_cached(force)
  fresh = cached if cached is not None else _probe()
  if not fresh:
    return record
  if cached is None:
    try:
      lib.write_json(lib.magilla_cache_dir() / "codex-limits.json", {
        "fetchedAtMs": round(lib.time_now() * 1000),
        "limits": fresh.get("limits") or [],
        "tierLabel": fresh.get("tierLabel") or "",
      })
    except OSError:
      pass
  return _apply(record, fresh)
