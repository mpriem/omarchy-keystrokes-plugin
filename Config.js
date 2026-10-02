// Settings normalization shared by the overlay and panel. No Qt imports.
.pragma library

var POSITIONS = [
  { value: "bottom-center", label: "Bottom" },
  { value: "bottom-left", label: "Bottom left" },
  { value: "bottom-right", label: "Bottom right" },
  { value: "top-center", label: "Top" },
  { value: "top-left", label: "Top left" },
  { value: "top-right", label: "Top right" }
]
var MONITOR_OPTIONS = [
  { value: "focused", label: "Focused" },
  { value: "all", label: "Every monitor" }
]
var SIZE_OPTIONS = [
  { value: "small", label: "Small" },
  { value: "normal", label: "Normal" },
  { value: "large", label: "Large" }
]
var SIZE_SCALE = { small: 0.85, normal: 1.0, large: 1.3 }
var ORDER_OPTIONS = [
  { value: "newest-bottom", label: "Newest at the bottom" },
  { value: "newest-top", label: "Newest on top" }
]
var TIMEOUT_MIN_MS = 500
var TIMEOUT_MAX_MS = 6000
var AUTO_OFF_OPTIONS = [
  { value: "0", label: "Never" },
  { value: "15", label: "15 min" },
  { value: "60", label: "1 hour" },
  { value: "180", label: "3 hours" }
]

var DEFAULTS = {
  position: "bottom-center",
  monitor: "focused",
  timeoutMs: 2000,
  maxItems: 5,
  size: "normal",
  order: "newest-bottom",
  combosOnly: true,
  sudoProtection: true,
  modifiersAlone: false,
  collapseRepeats: true,
  hideFor: ["1password", "bitwarden", "keepassxc", "hyprlock"],
  autoOffMinutes: 0
}

// Unknown fields remain in the raw document for forward-compatible saves.
// Exclusions: at most 64 strings of 128 UTF-16 units (at most 512 UTF-8
// bytes, the producer's independent limit). Empty lists are intentional.
function normalize(cfg) {
  var out = {}, issues = []
  var policy = ["combosOnly", "sudoProtection", "modifiersAlone", "hideFor", "autoOffMinutes"]
  for (var k in DEFAULTS) out[k] = Array.isArray(DEFAULTS[k]) ? DEFAULTS[k].slice() : DEFAULTS[k]
  if (!cfg || typeof cfg !== "object" || Array.isArray(cfg))
    return { values: out, issues: ["document"], policyValid: false }
  function invalid(key) { issues.push(key) }
  function choice(key, options) {
    if (typeof cfg[key] === "string" && options.some(function(o) { return o.value === cfg[key] })) out[key] = cfg[key]
    else invalid(key)
  }
  for (var key in cfg) {
    if (!Object.prototype.hasOwnProperty.call(cfg, key) || !Object.prototype.hasOwnProperty.call(DEFAULTS, key)) continue
    var value = cfg[key]
    if (key === "position") choice(key, POSITIONS)
    else if (key === "size") choice(key, SIZE_OPTIONS)
    else if (key === "order") choice(key, ORDER_OPTIONS)
    else if (key === "monitor") {
      if (typeof value === "string" && value.length > 0 && value.length <= 128 && !/[\x00-\x1f\x7f]/.test(value)) out[key] = value
      else invalid(key)
    } else if (["timeoutMs", "maxItems", "autoOffMinutes"].indexOf(key) >= 0) {
      var min = key === "timeoutMs" ? TIMEOUT_MIN_MS : key === "maxItems" ? 1 : 0
      var max = key === "timeoutMs" ? TIMEOUT_MAX_MS : key === "maxItems" ? 10 : 1440
      if (typeof value === "number" && isFinite(value) && value >= min && value <= max && Math.floor(value) === value) out[key] = value
      else invalid(key)
    } else if (key === "hideFor") {
      if (Array.isArray(value) && value.length <= 64 && !value.some(function(v) { return typeof v !== "string" || v.length > 128 })) out[key] = value.slice()
      else invalid(key)
    } else if (typeof value === "boolean") out[key] = value
    else invalid(key)
  }
  return { values: out, issues: issues, policyValid: !issues.some(function(k) { return policy.indexOf(k) >= 0 }) }
}
function read(cfg) { return normalize(cfg).values }
function parse(text) {
  try {
    var raw = JSON.parse(text), result = normalize(raw)
    return { raw: raw, values: result.values, valid: result.policyValid, issues: result.issues }
  } catch (e) { return { valid: false, issues: ["document"] } }
}
function withValue(cfg, key, value) {
  var next = JSON.parse(JSON.stringify(cfg || {}))
  next[key] = value
  return next
}
function serialize(cfg) { return JSON.stringify(cfg, null, 2) + "\n" }
function timeoutLabel(ms) { return (ms / 1000).toFixed(1).replace(/\.0$/, "") + " s" }
