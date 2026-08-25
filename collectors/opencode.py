"""OpenCode local session stats from the SQLite ledger.

Does not read account or credential tables beyond COUNT(*) during detection.
Token totals come from session rows (parent sessions only).
"""

from __future__ import annotations

import os
import sqlite3
from pathlib import Path
from typing import Any

import lib

AGENT_ID = "opencode"
AGENT_NAME = "OpenCode"
AUTH_HELP = "Sign in to OpenCode to start recording sessions."


def _db_path() -> Path:
  override = os.environ.get("OPENCODE_DB") or ""
  if override.strip():
    return lib.expand(override)
  return lib.xdg_data() / "opencode" / "opencode.db"


def collect(force: bool = False, limits_only: bool = False) -> dict[str, Any]:
  del force
  record = lib.base_record(AGENT_ID, AGENT_NAME, scope="device")
  db = _db_path()
  if not db.is_file():
    record["usageStatusText"] = "No OpenCode sessions yet"
    record["authHelpText"] = AUTH_HELP
    return record
  if limits_only:
    previous = lib.read_json(lib.magilla_usage_dir() / "opencode.json")
    if previous:
      previous["updatedAt"] = lib.iso_now()
      return previous

  acc = lib.StatsAcc()
  try:
    conn = sqlite3.connect(db.resolve().as_uri() + "?mode=ro", uri=True, timeout=2)
  except sqlite3.Error:
    record["usageStatusText"] = "OpenCode database busy"
    record["authHelpText"] = "Retry in a moment — OpenCode may have the file locked."
    record["retryAdvised"] = True
    return record

  try:
    rows = conn.execute(
      """
      SELECT id, parent_id, time_created, tokens_input, tokens_output,
             tokens_reasoning, tokens_cache_read
      FROM session
      """
    ).fetchall()
  except sqlite3.Error:
    conn.close()
    record["usageStatusText"] = "OpenCode database unreadable"
    return record
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

  record.update(acc.as_fields())
  record["ready"] = record.get("hasLocalStats") is True
  if not record["ready"]:
    record["usageStatusText"] = "OpenCode is installed"
    record["authHelpText"] = "Sessions will appear here after you chat in OpenCode."
  return record
