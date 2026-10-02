const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const escapedChecks = [];
const p = {};
vm.createContext(p);
vm.runInContext(fs.readFileSync('CaptureProtocol.js', 'utf8').replace('.pragma library', ''), p);
const token = 'ABCDEFGHIJKL';
const frame = lines => (`keystrokes-v5 ${token} on 0 1\nb SUPER + SHIFT + K\n` + lines).padEnd(2048, ' ');
assert.equal(p.parse(frame('p 38 1 0\n'), token).events.length, 1);
for (const data of ['', frame('p 38 1 0\n').slice(1), frame('p 1 1 0\n'), frame('p 38 16 0\n'),
    frame('p 38 1 0\n'.repeat(33)), frame('p 38 1 0\n').replace('on ', 'waiting ')]) {
  assert.equal(p.parse(data, token), null);
}
assert.equal(p.parse(frame(''), 'OTHER1234567'), null);
for (const value of ['normal', '\nstarts with newline', ']]; error("injected"); --', ']=] ]==] [[', 'a\nb', '"\\']) {
  escapedChecks.push('assert(' + p.luaString(value) + ' == string.char(' + [...Buffer.from(value)].join(',') + '))');
}
fs.writeFileSync(process.env.XDG_RUNTIME_DIR + '/quoted.lua', escapedChecks.join('\n'));
console.log('PASS: bounded protocol, token validation and Lua injection escaping');

for (const reason of ['sudo', 'polkit']) {
  const data = `keystrokes-v5 ${token} ${reason} 1 2\nb\n`.padEnd(2048, ' ');
  assert.equal(p.parse(data, token).pauseReason, reason);
  assert.equal(p.parse(data, token).enabled, false);
  assert.equal(p.parse(`keystrokes-v5 ${token} ${reason} 1 2\nb\np 38 1 0\n`.padEnd(2048, ' '), token), null);
}

assert.equal(p.shortcutLabel('SUPER + SHIFT + J\n'), 'Super+Shift+J');
assert.equal(p.shortcutLabel('CTRL + ALT + F10'), 'Ctrl+Alt+F10');
assert.equal(p.shortcutLabel('bad\nlabel'), '');
assert.equal(p.parse(frame(''), token).shortcut, 'Super+Shift+K');
assert.equal(p.parse(frame('').replace('b SUPER + SHIFT + K', 'x SUPER + SHIFT + K'), token), null);
const labels = {}; vm.createContext(labels);
vm.runInContext(fs.readFileSync('KeyLabels.js', 'utf8').replace('.pragma library', ''), labels);
assert.equal(labels.pauseText('sudo', 'Super+Shift+J'), 'SUDO Found - Click or Super+Shift+J to continue');
assert.equal(labels.pauseText('sudo', ''), 'SUDO Found - Click to continue');

const produced = fs.readFileSync(process.env.XDG_RUNTIME_DIR + '/producer.frame', 'ascii');
const actual = p.parse(produced, produced.split(' ')[1]);
assert.equal(actual.enabled, true);
assert.equal(actual.events[0].code, 38);
assert.equal(actual.events[0].mods, 1);
assert.equal(actual.generation, 0);
assert.ok(actual.sequence > 1);
for (const code of [NaN, Infinity, 8, 256, 38.5]) assert.equal(p.event(code, 1), null);
for (const mods of [-1, 16, NaN, 1.5]) assert.equal(p.event(38, mods), null);
console.log('PASS: real Lua frame decoded into structured events');

for (const number of ['9'.repeat(310), '2147483648', '-1', '1.5', 'Infinity']) {
  for (const counters of [`${number} 1`, `0 ${number}`])
    assert.equal(p.parse(`keystrokes-v5 ${token} on ${counters}\nb\n`.padEnd(2048, ' '), token), null);
}
assert.equal(p.parse(`keystrokes-v5 ${token} on 2147483647 2147483647\nb\n`.padEnd(2048, ' '), token).sequence, 2147483647);
assert.equal(p.parse(frame('').replace(/ $/, '\u00a0'), token), null);
