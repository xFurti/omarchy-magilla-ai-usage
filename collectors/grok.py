"""Grok / SuperGrok usage: local session stats plus the billing pool.

Local tokens come from $GROK_HOME/sessions/**/updates.jsonl turn_completed
usage objects. Subscription limits come from the same cli-chat-proxy billing
endpoint Grok's own UI uses. Auth tokens are never written to disk by Magilla.
"""

from __future__ import annotations

import json
import os
import urllib.error
import urllib.request
from typing import Any

import lib

AGENT_ID = "grok"
AGENT_NAME = "Grok"
AUTH_HELP = "Run `grok login` to restore SuperGrok usage."
BILLING_URL = os.environ.get("GROK_BILLING_URL") or "https://cli-chat-proxy.grok.com/v1/billing?format=credits"
SETTINGS_URL = os.environ.get("GROK_SETTINGS_URL") or "https://cli-chat-proxy.grok.com/v1/settings"
TOKEN_AUTH = "xai-grok-cli"
PROBE_MIN_INTERVAL_SECONDS = 20


def _oauth_login() -> dict[str, Any] | None:
  data = lib.read_json(lib.grok_home() / "auth.json")
  if not data:
    return None
  now = lib.utc_now()
  best: dict[str, Any] | None = None
  best_expiry = None
  for entry in data.values():
    if not isinstance(entry, dict):
      continue
    mode = str(entry.get("auth_mode") or "")
    if mode not in ("oidc", "oauth", ""):
      continue
    key = str(entry.get("key") or "").strip()
    if key == "" or key.startswith("sk-") or key.startswith("xai-"):
      continue
    expires = lib.parse_iso(entry.get("expires_at"))
    if best is None:
      best = entry
      best_expiry = expires
      continue
    if expires and (best_expiry is None or expires > best_expiry):
      best = entry
      best_expiry = expires
    elif expires is None and best_expiry is not None and best_expiry < now:
      best = entry
      best_expiry = expires
  return best


def _scan_local() -> dict[str, Any]:
  acc = lib.StatsAcc()
  root = lib.grok_home() / "sessions"
  if not root.is_dir():
    return acc.as_fields()

  for updates in root.rglob("updates.jsonl"):
    session_id = updates.parent.name
    session_day = ""
    last_by_prompt: dict[str, dict[str, Any]] = {}
    try:
      lines = updates.read_text(encoding="utf-8", errors="replace").splitlines()
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
      params = payload.get("params") if isinstance(payload.get("params"), dict) else {}
      update = params.get("update") if isinstance(params.get("update"), dict) else {}
      kind = str(update.get("session_kind") or params.get("session_kind") or "")
      if kind.startswith("subagent"):
        continue
      usage = update.get("usage") if isinstance(update.get("usage"), dict) else None
      event = str(update.get("event_name") or update.get("sessionUpdate") or "")
      if usage is None and event != "turn_completed":
        continue
      if usage is None:
        continue
      prompt_id = str(update.get("prompt_id") or params.get("promptId") or "")
      model = "grok"
      model_usage = usage.get("modelUsage")
      if isinstance(model_usage, dict) and model_usage:
        model = str(next(iter(model_usage.keys())))
      stamp = payload.get("timestamp") or params.get("timestamp")
      day = lib.local_date_from_timestamp(stamp) if stamp is not None else ""
      last_by_prompt[prompt_id or f"{session_id}:{len(last_by_prompt)}"] = {
        "day": day,
        "model": model,
        "usage": usage,
      }
      if day:
        session_day = day
    if not session_day:
      try:
        session_day = lib.local_date_from_timestamp(updates.stat().st_mtime)
      except OSError:
        session_day = lib.date_string()
    if last_by_prompt:
      acc.add_session_day(session_id, session_day)
    for prompt_id, item in last_by_prompt.items():
      acc.add_prompt(
        session_id=session_id,
        day=item["day"] or session_day,
        model=item["model"],
        usage=item["usage"],
      )
  return acc.as_fields()


