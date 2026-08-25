.pragma library

// Display helpers for Magilla. Pure functions so BarWidget, Panel, Settings,
// and Engine can share one language for status, pinning, and labels.

var KNOWN = [
  { id: "grok", name: "Grok", shortName: "Grok" },
  { id: "cursor", name: "Cursor", shortName: "Cursor" },
  { id: "claude", name: "Claude Code", shortName: "Claude" },
  { id: "codex", name: "Codex", shortName: "Codex" },
  { id: "opencode", name: "OpenCode", shortName: "OpenCode" },
  { id: "fireworks", name: "Fireworks", shortName: "Fireworks" },
  { id: "gemini", name: "Gemini", shortName: "Gemini" },
  { id: "copilot", name: "GitHub Copilot", shortName: "Copilot" },
  { id: "crush", name: "Crush", shortName: "Crush" },
  { id: "pi", name: "Pi", shortName: "Pi" }
]

function knownName(id, fallback) {
  for (var i = 0; i < KNOWN.length; i++) {
    if (KNOWN[i].id === id) return KNOWN[i].name
  }
  return fallback || id
}

function shortName(id, fallback) {
  for (var i = 0; i < KNOWN.length; i++) {
    if (KNOWN[i].id === id) return KNOWN[i].shortName
  }
  return fallback || id
}

function clone(value, fallback) {
  if (value === undefined || value === null) return fallback
  try {
    return JSON.parse(JSON.stringify(value))
  } catch (e) {
    return fallback
  }
}

function numberValue(value) {
  var n = Number(value)
  return isFinite(n) ? n : 0
}

function parseOn(value, fallback) {
  if (value === true) return true
  if (value === false) return false
  if (value === undefined || value === null || value === "") return fallback !== false
  var text = String(value).trim().toLowerCase()
  if (text === "off" || text === "false" || text === "0" || text === "no") return false
  return true
}

function parseBarSlots(value) {
  var slots = []
  if (Array.isArray(value)) {
    for (var i = 0; i < value.length; i++) slots.push(String(value[i] || "").trim())
  } else {
    var parts = String(value || "").split(",")
    for (var j = 0; j < parts.length; j++) slots.push(parts[j].trim())
  }
  var out = []
  for (var k = 0; k < slots.length; k++) {
    if (slots[k] !== "" && out.indexOf(slots[k]) < 0) out.push(slots[k])
    if (out.length >= 3) break
  }
  return out
}

function joinBarSlots(slots) {
  return parseBarSlots(slots).join(",")
}

function hasExplicitEnable(settings, id) {
  return !!(settings && settings.providers && settings.providers[id] && settings.providers[id].enabled !== undefined)
}

function providerEnabled(settings, id, authenticated) {
  if (hasExplicitEnable(settings, id))
    return settings.providers[id].enabled !== false
  return authenticated === true
}

function usedPercent(provider) {
  if (!provider) return -1
  var limits = provider.limits || []
  var best = -1
  for (var i = 0; i < limits.length; i++) {
    var p = Number(limits[i] && limits[i].percent)
    if (isFinite(p) && p >= 0) best = Math.max(best, p)
  }
  if (best >= 0) return best > 1 ? Math.min(1, best / 100) : Math.min(1, best)
  var balance = provider.balance
  if (balance && numberValue(balance.funded) > 0) {
    var remaining = numberValue(balance.remaining)
    var funded = numberValue(balance.funded)
    return Math.max(0, Math.min(1, 1 - remaining / funded))
  }
  return -1
}

function remainingPercent(provider) {
  var used = usedPercent(provider)
  return used < 0 ? -1 : Math.max(0, 1 - used)
}

function bindingLimit(provider) {
  if (!provider) return null
  var limits = provider.limits || []
  var best = null
  for (var i = 0; i < limits.length; i++) {
    var entry = limits[i] || {}
    var percent = Number(entry.percent)
    if (!isFinite(percent) || percent < 0) continue
    if (percent > 1) percent = percent / 100
    if (!best || percent > best.percent) {
      best = {
        label: String(entry.label || ""),
        title: String(entry.title || entry.label || "Limit"),
        percent: Math.min(1, percent),
        resetsAt: String(entry.resetsAt || ""),
        startsAt: String(entry.startsAt || "")
      }
    }
  }
  return best
}

