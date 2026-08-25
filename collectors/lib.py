"""Shared path helpers and the Omarchy usage-record contract.

Collectors print one JSON object the panel already understands. Credentials
never leave the process: they are read into memory, used for a request if
needed, and discarded. Cache files store percents and plan names only.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import tempfile
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Iterator

# Hard cap for authenticated HTTP JSON (billing/plan payloads are tiny).
MAX_HTTP_JSON_BYTES = 1_048_576
_HTTP_READ_CHUNK = 16_384
_DEFAULT_HTTP_TIMEOUT = 15.0
_SAFE_DISPLAY = re.compile(r"[^\w\s.+/\-()]+", re.UNICODE)
ALLOWED_HTTP_HOSTS = frozenset({
  "api2.cursor.sh",
  "cli-chat-proxy.grok.com",
  "opencode.ai",
})


class _RefuseRedirect(urllib.request.HTTPRedirectHandler):
  """Do not follow redirects. urllib copies Authorization to the next hop."""

  def redirect_request(self, req, fp, code, msg, headers, newurl):  # noqa: ANN001
    raise urllib.error.HTTPError(
      getattr(req, "full_url", newurl),
      code,
      "HTTP redirect refused for authenticated Magilla requests",
      headers,
      fp,
    )


# Ignore HTTP(S)_PROXY so a poisoned environment cannot intercept Bearer tokens.
_http_opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), _RefuseRedirect)


def safe_display_text(value: Any, max_len: int = 64) -> str:
  """Strip control chars and markup from provider-controlled UI strings."""
  text = " ".join(str(value or "").split())
  text = _SAFE_DISPLAY.sub("", text).strip()
  if len(text) > max_len:
    text = text[:max_len].rstrip()
  return text


def require_https_host(url: str, allowed: frozenset[str] = ALLOWED_HTTP_HOSTS) -> str:
  parsed = urllib.parse.urlparse(url)
  host = (parsed.hostname or "").lower()
  if parsed.scheme != "https" or parsed.username or parsed.password:
    raise ValueError("Magilla only allows https URLs without credentials in the URL")
  if parsed.port not in (None, 443):
    raise ValueError("Magilla only allows https port 443")
  if host not in allowed:
    raise ValueError("Magilla refused a host outside the provider allow-list")
  return url


def _deadline_remaining(deadline: float) -> float:
  left = deadline - time.monotonic()
  if left <= 0:
    raise TimeoutError("HTTP call exceeded Magilla deadline")
  return left


def _walk_fileobjs(obj: Any) -> Iterator[Any]:
  seen: set[int] = set()
  stack = [obj]
  while stack:
    cur = stack.pop()
    ident = id(cur)
    if ident in seen or cur is None or isinstance(cur, (bytes, str, int, float, bool)):
      continue
    seen.add(ident)
    yield cur
    for name in ("fp", "raw", "_fp", "rfile"):
      inner = getattr(cur, name, None)
      if inner is not None:
        stack.append(inner)


def _set_read_timeout(response: Any, seconds: float) -> None:
  for obj in _walk_fileobjs(response):
    sock = getattr(obj, "_sock", None)
    setter = getattr(sock, "settimeout", None) if sock is not None else None
    if callable(setter):
      try:
        setter(seconds)
      except (OSError, AttributeError, ValueError):
        continue


def _close_quietly(obj: Any) -> None:
  closer = getattr(obj, "close", None)
  if callable(closer):
    try:
      closer()
    except Exception:
      pass
  for nested in _walk_fileobjs(obj):
    sock = getattr(nested, "_sock", None)
    if sock is None:
      continue
    try:
      sock.shutdown(2)
    except Exception:
      pass
    try:
      sock.close()
    except Exception:
      pass


class _DeadlineWatchdog:
  """Close the HTTP response when the whole-call deadline elapses."""

  def __init__(self, deadline: float) -> None:
    self._deadline = deadline
    self._stop = threading.Event()
    self._lock = threading.Lock()
    self._targets: list[Any] = []
    self._thread = threading.Thread(target=self._run, name="magilla-http-deadline", daemon=True)
    self._thread.start()

  def watch(self, obj: Any) -> None:
    with self._lock:
      self._targets.append(obj)

  def _run(self) -> None:
    while not self._stop.wait(0.05):
      if time.monotonic() < self._deadline:
        continue
      with self._lock:
        targets = list(self._targets)
      for obj in targets:
        _close_quietly(obj)
      return

  def cancel(self) -> None:
    self._stop.set()


def read_http_json(
  response: Any,
  max_bytes: int = MAX_HTTP_JSON_BYTES,
  deadline: float | None = None,
) -> Any:
  """Decode a JSON HTTP body without letting it grow without bound."""
  length = response.headers.get("Content-Length") if getattr(response, "headers", None) else None
  if length is not None:
    try:
      declared = int(length)
    except ValueError:
      declared = -1
    if declared > max_bytes:
      raise ValueError("HTTP Content-Length exceeds Magilla's JSON body limit")
  chunks: list[bytes] = []
  total = 0
  while True:
    left = _deadline_remaining(deadline) if deadline is not None else _DEFAULT_HTTP_TIMEOUT
    _set_read_timeout(response, left)
    to_read = min(_HTTP_READ_CHUNK, max(1, max_bytes - total + 1))
    try:
      chunk = response.read(to_read)
    except TimeoutError as exc:
      raise TimeoutError("HTTP JSON read exceeded Magilla deadline") from exc
    except OSError as exc:
      if deadline is not None and time.monotonic() >= deadline:
        raise TimeoutError("HTTP JSON read exceeded Magilla deadline") from exc
      raise
    if not chunk:
      break
    total += len(chunk)
    if total > max_bytes:
      raise ValueError("HTTP response exceeded Magilla's JSON body limit")
    chunks.append(chunk)
  return json.loads(b"".join(chunks).decode("utf-8", errors="replace"))


def open_http_json(
  request: urllib.request.Request,
  timeout: float = _DEFAULT_HTTP_TIMEOUT,
  max_bytes: int = MAX_HTTP_JSON_BYTES,
) -> Any:
  """GET/POST JSON with no redirects, a whole-call deadline, and a body cap."""
  timeout = max(0.2, float(timeout))
  deadline = time.monotonic() + timeout
  require_https_host(request.full_url)
  watchdog = _DeadlineWatchdog(deadline)
  response = None
  try:
    remaining = _deadline_remaining(deadline)
    try:
      response = _http_opener.open(request, timeout=remaining)
    except urllib.error.HTTPError as error:
      watchdog.watch(error)
      _close_quietly(error)
      raise
    watchdog.watch(response)
    _set_read_timeout(response, _deadline_remaining(deadline))
    return read_http_json(response, max_bytes=max_bytes, deadline=deadline)
  finally:
    watchdog.cancel()
    if response is not None:
      _close_quietly(response)


def home() -> Path:
  raw = os.environ.get("HOME")
  return Path(raw) if raw else Path.home()


def expand(value: str | os.PathLike[str] | None) -> Path:
  raw = os.path.expandvars(os.path.expanduser(str(value or "")))
  return Path(raw) if raw else home()


def xdg_config() -> Path:
  return Path(os.environ.get("XDG_CONFIG_HOME") or (home() / ".config"))


def xdg_state() -> Path:
  return Path(os.environ.get("XDG_STATE_HOME") or (home() / ".local" / "state"))


def xdg_cache() -> Path:
  return Path(os.environ.get("XDG_CACHE_HOME") or (home() / ".cache"))


def xdg_data() -> Path:
  return Path(os.environ.get("XDG_DATA_HOME") or (home() / ".local" / "share"))


def grok_home() -> Path:
  return expand(os.environ.get("GROK_HOME") or "~/.grok")


def claude_home() -> Path:
  return expand(os.environ.get("CLAUDE_CONFIG_DIR") or "~/.claude")


def codex_home() -> Path:
  return expand(os.environ.get("CODEX_HOME") or "~/.codex")


def cursor_config_dir() -> Path:
  override = os.environ.get("CURSOR_CONFIG_DIR") or os.environ.get("CURSOR_HOME")
  if override:
    return expand(override)
  capital = xdg_config() / "Cursor"
  lower = xdg_config() / "cursor"
  if capital.exists():
    return capital
  if lower.exists():
    return lower
  return capital


def magilla_state() -> Path:
  path = xdg_state() / "magilla-ai-usage"
  path.mkdir(parents=True, exist_ok=True)
  return path


def magilla_usage_dir() -> Path:
  path = magilla_state() / "usage"
  path.mkdir(parents=True, exist_ok=True)
  return path


def magilla_cache_dir() -> Path:
  path = xdg_cache() / "magilla-ai-usage"
  path.mkdir(parents=True, exist_ok=True)
  return path


def omarchy_usage_dir() -> Path:
  return xdg_state() / "omarchy" / "agents" / "usage"


def omarchy_path() -> Path:
  return expand(os.environ.get("OMARCHY_PATH") or "/usr/share/omarchy")


def which(name: str) -> str:
  found = shutil.which(name)
  if found:
    return found
  extras = [
    home() / ".local" / "bin" / name,
    grok_home() / "bin" / name,
    home() / ".local" / "share" / "mise" / "shims" / name,
  ]
  for candidate in extras:
    if candidate.is_file() and os.access(candidate, os.X_OK):
      return str(candidate)
  return ""


def path_exists(path: Path) -> bool:
  try:
    return path.exists()
  except OSError:
    return False


def non_empty_file(path: Path) -> bool:
  try:
    return path.is_file() and path.stat().st_size > 2
  except OSError:
    return False


def utc_now() -> datetime:
  return datetime.now(timezone.utc)


def iso_now() -> str:
  return utc_now().isoformat()


def date_string(value: datetime | None = None) -> str:
  stamp = value or datetime.now().astimezone()
  return stamp.date().isoformat()


def recent_date_strings() -> list[str]:
  today = datetime.now().astimezone().date()
  return [(today - timedelta(days=offset)).isoformat() for offset in range(6, -1, -1)]


def local_date_from_timestamp(value: Any) -> str:
  if value is None:
    return date_string()
  if isinstance(value, datetime):
    stamp = value
    if stamp.tzinfo is not None:
      stamp = stamp.astimezone()
    return stamp.date().isoformat()
  if isinstance(value, (int, float)):
    seconds = float(value)
    if seconds > 10_000_000_000:
      seconds /= 1000.0
    try:
      return datetime.fromtimestamp(seconds).date().isoformat()
    except (OverflowError, OSError, ValueError):
      return date_string()
  raw = str(value).strip()
  if not raw:
    return date_string()
  try:
    parsed = datetime.fromisoformat(raw.replace("Z", "+00:00"))
    if parsed.tzinfo is not None:
      parsed = parsed.astimezone()
    return parsed.date().isoformat()
  except ValueError:
    return date_string()


def parse_iso(value: Any) -> datetime | None:
  raw = str(value or "").strip()
  if raw == "":
    return None
  try:
    parsed = datetime.fromisoformat(raw.replace("Z", "+00:00"))
  except ValueError:
    return None
  if parsed.tzinfo is None:
    parsed = parsed.replace(tzinfo=timezone.utc)
  return parsed


def number(value: Any) -> int:
  try:
    n = float(value or 0)
  except (TypeError, ValueError):
    return 0
  if n != n:
    return 0
  return round(n)


def empty_bucket() -> dict[str, int]:
  return {
    "inputTokens": 0,
    "outputTokens": 0,
    "cacheReadInputTokens": 0,
    "cacheCreationInputTokens": 0,
  }


def empty_stats() -> dict[str, Any]:
  return {
    "todayPrompts": 0,
    "todaySessions": 0,
    "todayTotalTokens": 0,
    "todayTokensByModel": {},
    "recentDays": [{"date": day, "messageCount": 0} for day in recent_date_strings()],
    "totalPrompts": 0,
    "totalSessions": 0,
    "activeDays": 0,
    "activeDates": [],
    "modelUsage": {},
  }


def base_record(agent_id: str, name: str, **overrides: Any) -> dict[str, Any]:
  record: dict[str, Any] = {
    "schemaVersion": 1,
    "id": agent_id,
    "name": name,
    "updatedAt": iso_now(),
    "ready": False,
    "hasLocalStats": False,
    "hasPromptStats": False,
    "scope": "device",
    "tierLabel": "",
    "usageStatusText": "",
    "authHelpText": "",
    "limits": [],
  }
  record.update(empty_stats())
  record.update(overrides)
  return record


def write_json(path: Path, payload: dict[str, Any], mode: int = 0o600) -> None:
  path.parent.mkdir(parents=True, exist_ok=True)
  handle_fd, tmp_name = tempfile.mkstemp(dir=str(path.parent), prefix=path.name + ".", suffix=".tmp")
  tmp = Path(tmp_name)
  try:
    with os.fdopen(handle_fd, "w", encoding="utf-8") as handle:
      handle.write(json.dumps(payload, separators=(",", ":"), sort_keys=True) + "\n")
    os.chmod(tmp, mode)
    tmp.replace(path)
  except BaseException:
    tmp.unlink(missing_ok=True)
    raise


def read_json(path: Path) -> dict[str, Any] | None:
  if not path.is_file():
    return None
  try:
    data = json.loads(path.read_text(encoding="utf-8"))
  except (OSError, json.JSONDecodeError):
    return None
  return data if isinstance(data, dict) else None


def read_fresh_json(path: Path, max_age_seconds: float) -> dict[str, Any] | None:
  if max_age_seconds <= 0 or not path.is_file():
    return None
  try:
    age = path.stat().st_mtime
    if time_now() - age > max_age_seconds:
      return None
  except OSError:
    return None
  return read_json(path)


def time_now() -> float:
  return datetime.now().timestamp()


def dump_record(record: dict[str, Any]) -> str:
  cleaned = dict(record)
  if not cleaned.get("balance"):
    cleaned.pop("balance", None)
  return json.dumps(cleaned, separators=(",", ":"), sort_keys=True)


def write_usage_record(record: dict[str, Any]) -> Path:
  path = magilla_usage_dir() / f"{record['id']}.json"
  write_json(path, record)
  return path


def display_path(path: Path) -> str:
  try:
    return "~/" + str(path.relative_to(home()))
  except ValueError:
    return str(path)


def add_tokens(bucket: dict[str, int], usage: dict[str, Any]) -> None:
  cache_read = number(usage.get("cachedReadTokens") or usage.get("cacheReadInputTokens") or usage.get("cache_read"))
  cache_write = number(usage.get("cacheCreationTokens") or usage.get("cacheCreationInputTokens") or usage.get("cache_write"))
  raw_input = number(usage.get("inputTokens") or usage.get("input_tokens") or usage.get("tokens_input"))
  output = number(usage.get("outputTokens") or usage.get("output_tokens") or usage.get("tokens_output"))
  # Keep the four panel buckets mutually exclusive: billed input minus cache.
  billed_input = max(0, raw_input - cache_read)
  bucket["inputTokens"] += billed_input
  bucket["outputTokens"] += output
  bucket["cacheReadInputTokens"] += cache_read
  bucket["cacheCreationInputTokens"] += cache_write


def token_total(bucket: dict[str, Any]) -> int:
  return (
    number(bucket.get("inputTokens"))
    + number(bucket.get("outputTokens"))
    + number(bucket.get("cacheReadInputTokens"))
    + number(bucket.get("cacheCreationInputTokens"))
  )


class StatsAcc:
  """Accumulate local session stats into the shared record fields."""

  def __init__(self) -> None:
    self.today = date_string()
    self.dates = recent_date_strings()
    self.today_prompts = 0
    self.today_sessions = 0
    self.today_tokens = 0
    self.today_by_model: dict[str, int] = {}
    self.recent: dict[str, int] = {day: 0 for day in self.dates}
    self.total_prompts = 0
    self.sessions: set[str] = set()
    self.active_dates: set[str] = set()
    self.models: dict[str, dict[str, int]] = {}

  def add_prompt(self, *, session_id: str, day: str, model: str, usage: dict[str, Any]) -> None:
    model_id = model or "unknown"
    bucket = self.models.setdefault(model_id, empty_bucket())
    before = token_total(bucket)
    add_tokens(bucket, usage)
    added = token_total(bucket) - before
    self.total_prompts += 1
    self.sessions.add(session_id)
    if day:
      self.active_dates.add(day)
      if day in self.recent:
        self.recent[day] += added
    if day == self.today:
      self.today_prompts += 1
      self.today_tokens += added
      self.today_by_model[model_id] = self.today_by_model.get(model_id, 0) + added

  def add_session_day(self, session_id: str, day: str) -> None:
    self.sessions.add(session_id)
    if day:
      self.active_dates.add(day)
      if day == self.today:
        self.today_sessions += 1

  def as_fields(self) -> dict[str, Any]:
    today_sessions = self.today_sessions
    if today_sessions == 0 and self.today_prompts > 0:
      today_sessions = 1
    return {
      "hasLocalStats": self.total_prompts > 0 or len(self.sessions) > 0,
      "hasPromptStats": self.total_prompts > 0,
      "todayPrompts": self.today_prompts,
      "todaySessions": today_sessions,
      "todayTotalTokens": self.today_tokens,
      "todayTokensByModel": dict(self.today_by_model),
      "recentDays": [{"date": day, "messageCount": self.recent.get(day, 0)} for day in self.dates],
      "totalPrompts": self.total_prompts,
      "totalSessions": len(self.sessions),
      "activeDays": len(self.active_dates),
      "activeDates": sorted(self.active_dates),
      "modelUsage": self.models,
    }
