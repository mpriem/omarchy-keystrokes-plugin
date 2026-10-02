const assert = require('node:assert/strict');
const fs = require('node:fs'), vm = require('node:vm');
const c = {}; vm.createContext(c);
vm.runInContext(fs.readFileSync('Config.js', 'utf8').replace('.pragma library', ''), c);
for (const doc of [null, [], 1, true, 'x']) assert.equal(c.normalize(doc).policyValid, false);
for (const [key, value] of Object.entries(c.DEFAULTS)) {
  assert.equal(c.normalize({[key]: value}).issues.length, 0);
  assert.ok(c.normalize({[key]: null}).issues.includes(key));
}
for (const key of ['position', 'size', 'order']) {
  for (const value of [42, '__proto__', 'sideways']) assert.ok(c.normalize({[key]: value}).issues.includes(key));
}
for (const key of ['maxItems', 'timeoutMs', 'autoOffMinutes']) {
  for (const value of [-1, Infinity, NaN, '5', 1.2, 10000]) assert.ok(c.normalize({[key]: value}).issues.includes(key));
}
assert.equal(c.read({monitor:'disconnected-DP-1'}).monitor, 'disconnected-DP-1');
assert.equal(c.normalize({monitor:'\n'}).issues.length, 1);
assert.equal(c.normalize({hideFor: Array(65).fill('a')}).policyValid, false);
assert.equal(c.normalize({hideFor: ['😀'.repeat(64)]}).policyValid, true);
assert.equal(c.normalize({hideFor: ['😀'.repeat(65)]}).policyValid, false);
assert.equal(c.read({hideFor: []}).hideFor.length, 0);
const first = c.read({}), second = c.read({}); first.hideFor.length = 0;
assert.ok(second.hideFor.length > 0);
let last = c.parse('{"hideFor":["private-editor"],"autoOffMinutes":15}');
for (const text of ['{', 'null', '{"hideFor":42}', JSON.stringify({hideFor:Array(65).fill('x')})]) {
  const next = c.parse(text); if (next.valid) last = next;
  assert.equal(last.values.hideFor[0], 'private-editor');
  assert.equal(last.values.autoOffMinutes, 15);
}
assert.equal(c.parse('{"future":42}').raw.future, 42);
console.log('PASS: configuration normalization and last-valid privacy policy');
