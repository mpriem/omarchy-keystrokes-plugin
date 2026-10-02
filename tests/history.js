const assert = require('node:assert/strict'), fs = require('node:fs'), vm = require('node:vm');
function load(name, globals={}) {
  const ctx = {...globals}; vm.createContext(ctx);
  vm.runInContext(fs.readFileSync(name, 'utf8').replace(/^\.(pragma|import).*$/mg, ''), ctx);
  return ctx;
}
const keys = load('KeyLabels.js'), c = load('Config.js'), h = load('StrokeHistory.js', {Keys:keys});
const config = c.read({maxItems:3}), key = code => ({code,mods:1});
let entries = [];
for (const [at, code] of [[0,38],[100,39],[200,40]]) entries = h.append(entries,key(code),config,at);
assert.equal(h.display(entries,'newest-top')[0].code,40);
assert.equal(h.display(entries,'newest-bottom')[0].code,38);
config.order = 'newest-top'; entries = h.append(entries,key(40),config,300);
assert.equal(entries[2].count,2);
assert.equal(h.display(entries,config.order)[0].count,2);
entries = h.append(entries,key(41),config,400);
assert.equal(entries[0].code,39);
entries = h.limit(entries,1); assert.equal(entries[0].code,41);
assert.equal(h.expire(entries,2400,2000).length,1);
assert.equal(h.expire(entries,2401,2000).length,0);
entries = h.append(entries,key(41),config,2400); assert.equal(entries.length,2); // collapse uses strict expiry
config.collapseRepeats=false;
entries = h.append(entries,key(41),config,2401); assert.equal(entries.length,3);
assert.equal(h.append([], {code:38,mods:2}, config,0).length,0);
assert.equal(h.append([], {code:37,mods:1}, config,0).length,0);
config.modifiersAlone=true;
assert.equal(h.append([], {code:37,mods:1}, config,0).length,1);
assert.equal(h.append([], {code:37,mods:9}, config,0).length,0);
assert.equal(keys.caps(9,38).join('+'),'Super+Ctrl+A');
console.log('PASS: chronological history, live order, capacity, repeats, expiry and display filtering');