function statusOf(provider) {
  if (!provider) return "idle"
  if (provider.authenticated === false && provider.installed) return "waiting"
  if (!provider.detected && !provider.ready) return "idle"
  var used = usedPercent(provider)
  if (used >= 0.95) return "exhausted"
  if (used >= 0.80) return "low"
  if (used >= 0 || provider.ready) return "active"
  if (provider.authenticated) return "active"
  if (provider.installed) return "waiting"
  return "idle"
}

function statusLabel(status) {
  if (status === "exhausted") return "Exhausted"
  if (status === "low") return "Low"
  if (status === "waiting") return "Sign in"
  if (status === "active") return "Active"
  return "Idle"
}

function formatPercent(fraction) {
  if (fraction === undefined || fraction === null || fraction < 0) return "—"
  return Math.round(fraction * 100) + "%"
}

function formatTokenCount(n) {
  var value = numberValue(n)
  if (value >= 1e9) return (value / 1e9).toFixed(1) + "B"
  if (value >= 1e6) return (value / 1e6).toFixed(1) + "M"
  if (value >= 1e3) return (value / 1e3).toFixed(1) + "K"
  return String(Math.round(value))
}

function formatDuration(ms) {
  if (!(ms > 0)) return "now"
  var minutes = Math.floor(ms / 60000)
  var hours = Math.floor(minutes / 60)
  var days = Math.floor(hours / 24)
  if (days > 0) return days + "d " + (hours % 24) + "h"
  if (hours > 0) return hours + "h " + (minutes % 60) + "m"
  return Math.max(1, minutes) + "m"
}

function resetMs(resetsAt, nowMs) {
  if (!resetsAt) return -1
  var ms = new Date(String(resetsAt)).getTime()
  if (!isFinite(ms)) return -1
  return ms - numberValue(nowMs || Date.now())
}

function formatReset(resetsAt, nowMs) {
  var remaining = resetMs(resetsAt, nowMs)
  if (remaining < 0) return ""
  return remaining > 0 ? "Resets in " + formatDuration(remaining) : "Resets now"
}

function formatClock(iso) {
  if (!iso) return ""
  var date = new Date(String(iso))
  if (isNaN(date.getTime())) return ""
  var h = date.getHours()
  var m = date.getMinutes()
  return String(h).padStart(2, "0") + ":" + String(m).padStart(2, "0")
}

function barLabel(provider, style) {
  if (!provider) return ""
  var used = usedPercent(provider)
  var left = remainingPercent(provider)
  var name = provider.shortName || shortName(provider.providerId, provider.providerName)
  if (style === "compact") {
    if (used < 0) return "·"
    return formatPercent(used)
  }
  if (style === "remaining") {
    if (left < 0) return name
    return name + " " + formatPercent(left)
  }
  if (used < 0) return name
  return name + " " + formatPercent(used)
}

function tooltipLine(provider, nowMs) {
  if (!provider) return ""
  var name = provider.providerName || knownName(provider.providerId)
  var used = usedPercent(provider)
  var parts = [name]
  if (provider.tierLabel) parts.push(String(provider.tierLabel))
  if (used >= 0) parts.push(formatPercent(used) + " used")
  var limit = bindingLimit(provider)
  if (limit && limit.resetsAt) {
    var reset = formatReset(limit.resetsAt, nowMs)
    if (reset) parts.push(reset)
  }
  if (used < 0) parts.push(statusLabel(statusOf(provider)))
  return parts.join(" · ")
}

function tooltipSummary(providers, nowMs) {
  if (!providers || providers.length === 0) return "Magilla AI Usage — click for details, right-click to refresh"
  var lines = []
  for (var i = 0; i < providers.length; i++) lines.push(tooltipLine(providers[i], nowMs))
  return lines.join("\n")
}

function hasUsage(provider) {
  if (!provider) return false
  if (usedPercent(provider) >= 0) return true
  if (provider.balance) return true
  if (numberValue(provider.todayPrompts) > 0 || numberValue(provider.todaySessions) > 0) return true
  if (numberValue(provider.totalPrompts) > 0 || numberValue(provider.totalSessions) > 0) return true
  if (numberValue(provider.todayTotalTokens) > 0) return true
  return false
}