def _cent_value(raw: Any) -> float | None:
  if not isinstance(raw, dict):
    return None
  try:
    return max(0.0, float(raw.get("val") or 0) / 100.0)
  except (TypeError, ValueError):
    return None


def _period_label(period_type: str) -> str:
  text = period_type.upper()
  if "WEEK" in text:
    return "Weekly"
  if "MONTH" in text:
    return "Monthly"
  if "DAY" in text:
    return "Daily"
  return "Usage"


def _parse_limits(config: dict[str, Any]) -> list[dict[str, Any]]:
  limits: list[dict[str, Any]] = []
  period = config.get("currentPeriod") if isinstance(config.get("currentPeriod"), dict) else {}
  period_type = str((period or {}).get("type") or "")
  resets_at = str((period or {}).get("end") or config.get("billingPeriodEnd") or "")
  starts_at = str((period or {}).get("start") or config.get("billingPeriodStart") or "")
  label = _period_label(period_type) if period_type else "Usage"

  percent: float | None = None
  raw_percent = config.get("creditUsagePercent")
  if raw_percent is None and (period or config.get("billingPeriodEnd")):
    percent = 0.0
  elif raw_percent is not None:
    try:
      percent = min(1.0, max(0.0, float(raw_percent) / 100.0))
    except (TypeError, ValueError):
      percent = None

  if percent is None:
    used = _cent_value(config.get("used"))
    cap = _cent_value(config.get("monthlyLimit"))
    if used is not None and cap and cap > 0:
      percent = min(1.0, used / cap)
      if not period_type:
        label = "Monthly"

  if percent is not None:
    limits.append({
      "label": f"{label} limit",
      "title": label,
      "percent": percent,
      "resetsAt": resets_at,
      "startsAt": starts_at,
    })

  on_cap = _cent_value(config.get("onDemandCap"))
  on_used = _cent_value(config.get("onDemandUsed"))
  if on_cap and on_cap > 0 and on_used is not None:
    limits.append({
      "label": "On-demand",
      "title": "On-demand",
      "percent": min(1.0, on_used / on_cap),
      "resetsAt": resets_at,
    })
  return limits


def _parse_balance(config: dict[str, Any]) -> dict[str, Any] | None:
  remaining = _cent_value(config.get("prepaidBalance"))
  if remaining is None or remaining <= 0:
    return None
  return {
    "remaining": remaining,
    "funded": 0,
    "spent": 0,
    "currency": "USD",
    "estimated": False,
  }


def _auth_headers(access_token: str, user_id: str) -> dict[str, str]:
  return {
    "Authorization": "Bearer " + access_token,
    "X-XAI-Token-Auth": TOKEN_AUTH,
    "Accept": "application/json",
    "x-userid": user_id,
    "x-grok-client-version": os.environ.get("GROK_CLIENT_VERSION", "1.0.5"),
  }


def _fetch_tier(access_token: str, user_id: str) -> str:
  request = urllib.request.Request(SETTINGS_URL, headers=_auth_headers(access_token, user_id))
  try:
    payload = lib.open_http_json(request, timeout=10)
  except Exception:
    return ""
  if not isinstance(payload, dict):
    return ""
  for key in ("subscription_tier_display", "subscriptionTierDisplay", "subscription_tier"):
    value = str(payload.get(key) or "").strip()
    if value:
      return lib.safe_display_text(value)
  return ""


