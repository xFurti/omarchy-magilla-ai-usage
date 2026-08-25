.pragma library

// Magilla visual language. Inspired by Magilla Gorilla's purple derby,
// bow tie, and banana — playful, not childish. Text still follows the
// Omarchy theme so light and dark shells stay readable.

var purple = "#7B3FA0"
var purpleDeep = "#4A2168"
var purpleSoft = "#B07AD4"
var pink = "#E8A0C8"
var banana = "#F4C430"
var charcoal = "#1C1524"
var peach = "#F3C7A5"

var statusActive = "#3D9A6E"
var statusLow = "#E6B422"
var statusExhausted = "#D45B6A"
var statusWaiting = "#9A7BB8"
var statusIdle = "#8A8094"

function hexColor(value, fallback) {
  var s = String(value || "")
  return s.charAt(0) === "#" ? s : (fallback || purple)
}

function statusHex(status) {
  if (status === "exhausted") return statusExhausted
  if (status === "low") return statusLow
  if (status === "active") return statusActive
  if (status === "waiting") return statusWaiting
  return statusIdle
}
