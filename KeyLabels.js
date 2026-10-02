.pragma library

// Modifier bits used by hypr/keystrokes.lua.
var MOD_CTRL = 1, MOD_SHIFT = 2, MOD_ALT = 4, MOD_SUPER = 8
var MOD_ORDER = [
  { bit: MOD_SUPER, label: "Super" },
  { bit: MOD_CTRL, label: "Ctrl" },
  { bit: MOD_ALT, label: "Alt" },
  { bit: MOD_SHIFT, label: "Shift" }
]

// XKB keycode (evdev + 8) -> what to print. Letters and punctuation follow
// the physical key on a US layout; the special keys are layout-independent.
var KEY_NAMES = {
  9: "Esc", 10: "1", 11: "2", 12: "3", 13: "4", 14: "5", 15: "6", 16: "7", 17: "8", 18: "9", 19: "0",
  20: "-", 21: "=", 22: "⌫", 23: "Tab", 24: "Q", 25: "W", 26: "E", 27: "R", 28: "T", 29: "Y", 30: "U",
  31: "I", 32: "O", 33: "P", 34: "[", 35: "]", 36: "Enter", 38: "A", 39: "S", 40: "D", 41: "F", 42: "G",
  43: "H", 44: "J", 45: "K", 46: "L", 47: ";", 48: "'", 49: "`", 51: "\\", 52: "Z", 53: "X", 54: "C",
  55: "V", 56: "B", 57: "N", 58: "M", 59: ",", 60: ".", 61: "/", 63: "KP *", 65: "Space", 66: "Caps",
  67: "F1", 68: "F2", 69: "F3", 70: "F4", 71: "F5", 72: "F6", 73: "F7", 74: "F8", 75: "F9", 76: "F10",
  77: "Num", 78: "Scroll", 79: "KP 7", 80: "KP 8", 81: "KP 9", 82: "KP -", 83: "KP 4", 84: "KP 5", 85: "KP 6",
  86: "KP +", 87: "KP 1", 88: "KP 2", 89: "KP 3", 90: "KP 0", 91: "KP .", 94: "<", 95: "F11", 96: "F12",
  104: "KP Enter", 106: "KP /", 107: "PrtSc", 110: "Home", 111: "↑", 112: "PgUp", 113: "←", 114: "→",
  115: "End", 116: "↓", 117: "PgDn", 118: "Ins", 119: "Del", 121: "Mute", 122: "Vol −", 123: "Vol +",
  127: "Pause", 135: "Menu", 171: "Next", 172: "Play", 173: "Prev", 174: "Stop", 232: "Bright −", 233: "Bright +"
}
var MODIFIER_CODES = { 37: MOD_CTRL, 105: MOD_CTRL, 50: MOD_SHIFT, 62: MOD_SHIFT, 64: MOD_ALT, 108: MOD_ALT, 133: MOD_SUPER, 134: MOD_SUPER }

function keyName(code) {
  var n = KEY_NAMES[code]
  if (n) return n
  var mod = MODIFIER_CODES[code]
  if (mod) for (var i = 0; i < MOD_ORDER.length; i++) if (MOD_ORDER[i].bit === mod) return MOD_ORDER[i].label
  return "#" + code
}
function isModifier(code) { return MODIFIER_CODES[code] !== undefined }
// the caps of one stroke, modifiers first in Omarchy's order
function caps(mods, code) {
  var list = []
  for (var i = 0; i < MOD_ORDER.length; i++) if (mods & MOD_ORDER[i].bit) list.push(MOD_ORDER[i].label)
  if (code > 0 && !isModifier(code)) list.push(keyName(code))
  else if (code > 0 && list.indexOf(keyName(code)) < 0) list.push(keyName(code))
  return list
}

function pauseText(reason, shortcut) {
  return (reason === "sudo" ? "SUDO Found" : "Authentication Found")
    + " - Click" + (shortcut ? " or " + shortcut : "") + " to continue"
}