def _probe_billing(access_token: str, user_id: str) -> dict[str, Any]:
  request = urllib.request.Request(BILLING_URL, headers=_auth_headers(access_token, user_id))
  try:
    payload = lib.open_http_json(request, timeout=15)
  except urllib.error.HTTPError as error:
    if error.code in (401, 403):
      return {"ok": False, "auth": True, "helpText": "Grok rejected the saved sign-in. Run `grok login`."}
    return {"ok": False, "helpText": f"Grok billing returned status {error.code}."}
  except Exception:
    return {
      "ok": False,
      "transport": True,
      "helpText": "Couldn't reach Grok's billing endpoint. Retrying shortly.",
    }

  if not isinstance(payload, dict):
    return {"ok": False, "helpText": "Grok billing returned an invalid response."}
  config = payload.get("config")
  if not isinstance(config, dict):
    return {"ok": False, "helpText": "Grok billing returned no credits config."}

  limits = _parse_limits(config)
  balance = _parse_balance(config)
  tier = _fetch_tier(access_token, user_id)
  if not tier:
    for key in ("subscriptionTier", "subscription_tier", "subscription_tier_display", "tier"):
      value = payload.get(key) or config.get(key)
      if value and not str(value).isdigit():
        tier = str(value)
        break
  if not limits and not balance:
    return {"ok": False, "helpText": "Grok billing returned no usage limits.", "tierLabel": tier}
  return {"ok": True, "limits": limits, "balance": balance, "tierLabel": tier}


def collect(force: bool = False, limits_only: bool = False) -> dict[str, Any]:
  local = {} if limits_only else _scan_local()
  login = _oauth_login()
  cache_path = lib.magilla_cache_dir() / "grok-limits.json"
  cached = lib.read_json(cache_path) or {}
  fallback_limits = cached.get("limits") if isinstance(cached.get("limits"), list) else []
  fallback_balance = cached.get("balance") if isinstance(cached.get("balance"), dict) else None
  fallback_tier = str(cached.get("tierLabel") or "")

  record = lib.base_record(AGENT_ID, AGENT_NAME, scope="account")
  if local:
    record.update(local)

  if login is None or not str(login.get("key") or "").strip():
    record.update({
      "limits": fallback_limits,
      "balance": fallback_balance,
      "tierLabel": fallback_tier,
      "ready": bool(fallback_limits or fallback_balance or record.get("hasLocalStats")),
      "usageStatusText": "Waiting for auth",
      "authHelpText": AUTH_HELP,
    })
    return record

  expires = lib.parse_iso(login.get("expires_at"))
  expired = expires is not None and expires <= lib.utc_now()
  fetched_at = lib.number(cached.get("fetchedAtMs")) / 1000
  if fallback_limits and not force and not expired and lib.time_now() - fetched_at < PROBE_MIN_INTERVAL_SECONDS:
    record.update({
      "ready": True,
      "limits": fallback_limits,
      "balance": fallback_balance,
      "tierLabel": fallback_tier,
    })
    return record

  probe = _probe_billing(str(login.get("key") or ""), str(login.get("user_id") or ""))
  if probe.get("ok"):
    snapshot = {
      "fetchedAtMs": round(lib.time_now() * 1000),
      "limits": probe.get("limits") or [],
      "balance": probe.get("balance"),
      "tierLabel": probe.get("tierLabel") or "",
    }
    try:
      lib.write_json(cache_path, snapshot)
    except OSError:
      pass
    record.update({
      "ready": True,
      "limits": snapshot["limits"],
      "balance": snapshot["balance"],
      "tierLabel": snapshot["tierLabel"],
    })
    return record

  record.update({
    "limits": fallback_limits,
    "balance": fallback_balance,
    "tierLabel": fallback_tier or str(probe.get("tierLabel") or ""),
    "ready": bool(fallback_limits or fallback_balance or record.get("hasLocalStats")),
  })
  if probe.get("transport"):
    record["retryAdvised"] = True
  if expired or probe.get("auth"):
    record["usageStatusText"] = "Sign-in expired" if expired else "Grok limits unavailable"
    record["authHelpText"] = AUTH_HELP
  elif not fallback_limits:
    record["usageStatusText"] = "Grok limits unavailable"
    record["authHelpText"] = str(probe.get("helpText") or AUTH_HELP)
  return record
