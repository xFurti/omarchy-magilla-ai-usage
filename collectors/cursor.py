"""Cursor plan usage via the local app session.

Reads the access token length from Cursor's state.vscdb (never copies the
token into Magilla state) and asks the same dashboard RPCs the Cursor app
uses for included Ultra / plan usage.
"""

from __future__ import annotations

import os
import sqlite3
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import lib

AGENT_ID = "cursor"
AGENT_NAME = "Cursor"
AUTH_HELP = "Sign in to the Cursor app to restore plan usage."
PLAN_URL = os.environ.get("CURSOR_PLAN_URL") or "https://api2.cursor.sh/aiserver.v1.DashboardService/GetPlanInfo"
USAGE_URL = os.environ.get("CURSOR_USAGE_URL") or "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage"
PROBE_MIN_INTERVAL_SECONDS = 20


def _state_db() -> Path:
  return lib.cursor_config_dir() / "User" / "globalStorage" / "state.vscdb"


def _read_item(db: Path, key: str) -> str:
  if not db.is_file():
    return ""
  try:
    conn = sqlite3.connect(db.resolve().as_uri() + "?mode=ro", uri=True, timeout=2)
  except sqlite3.Error:
    return ""
  try:
    row = conn.execute("SELECT value FROM ItemTable WHERE key = ?", (key,)).fetchone()
  except sqlite3.Error:
    return ""
  finally:
    conn.close()
  return str(row[0] or "") if row else ""


def _ms_to_iso(value: Any) -> str:
  raw = str(value or "").strip()
  if not raw:
    return ""
  try:
    ms = int(raw)
    if ms < 1e12:
      ms *= 1000
    return datetime.fromtimestamp(ms / 1000, timezone.utc).isoformat()
  except (TypeError, ValueError, OSError, OverflowError):
    return raw


def _used_ratio(value: Any) -> float | None:
  try:
    n = float(value)
  except (TypeError, ValueError):
    return None
  if n != n:
    return None
  if n > 1:
    n = n / 100.0
  return min(1.0, max(0.0, n))


def _dashboard_post(url: str, token: str) -> dict[str, Any]:
  request = urllib.request.Request(
    url,
    data=b"{}",
    method="POST",
    headers={
      "Authorization": "Bearer " + token,
      "Accept": "application/json",
      "Content-Type": "application/json",
      "User-Agent": "MagillaAIUsage/0.1",
    },
  )
  try:
    with urllib.request.urlopen(request, timeout=15) as response:
      payload = lib.read_http_json(response)
  except urllib.error.HTTPError as error:
    if error.code in (401, 403):
      return {"ok": False, "auth": True, "helpText": "Cursor rejected the saved sign-in. Open Cursor and sign in."}
    return {"ok": False, "helpText": f"Cursor usage returned status {error.code}."}
  except Exception:
    return {"ok": False, "transport": True, "helpText": "Couldn't reach Cursor's usage endpoint. Retrying shortly."}
  return {"ok": True, "payload": payload if isinstance(payload, dict) else {}}


def _parse_usage(plan: dict[str, Any], usage: dict[str, Any]) -> dict[str, Any]:
  info = plan.get("planInfo") if isinstance(plan.get("planInfo"), dict) else {}
  bucket = usage.get("planUsage") if isinstance(usage.get("planUsage"), dict) else {}
  start = _ms_to_iso(usage.get("billingCycleStart"))
  end = _ms_to_iso(usage.get("billingCycleEnd") or info.get("billingCycleEnd"))
  tier = str(info.get("planName") or "").strip()
  limits: list[dict[str, Any]] = []
  cursor_models = _used_ratio(bucket.get("autoPercentUsed"))
  other_models = _used_ratio(bucket.get("apiPercentUsed"))
  if cursor_models is not None:
    limits.append({
      "label": "Cursor models",
      "title": "Cursor models",
      "percent": cursor_models,
      "resetsAt": end,
      "startsAt": start,
    })
  if other_models is not None:
    limits.append({
      "label": "Other models",
      "title": "Other models",
      "percent": other_models,
      "resetsAt": end,
      "startsAt": start,
    })
  if not limits:
    total = _used_ratio(bucket.get("totalPercentUsed") or usage.get("totalPercentUsed"))
    if total is not None:
      limits.append({
        "label": "Monthly included",
        "title": "Monthly",
        "percent": total,
        "resetsAt": end,
        "startsAt": start,
      })
  if not limits:
    return {}
  return {"ready": True, "tierLabel": tier or "Cursor", "limits": limits}


def collect(force: bool = False, limits_only: bool = False) -> dict[str, Any]:
  del limits_only
  db = _state_db()
  token = _read_item(db, "cursorAuth/accessToken")
  membership = _read_item(db, "cursorAuth/stripeMembershipType")
  cache_path = lib.magilla_cache_dir() / "cursor-limits.json"
  cached = lib.read_json(cache_path) or {}
  fallback = cached.get("record") if isinstance(cached.get("record"), dict) else None

  if not token:
    record = lib.base_record(
      AGENT_ID,
      AGENT_NAME,
      scope="account",
      usageStatusText="Waiting for auth",
      authHelpText=AUTH_HELP,
      tierLabel=membership.title() if membership else "",
    )
    if fallback:
      record.update({k: fallback[k] for k in ("limits", "balance", "tierLabel") if k in fallback})
      record["ready"] = True
    return record

  fetched_at = float(cached.get("fetchedAtMs") or 0) / 1000
  if fallback and not force and lib.time_now() - fetched_at < PROBE_MIN_INTERVAL_SECONDS:
    record = lib.base_record(AGENT_ID, AGENT_NAME, scope="account", ready=True)
    record.update(fallback)
    return record

  plan = _dashboard_post(PLAN_URL, token)
  usage = _dashboard_post(USAGE_URL, token)
  if not plan["ok"] or not usage["ok"]:
    failed = plan if not plan["ok"] else usage
    record = lib.base_record(AGENT_ID, AGENT_NAME, scope="account")
    if fallback:
      record.update({k: fallback[k] for k in ("limits", "balance", "tierLabel") if k in fallback})
      record["ready"] = True
    if failed.get("transport"):
      record["retryAdvised"] = True
    if failed.get("auth") or not fallback:
      record["usageStatusText"] = "Cursor usage unavailable"
      record["authHelpText"] = str(failed.get("helpText") or AUTH_HELP)
    if membership and not record.get("tierLabel"):
      record["tierLabel"] = membership.title()
    return record

  parsed = _parse_usage(plan.get("payload") or {}, usage.get("payload") or {})
  if not parsed:
    record = lib.base_record(
      AGENT_ID,
      AGENT_NAME,
      scope="account",
      usageStatusText="Cursor usage unavailable",
      authHelpText="Cursor returned no included usage.",
      tierLabel=membership.title() if membership else "",
    )
    return record

  snapshot = {"fetchedAtMs": round(lib.time_now() * 1000), "record": parsed}
  try:
    lib.write_json(cache_path, snapshot)
  except OSError:
    pass
  record = lib.base_record(AGENT_ID, AGENT_NAME, scope="account")
  record.update(parsed)
  if membership and not record.get("tierLabel"):
    record["tierLabel"] = membership.title()
  return record
