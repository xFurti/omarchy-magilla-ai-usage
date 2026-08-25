.pragma library

// Quiet Magilla accent. Status colors follow Omarchy: theme foreground for
// healthy meters, urgent when a window is nearly spent.

var purple = "#7B3FA0"

var statusActive = ""
var statusLow = "#C9A227"
var statusExhausted = "#A55555"
var statusWaiting = "#8A8094"
var statusIdle = "#8A8094"

function statusHex(status) {
  if (status === "exhausted") return statusExhausted
  if (status === "low") return statusLow
  if (status === "waiting") return statusWaiting
  return statusIdle
}
