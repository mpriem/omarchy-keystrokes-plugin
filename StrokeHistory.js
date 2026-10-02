.pragma library
.import "KeyLabels.js" as Keys

// Canonical chronological history. Display order never affects accumulation.
function limit(entries, capacity) { return entries.slice(Math.max(0, entries.length - capacity)) }
function display(entries, order) { return order === "newest-top" ? entries.slice().reverse() : entries }
function expire(entries, now, timeout) {
  return entries.filter(function(entry) { return now - entry.at <= timeout })
}
function append(entries, event, config, now) {
  var code = event.code, mods = event.mods
  if (Keys.isModifier(code)) {
    if (!config.modifiersAlone || (mods & ~Keys.MODIFIER_CODES[code]) !== 0) return entries
  } else if (config.combosOnly && (mods & (Keys.MOD_CTRL | Keys.MOD_ALT | Keys.MOD_SUPER)) === 0) return entries
  var next = entries.slice(), last = next.length ? next[next.length - 1] : null
  if (last && config.collapseRepeats && last.code === code && last.mods === mods && now - last.at < config.timeoutMs)
    next[next.length - 1] = {code:code, mods:mods, count:last.count + 1, at:now}
  else next.push({code:code, mods:mods, count:1, at:now})
  return limit(next, config.maxItems)
}