function displaySort(a, b) {
  var rank = { exhausted: 0, low: 1, active: 2, waiting: 3, idle: 4 }
  var sa = rank[statusOf(a)] !== undefined ? rank[statusOf(a)] : 9
  var sb = rank[statusOf(b)] !== undefined ? rank[statusOf(b)] : 9
  if (sa !== sb) return sa - sb
  var ua = usedPercent(a)
  var ub = usedPercent(b)
  if (ua !== ub) return ub - ua
  return String(a.providerName || a.providerId).localeCompare(String(b.providerName || b.providerId))
}

function autoBarSlots(providers) {
  var picked = []
  if (!providers) return picked
  var ranked = providers.slice().sort(displaySort)
  for (var i = 0; i < ranked.length; i++) {
    var p = ranked[i]
    if (!p || !p.enabled) continue
    if (!p.authenticated && !hasUsage(p)) continue
    picked.push(p.providerId)
    if (picked.length >= 3) break
  }
  return picked
}

function mergeProviders(catalog, records, settings) {
  var showIdle = parseOn(settings ? settings.showIdleProviders : "Off", false)
  var enabledMap = settings && settings.providers ? settings.providers : {}
  var byId = {}

  function ensure(id, name) {
    if (byId[id]) return byId[id]
    byId[id] = {
      providerId: id,
      providerName: knownName(id, name || id),
      shortName: shortName(id, name || id),
      detected: false,
      installed: false,
      authenticated: false,
      ready: false,
      enabled: false,
      traces: [],
      cli: "",
      tierLabel: "",
      usageStatusText: "",
      authHelpText: "",
      limits: [],
      balance: null,
      todayPrompts: 0,
      todaySessions: 0,
      todayTotalTokens: 0,
      todayTokensByModel: ({}),
      recentDays: [],
      totalPrompts: 0,
      totalSessions: 0,
      activeDays: 0,
      modelUsage: ({}),
      hasLocalStats: false,
      hasPromptStats: false,
      updatedAt: "",
      known: false
    }
    return byId[id]
  }

  for (var k = 0; k < KNOWN.length; k++) {
    var known = ensure(KNOWN[k].id, KNOWN[k].name)
    known.known = true
  }

  var list = catalog && catalog.providers ? catalog.providers : []
  for (var i = 0; i < list.length; i++) {
    var item = list[i] || {}
    var id = String(item.id || "")
    if (!id) continue
    var row = ensure(id, item.name)
    row.detected = item.detected !== false && (item.installed === true || item.authenticated === true)
    row.installed = item.installed === true
    row.authenticated = item.authenticated === true
    row.traces = Array.isArray(item.traces) ? item.traces : []
    row.cli = String(item.cli || "")
    if (item.name) row.providerName = String(item.name)
  }

  for (var rid in records) {
    var rec = records[rid]
    if (!rec || !rec.id) continue
    var target = ensure(String(rec.id), rec.name)
    target.ready = rec.ready === true
    target.tierLabel = String(rec.tierLabel || "")
    target.usageStatusText = String(rec.usageStatusText || "")
    target.authHelpText = String(rec.authHelpText || "")
    target.limits = Array.isArray(rec.limits) ? rec.limits : []
    target.balance = rec.balance && typeof rec.balance === "object" ? rec.balance : null
    target.todayPrompts = numberValue(rec.todayPrompts)
    target.todaySessions = numberValue(rec.todaySessions)
    target.todayTotalTokens = numberValue(rec.todayTotalTokens)
    target.todayTokensByModel = rec.todayTokensByModel || ({})
    target.recentDays = Array.isArray(rec.recentDays) ? rec.recentDays : []
    target.totalPrompts = numberValue(rec.totalPrompts)
    target.totalSessions = numberValue(rec.totalSessions)
    target.activeDays = numberValue(rec.activeDays)
    target.modelUsage = rec.modelUsage || ({})
    target.hasLocalStats = rec.hasLocalStats === true
    target.hasPromptStats = rec.hasPromptStats !== false
    target.updatedAt = String(rec.updatedAt || "")
    if (target.ready || hasUsage(target)) target.detected = true
  }

  var out = []
  for (var id2 in byId) {
    var p = byId[id2]
    if (hasExplicitEnable(settings, id2))
      p.enabled = enabledMap[id2].enabled !== false
    else
      p.enabled = p.authenticated === true
    p.status = statusOf(p)
    p.statusLabel = statusLabel(p.status)
    p.usedPercent = usedPercent(p)
    p.remainingPercent = remainingPercent(p)
    p.headline = bindingLimit(p)
    p.visibleInPanel = !!(p.enabled && (p.authenticated || hasUsage(p) || (showIdle && p.installed)))
    if (p.visibleInPanel || p.known) out.push(p)
  }

  out.sort(function(a, b) {
    if (a.visibleInPanel !== b.visibleInPanel) return a.visibleInPanel ? -1 : 1
    return displaySort(a, b)
  })
  return out
}

