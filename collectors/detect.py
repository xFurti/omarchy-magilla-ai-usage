"""Extensible detection of AI coding tools.

Paths honor environment variables and XDG locations. Detection never reads
token values — only whether an auth file or CLI is present.
"""

from __future__ import annotations

import os
import sqlite3
from pathlib import Path
from typing import Any, Callable

import lib


def _cli(names: list[str]) -> str:
  for name in names:
    found = lib.which(name)
    if found:
      return Path(found).name
  return ""


def _auth_json_has_key(path: Path, key_fields: tuple[str, ...] = ("key", "access_token", "token")) -> bool:
  data = lib.read_json(path)
  if not data:
    return lib.non_empty_file(path)

  def walk(node: Any) -> bool:
    if isinstance(node, dict):
      for field in key_fields:
        value = node.get(field)
        if isinstance(value, str) and value.strip():
          return True
      return any(walk(value) for value in node.values())
    if isinstance(node, list):
      return any(walk(value) for value in node)
    return False

  return walk(data)


def detect_grok() -> dict[str, Any]:
  home = lib.grok_home()
  auth = home / "auth.json"
  cli = _cli(["grok"])
  traces: list[str] = []
  if cli:
    traces.append("CLI " + cli)
  if home.is_dir():
    traces.append(lib.display_path(home))
  if auth.is_file():
    traces.append(lib.display_path(auth))
  installed = bool(cli or home.is_dir())
  authenticated = _auth_json_has_key(auth)
  return _result("grok", "Grok", cli, installed, authenticated, traces)


def detect_cursor() -> dict[str, Any]:
  config = lib.cursor_config_dir()
  db = config / "User" / "globalStorage" / "state.vscdb"
  cursor_home = lib.expand(os.environ.get("CURSOR_USER_DIR") or "~/.cursor")
  cli = _cli(["cursor", "cursor-agent"])
  traces: list[str] = []
  if cli:
    traces.append("CLI " + cli)
  if db.is_file():
    traces.append(lib.display_path(db))
  elif cursor_home.is_dir():
    traces.append(lib.display_path(cursor_home))
  authenticated = False
  if db.is_file():
    try:
      conn = sqlite3.connect(db.resolve().as_uri() + "?mode=ro", uri=True, timeout=2)
      try:
        row = conn.execute(
          "SELECT length(value) FROM ItemTable WHERE key = ?",
          ("cursorAuth/accessToken",),
        ).fetchone()
        authenticated = bool(row and int(row[0] or 0) > 8)
      finally:
        conn.close()
    except sqlite3.Error:
      authenticated = False
  installed = bool(cli or db.is_file() or cursor_home.is_dir())
  return _result("cursor", "Cursor", cli, installed, authenticated, traces)


def detect_claude() -> dict[str, Any]:
  home = lib.claude_home()
  cli = _cli(["claude"])
  traces: list[str] = []
  if cli:
    traces.append("CLI " + cli)
  if home.is_dir():
    traces.append(lib.display_path(home))
  credentials = home / ".credentials.json"
  if not credentials.is_file():
    credentials = home / "credentials.json"
  authenticated = lib.non_empty_file(credentials)
  if credentials.is_file():
    traces.append(lib.display_path(credentials))
  return _result("claude", "Claude Code", cli, bool(cli or home.is_dir()), authenticated, traces)


def detect_codex() -> dict[str, Any]:
  home = lib.codex_home()
  cli = _cli(["codex"])
  traces: list[str] = []
  if cli:
    traces.append("CLI " + cli)
  if home.is_dir():
    traces.append(lib.display_path(home))
  auth = home / "auth.json"
  authenticated = lib.non_empty_file(auth)
  if auth.is_file():
    traces.append(lib.display_path(auth))
  return _result("codex", "Codex", cli, bool(cli or home.is_dir()), authenticated, traces)


def detect_opencode() -> dict[str, Any]:
  config = lib.xdg_config() / "opencode"
  data = lib.xdg_data() / "opencode"
  db = data / "opencode.db"
  auth = data / "auth.json"
  if not auth.is_file():
    auth = config / "auth.json"
  cli = _cli(["opencode"])
  traces: list[str] = []
  if cli:
    traces.append("CLI " + cli)
  if config.is_dir():
    traces.append(lib.display_path(config))
  if db.is_file():
    traces.append(lib.display_path(db))
  if auth.is_file():
    traces.append(lib.display_path(auth))
  # OpenCode Go / Zen /connect stores API keys in auth.json. The SQLite
  # account/credential tables are a different login path and are often empty.
  authenticated = _auth_json_has_key(auth)
  if not authenticated and db.is_file():
    try:
      conn = sqlite3.connect(db.resolve().as_uri() + "?mode=ro", uri=True, timeout=2)
      try:
        accounts = conn.execute("SELECT COUNT(*) FROM account").fetchone()
        creds = conn.execute("SELECT COUNT(*) FROM credential").fetchone()
        authenticated = bool((accounts and accounts[0]) or (creds and creds[0]))
      finally:
        conn.close()
    except sqlite3.Error:
      authenticated = False
  installed = bool(cli or config.is_dir() or data.is_dir())
  return _result("opencode", "OpenCode", cli, installed, authenticated, traces)


