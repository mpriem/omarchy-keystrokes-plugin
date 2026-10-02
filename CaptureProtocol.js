.pragma library

var MAX_COUNTER = 2147483647
function counter(value) {
  var n = Number(value)
  return value.length <= 10 && isFinite(n) && n >= 0 && Math.floor(n) === n && n <= MAX_COUNTER
}

// Long strings avoid interpreting user-controlled exclusions as Lua code.
function luaString(value) {
  var text = String(value), equals = ""
  while (text.indexOf("]" + equals + "]") !== -1) equals += "="
  return "[" + equals + "[\n" + text + "]" + equals + "]"
}

function optionsLua(config) {
  return "{combosOnly=" + (config.combosOnly ? "true" : "false")
    + ",sudoProtection=" + (config.sudoProtection ? "true" : "false")
    + ",modifiersAlone=" + (config.modifiersAlone ? "true" : "false")
    + ",autoOffMinutes=" + config.autoOffMinutes
    + ",hideFor={" + config.hideFor.map(luaString).join(",") + "}}"
}

function startLua(token, options) {
  return 'if not Keystrokes or Keystrokes.protocol ~= 5 then return "unavailable" end; return Keystrokes.start('
    + luaString(token) + "," + options + ")"
}

function event(code, mods) {
  if (typeof code !== "number" || typeof mods !== "number" || !isFinite(code) || !isFinite(mods)
      || Math.floor(code) !== code || Math.floor(mods) !== mods || code < 9 || code > 255 || mods < 0 || mods > 15) return null
  return { code: code, mods: mods }
}

function stopLua(token) {
  return 'if Keystrokes then if Keystrokes.protocol == 5 then return Keystrokes.stop('
    + (token === undefined ? "" : luaString(token))
    + ') else Keystrokes.set(false) end end; return "keystrokes-v5 off"'
}

function shortcutLua() {
  return 'if Keystrokes and Keystrokes.shortcut then return Keystrokes.shortcut() end; return ""'
}

function shortcutLabel(text) {
  var label = String(text).trim()
  if (label.length > 128 || /[^\x20-\x7e]/.test(label)) return ""
  var names = { SUPER: "Super", META: "Super", WIN: "Super", SHIFT: "Shift", CTRL: "Ctrl", CONTROL: "Ctrl", ALT: "Alt" }
  return label.split(/\s*\+\s*/).map(function(part) { return names[part.toUpperCase()] || part }).join("+")
}

function parse(text, token) {
  if (text.length !== 2048 || /[^\x20-\x7e\n]/.test(text)) return null
  var lines = text.trim().split("\n")
  var header = /^keystrokes-v5 ([A-Za-z0-9]{12}) (on|waiting|sudo|polkit) (\d+) (\d+)$/.exec(lines.shift())
  var binding = /^b(?: ([ -~]{1,128}))?$/.exec(lines.shift())
  if (!header || header[1] !== token || !binding || lines.length > 32) return null
  if (!counter(header[3]) || !counter(header[4]) || Number(header[4]) === 0) return null
  var events = []
  for (var line of lines) {
    var match = /^p (\d+) (\d+) 0$/.exec(line)
    var stroke = match ? event(Number(match[1]), Number(match[2])) : null
    if (!stroke) return null
    events.push(stroke)
  }
  if (header[2] !== "on" && lines.length) return null
  return { shortcut: shortcutLabel(binding[1] || ""), enabled: header[2] === "on", pauseReason: ["sudo", "polkit"].indexOf(header[2]) >= 0 ? header[2] : "", generation: Number(header[3]), sequence: Number(header[4]), events: events }
}
