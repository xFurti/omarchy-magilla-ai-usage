"""OpenCode Go plan windows plus local session token totals.

Go quota comes from GET /zen/go/v1/usage with the /connect API key.
The key is read into memory and never written to Magilla state.
"""

from __future__ import annotations

import os
import sqlite3
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

import lib

AGENT_ID = "opencode"
AGENT_NAME = "OpenCode"
AUTH_HELP = "In OpenCode run /connect and paste your OpenCode Go API key."
USAGE_URL = os.environ.get("OPENCODE_GO_USAGE_URL") or "https://opencode.ai/zen/go/v1/usage"
PROBE_MIN_INTERVAL_SECONDS = 30
WINDOWS = (
  ("rolling", "5-hour limit", "5-hour"),
  ("weekly", "Weekly limit", "Weekly"),
  ("monthly", "Monthly limit", "Monthly"),
)


def _db_path() -> Path:
  override = os.environ.get("OPENCODE_DB") or ""
  if override.strip():
    return lib.expand(override)
  return lib.xdg_data() / "opencode" / "opencode.db"


def _auth_path() -> Path:
  data = lib.xdg_data() / "opencode" / "auth.json"
  if data.is_file():
    return data
  return lib.xdg_config() / "opencode" / "auth.json"


def _auth_payload() -> dict[str, Any]:
  data = lib.read_json(_auth_path())
  return data if isinstance(data, dict) else {}


def _go_api_key() -> str:
  entry = _auth_payload().get("opencode-go")
  if not isinstance(entry, dict):
    return ""
  return str(entry.get("key") or "").strip()


def _tier_label() -> str:
  payload = _auth_payload()
  if "opencode-go" in payload:
    return "OpenCode Go"
  if "opencode" in payload:
    return "OpenCode Zen"
  return ""


def _ratio(raw: Any) -> float | None:
  if raw is None or raw == "":
    return None
  try:
    n = float(raw)
  except (TypeError, ValueError):
    return None
  if n > 1:
    n = n / 100.0
  return min(1.0, max(0.0, n))


def _window_node(payload: dict[str, Any], name: str) -> dict[str, Any] | None:
  usage = payload.get("usage") if isinstance(payload.get("usage"), dict) else payload
  node = usage.get(name) if isinstance(usage, dict) else None
  if node is None:
    node = payload.get(name + "Usage")
  return node if isinstance(node, dict) else None


def _parse_go_usage(payload: dict[str, Any]) -> list[dict[str, Any]]:
  limits: list[dict[str, Any]] = []
  for name, label, title in WINDOWS:
    node = _window_node(payload, name)
    if not node:
      continue
    percent = _ratio(node.get("percent") if "percent" in node else node.get("usagePercent"))
    if percent is None:
      continue
    limits.append({
      "label": label,
      "title": title,
      "percent": percent,
      "resetsAt": str(node.get("resetsAt") or ""),
    })
  return limits


def _probe_go_usage(api_key: str) -> dict[str, Any]:
  request = urllib.request.Request(
    USAGE_URL,
    headers={
      "Authorization": "Bearer " + api_key,
      "Accept": "application/json",
      "User-Agent": "MagillaAIUsage/0.1",
    },
  )
  try:
    payload = lib.open_http_json(request, timeout=15)
  except urllib.error.HTTPError as error:
    if error.code in (401, 403):
      return {"ok": False, "auth": True, "helpText": "OpenCode Go rejected the saved API key. Run /connect again."}
    return {"ok": False, "helpText": f"OpenCode Go usage returned status {error.code}."}
  except Exception:
    return {"ok": False, "transport": True, "helpText": "Couldn't reach OpenCode Go usage. Retrying shortly."}
  if not isinstance(payload, dict):
    return {"ok": False, "helpText": "OpenCode Go usage returned an invalid response."}
  limits = _parse_go_usage(payload)
  if not limits:
    return {"ok": False, "helpText": "OpenCode Go usage returned no windows."}
  return {"ok": True, "limits": limits}


def _scan_local() -> dict[str, Any]:
  db = _db_path()
  if not db.is_file():
    return {}
  acc = lib.StatsAcc()
  try:
    conn = sqlite3.connect(db.resolve().as_uri() + "?mode=ro", uri=True, timeout=2)
  except sqlite3.Error:
    return {}
  try:
    rows = conn.execute(
      """
      SELECT id, parent_id, time_created, tokens_input, tokens_output,
             tokens_reasoning, tokens_cache_read
      FROM session
      """
    ).fetchall()
  except sqlite3.Error:
    return {}
  finally:
    try:
      conn.close()
    except sqlite3.Error:
      pass

  for row in rows:
    session_id, parent_id, created, tokens_input, tokens_output, _reasoning, cache_read = row
    if parent_id:
      continue
    day = lib.local_date_from_timestamp(created)
    usage = {
      "inputTokens": lib.number(tokens_input),
      "outputTokens": lib.number(tokens_output),
      "cachedReadTokens": lib.number(cache_read),
      "cacheCreationTokens": 0,
    }
    acc.add_session_day(str(session_id), day)
    if lib.token_total({
      "inputTokens": lib.number(tokens_input),
      "outputTokens": lib.number(tokens_output),
      "cacheReadInputTokens": lib.number(cache_read),
      "cacheCreationInputTokens": 0,
    }) > 0:
      acc.add_prompt(session_id=str(session_id), day=day, model="opencode", usage=usage)
  return acc.as_fields()


def collect(force: bool = False, limits_only: bool = False) -> dict[str, Any]:
  record = lib.base_record(AGENT_ID, AGENT_NAME, scope="account")
  local = {} if limits_only else _scan_local()
  if local:
    record.update(local)

  cache_path = lib.magilla_cache_dir() / "opencode-go-limits.json"
  cached = lib.read_json(cache_path) or {}
  fallback_limits = cached.get("limits") if isinstance(cached.get("limits"), list) else []
  api_key = _go_api_key()
  record["tierLabel"] = _tier_label()

  if not api_key:
    record["limits"] = fallback_limits
    record["ready"] = bool(fallback_limits or record.get("hasLocalStats"))
    if not record["ready"]:
      record["usageStatusText"] = "OpenCode is installed"
      record["authHelpText"] = AUTH_HELP
    return record

  fetched_at = lib.number(cached.get("fetchedAtMs")) / 1000
  if fallback_limits and not force and lib.time_now() - fetched_at < PROBE_MIN_INTERVAL_SECONDS:
    record["limits"] = fallback_limits
    record["ready"] = True
    return record

  probe = _probe_go_usage(api_key)
  if probe.get("ok"):
    snapshot = {
      "fetchedAtMs": round(lib.time_now() * 1000),
      "limits": probe.get("limits") or [],
    }
    try:
      lib.write_json(cache_path, snapshot)
    except OSError:
      pass
    record["limits"] = snapshot["limits"]
    record["ready"] = True
    return record

  record["limits"] = fallback_limits
  record["ready"] = bool(fallback_limits or record.get("hasLocalStats"))
  if probe.get("transport"):
    record["retryAdvised"] = True
  if probe.get("auth"):
    record["usageStatusText"] = "OpenCode Go sign-in rejected"
    record["authHelpText"] = AUTH_HELP
  elif not fallback_limits:
    record["usageStatusText"] = "OpenCode Go limits unavailable"
    record["authHelpText"] = str(probe.get("helpText") or AUTH_HELP)
  return record