def detect_fireworks() -> dict[str, Any]:
  env_key = bool(os.environ.get("FIREWORKS_API_KEY"))
  auth = lib.home() / ".fireworks" / "auth.ini"
  cli = _cli(["firectl"])
  traces: list[str] = []
  if env_key:
    traces.append("FIREWORKS_API_KEY")
  if auth.is_file():
    traces.append(lib.display_path(auth))
  if cli:
    traces.append("CLI " + cli)
  installed = env_key or auth.is_file() or bool(cli)
  return _result("fireworks", "Fireworks", cli, installed, env_key or lib.non_empty_file(auth), traces)


def detect_gemini() -> dict[str, Any]:
  homes = [
    lib.expand(os.environ.get("GEMINI_CONFIG_DIR") or "~/.gemini"),
    lib.xdg_config() / "gemini",
    lib.xdg_config() / "gemini-cli",
  ]
  cli = _cli(["gemini"])
  traces: list[str] = []
  if cli:
    traces.append("CLI " + cli)
  if os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY"):
    traces.append("GEMINI_API_KEY")
  authenticated = bool(os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY"))
  installed = bool(cli)
  for path in homes:
    if path.is_dir():
      traces.append(lib.display_path(path))
      installed = True
      oauth = path / "oauth_creds.json"
      google = path / "google_accounts.json"
      if lib.non_empty_file(oauth) or lib.non_empty_file(google):
        authenticated = True
  return _result("gemini", "Gemini", cli, installed, authenticated, traces)


def detect_copilot() -> dict[str, Any]:
  homes = [
    lib.xdg_config() / "github-copilot",
    lib.home() / ".copilot",
    lib.xdg_data() / "github-copilot",
  ]
  cli = _cli(["copilot"])
  traces: list[str] = []
  if cli:
    traces.append("CLI " + cli)
  installed = bool(cli)
  authenticated = False
  for path in homes:
    if path.exists():
      traces.append(lib.display_path(path))
      installed = True
      hosts = path / "hosts.yml"
      apps = path / "apps.json"
      if lib.non_empty_file(hosts) or lib.non_empty_file(apps):
        authenticated = True
  return _result("copilot", "GitHub Copilot", cli, installed, authenticated, traces)


def detect_crush() -> dict[str, Any]:
  homes = [lib.xdg_config() / "crush", lib.xdg_data() / "crush", lib.home() / ".crush"]
  cli = _cli(["crush"])
  traces: list[str] = []
  if cli:
    traces.append("CLI " + cli)
  installed = bool(cli)
  authenticated = False
  for path in homes:
    if path.exists():
      traces.append(lib.display_path(path))
      installed = True
      if lib.non_empty_file(path / "config.json") or lib.non_empty_file(path / "auth.json"):
        authenticated = True
  return _result("crush", "Crush", cli, installed, authenticated, traces)


def detect_pi() -> dict[str, Any]:
  home = lib.expand(os.environ.get("PI_HOME") or "~/.pi")
  agent = home / "agent"
  cli = _cli(["pi", "omp"])
  traces: list[str] = []
  if cli:
    traces.append("CLI " + cli)
  if home.is_dir():
    traces.append(lib.display_path(home))
  auth = agent / "auth.json"
  authenticated = lib.non_empty_file(auth)
  if auth.is_file():
    traces.append(lib.display_path(auth))
  return _result("pi", "Pi", cli, bool(cli or home.is_dir()), authenticated, traces)


def _result(provider_id: str, name: str, cli: str, installed: bool, authenticated: bool, traces: list[str]) -> dict[str, Any]:
  return {
    "id": provider_id,
    "name": name,
    "cli": cli,
    "installed": installed,
    "authenticated": authenticated,
    "detected": installed or authenticated,
    "traces": traces,
  }


DETECTORS: list[tuple[str, Callable[[], dict[str, Any]]]] = [
  ("grok", detect_grok),
  ("cursor", detect_cursor),
  ("claude", detect_claude),
  ("codex", detect_codex),
  ("opencode", detect_opencode),
  ("fireworks", detect_fireworks),
  ("gemini", detect_gemini),
  ("copilot", detect_copilot),
  ("crush", detect_crush),
  ("pi", detect_pi),
]


def scan() -> dict[str, Any]:
  providers = []
  for _provider_id, detector in DETECTORS:
    try:
      providers.append(detector())
    except Exception as exc:
      providers.append({
        "id": _provider_id,
        "name": _provider_id,
        "cli": "",
        "installed": False,
        "authenticated": False,
        "detected": False,
        "traces": [],
        "error": str(exc),
      })
  return {
    "schemaVersion": 1,
    "updatedAt": lib.iso_now(),
    "providers": providers,
  }