function resolveBarProviders(all, settings) {
  var enabled = []
  for (var i = 0; i < all.length; i++) {
    if (all[i].enabled && all[i].visibleInPanel) enabled.push(all[i])
  }
  var wanted = parseBarSlots(settings ? settings.barSlots : "")
  var byId = {}
  for (var j = 0; j < all.length; j++) byId[all[j].providerId] = all[j]
  var slots = []
  if (wanted.length > 0) {
    for (var w = 0; w < wanted.length; w++) {
      var hit = byId[wanted[w]]
      if (hit && hit.enabled) slots.push(hit)
    }
  } else {
    var autoIds = autoBarSlots(enabled)
    for (var a = 0; a < autoIds.length; a++) {
      if (byId[autoIds[a]]) slots.push(byId[autoIds[a]])
    }
  }
  return slots.slice(0, 3)
}

function pinSlots(current, id, on) {
  var slots = parseBarSlots(current)
  var next = []
  for (var i = 0; i < slots.length; i++) if (slots[i] !== id) next.push(slots[i])
  if (on) {
    next.unshift(id)
    next = next.slice(0, 3)
  }
  return next
}

function modelWordCase(word) {
  if (word === "gpt") return "GPT"
  if (word === "deepseek") return "DeepSeek"
  return word.charAt(0).toUpperCase() + word.slice(1)
}

function friendlyModelName(id) {
  if (!id) return "Unknown"
  var name = String(id).replace(/^claude-/, "").replace(/-\d{8}$/, "")
  var parts = name.split("-")
  var words = []
  var version = []
  for (var i = 0; i < parts.length; i++) {
    var part = parts[i]
    if (part === "") continue
    if (/^\d/.test(part)) {
      version.push(part)
      continue
    }
    if (version.length > 0) {
      words.push(version.join("."))
      version = []
    }
    words.push(modelWordCase(part))
  }
  if (version.length > 0) words.push(version.join("."))
  return words.length > 0 ? words.join(" ") : "Unknown"
}

function modelRows(provider) {
  var usageByModel = provider ? (provider.modelUsage || {}) : {}
  var rows = []
  for (var id in usageByModel) {
    var bucket = usageByModel[id] || {}
    var input = numberValue(bucket.inputTokens)
    var output = numberValue(bucket.outputTokens)
    var cacheRead = numberValue(bucket.cacheReadInputTokens)
    var cacheWrite = numberValue(bucket.cacheCreationInputTokens)
    rows.push({
      name: friendlyModelName(id),
      total: input + output + cacheRead + cacheWrite,
      input: input,
      output: output,
      cacheRead: cacheRead,
      cacheWrite: cacheWrite
    })
  }
  rows.sort(function(a, b) { return b.total - a.total })
  return rows.slice(0, 6)
}

function pluginPathFromUrl(url) {
  var text = String(url || "")
  if (text.indexOf("file://") === 0) {
    text = text.substring(7)
    if (text.charAt(0) !== "/") text = "/" + text
  }
  try {
    text = decodeURIComponent(text)
  } catch (e) {
  }
  return text.replace(/\/$/, "")
}
