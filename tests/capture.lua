-- Run through tests/run.py: it supplies a fresh private runtime directory.
assert(os.getenv('KEYSTROKES_TEST') == '1', 'use python3 tests/run.py')
local source = 'hypr/keystrokes.lua'
local now, locked, active, down, timers, binds, events = 100, false, nil, {}, {}, {}, {}
local layers = {}
local original_open = io.open
io.open = function(path, mode)
  if path == '/proc/uptime' then
    return {read=function() return string.format('%.2f 0.00', now) end, close=function() return true end}
  end
  return original_open(path, mode)
end
local function window(class) return {class=class, active=true} end
hl = {
  bind = function(key, callback, opts)
    local b = {key=key, display_key=key, callback=callback, opts=opts, enabled=true}
    function b:set_enabled(on) self.enabled=on end
    function b:remove() self.enabled=false; self.removed=true end
    binds[#binds+1]=b; return b
  end,
  timer = function(callback, opts)
    local t = {callback=callback, enabled=true, timeout=opts.timeout}
    function t:set_enabled(on) self.enabled=on end
    function t:set_timeout(ms) self.timeout=ms end
    timers[#timers+1]=t; return t
  end,
  on = function(event, callback)
    assert(event ~= 'input.keyboard.key', 'raw input bypasses lock protection')
    local s={callback=callback}; function s:remove() self.removed=true end
    events[event]=s; return s
  end,
  get_layers=function() return layers end,
  get_active_window=function() return active end,
  is_key_down=function(code) return down[code] == true end,
  dsp={exec_cmd=function() return function() end end},
}
KEYSTROKES_NO_BIND=true
local directory, token
local defaults={sudoProtection=true,combosOnly=true, modifiersAlone=false, hideFor={'Bitwarden', '1password'}, autoOffMinutes=0}
local function read()
  if not directory then return '' end
  local f=io.open(directory .. '/events', 'r'); if not f then return '' end
  local result=f:read('a'); f:close(); return result
end
local function tick() timers[#timers].callback() end
local function acknowledge()
  local seq=assert(read():match('keystrokes%-v5 %w+ %w+ %d+ (%d+)'))
  local f=assert(io.open(directory .. '/ack', 'w')); f:write(token .. ' ' .. seq .. '\n'); f:close()
  tick()
end
local function start(cfg, wait)
  Keystrokes.stop()
  local p=assert(io.popen('bash runtime.sh create', 'r'))
  directory=assert(p:read('l')); assert(p:close()); token=directory:match('%.(%w+)$')
  assert(Keystrokes.start(token, cfg or defaults) == 'keystrokes-v5 waiting')
  if not wait then acknowledge(); assert(Keystrokes.is_on()) end
end
local function press(code)
  for _, b in ipairs(binds) do
    if b.key=='code:' .. code and b.enabled and not b.removed and (not locked or b.opts.locked) then b.callback() end
  end
end
local function empty() assert(not read():find('\np '), 'unexpected key data') end
local function contains(code) assert(read():find('\np ' .. code .. ' '), 'missing key event') end
local count=0
local function test(name, fn)
  layers = {}
  KEYSTROKES_NO_BIND, KEYSTROKES_TOGGLE_BIND = true, nil
  locked, down, active, now=false, {}, window('editor'), 100
  dofile(source)
  fn()
  Keystrokes.stop()
  assert(read()=='', 'transport not removed')
  count=count+1; print('PASS: ' .. name)
end

test('startup never resumes capture and handshake is required', function()
  assert(not Keystrokes.is_on()); Keystrokes.set(true); assert(not Keystrokes.is_on())
  start(nil, true); press(38); empty(); assert(not Keystrokes.is_on())
  now=101; tick(); assert(not Keystrokes.is_on())
end)
test('bindings pass through keys and are suppressed on lock/repeat', function()
  for _, b in ipairs(binds) do if not b.removed then
    assert(b.opts.locked==false and b.opts.repeating==false)
    assert(b.opts.non_consuming and b.opts.transparent and b.opts.ignore_mods and b.opts.submap_universal)
    assert(not b.enabled)
  end end
end)
test('plain typing is filtered before transmission', function()
  start(); press(38); empty(); down[50]=true; press(39); empty()
  down[37]=true; press(38); contains(38)
end)
test('full typing is explicitly configurable', function()
  start({sudoProtection=true,combosOnly=false, modifiersAlone=false, hideFor={}, autoOffMinutes=0}); press(38); contains(38)
end)
test('excluded app keys never enter the transport', function()
  start(); down[37]=true; active=window('com.Bitwarden.desktop'); press(38); empty()
  active=window('editor'); acknowledge(); press(39); contains(39)
end)
test('focus and class changes erase pending and visible keys', function()
  start(); down[37]=true; press(38); events['window.active'].callback(); empty()
  acknowledge(); press(39); events['window.class'].callback(); empty()
end)
test('native lock suppression prevents key capture', function()
  start(); down[37]=true; locked=true; press(38); locked=false; empty()
end)
test('unknown focus and invalid window fail closed', function()
  start(); down[37]=true; active=nil; press(38); empty()
  active=setmetatable({}, {__index=function() error('invalid focus') end}); press(38)
  assert(not Keystrokes.is_on())
end)
test('stale acknowledgements cannot renew the lease', function()
  start(); down[37]=true; press(38)
  now=100.9; tick(); assert(Keystrokes.is_on())
  now=101; tick(); assert(not Keystrokes.is_on() and read()=='')
end)
test('suspend and clock reversal stop before another key', function()
  start(); now=103; press(38); assert(not Keystrokes.is_on())
  now=100; start(); now=99; assert(not Keystrokes.is_on())
end)
test('foreign stop token does not stop the current session', function()
  start(); Keystrokes.stop('OTHER1234567'); assert(Keystrokes.is_on())
end)
test('stop clears transport, open readers, and capture bindings', function()
  start(); down[37]=true; press(38)
  local f=assert(io.open(directory .. '/events', 'r'))
  Keystrokes.stop(token); assert(read()=='' and not Keystrokes.is_on())
  assert(f:read('a')==string.rep(' ', 2048)); f:close()
  for _, b in ipairs(binds) do assert(not b.enabled) end
end)
test('queue and snapshot are bounded; acknowledged events expire', function()
  start(); down[37]=true; for _=1,200 do press(38) end
  assert(#read()==2048); acknowledge()
  local _, n=read():gsub('\np ', ''); assert(n==32)
  acknowledge(); now=100.3; tick(); empty(); assert(#read()==2048)
end)
test('auto-off runs in the compositor', function()
  for cycle=1,2 do
    start({sudoProtection=true,combosOnly=true, modifiersAlone=false, hideFor={}, autoOffMinutes=1})
    local beginning=now
    for i=1,239 do now=beginning+i/4; tick(); acknowledge() end
    assert(Keystrokes.is_on())
    now=beginning+60; tick(); assert(not Keystrokes.is_on())
  end
end)
test('reload disables previous bindings and stops capture', function()
  start(); local old=binds[#binds]; dofile(source)
  assert(not old.enabled and not Keystrokes.is_on() and read()=='')
  start(); events['config.reloaded'].callback(); assert(not Keystrokes.is_on())
end)
test('legacy raw listener is retired during upgrade', function()
  Keystrokes.dispose()
  local stopped, removed=false,false
  Keystrokes={set=function(on) assert(not on); stopped=true end, _subscription={remove=function() removed=true end}}
  dofile(source); assert(stopped and removed and not Keystrokes.is_on())
end)
test('invalid configuration and missing owner refuse activation', function()
  assert(Keystrokes.start('BAD', defaults)=='keystrokes-v5 off')
  assert(Keystrokes.start('ABCDEFGHIJKL', {})=='keystrokes-v5 off')
  assert(Keystrokes.start('ABCDEFGHIJKL', defaults)=='keystrokes-v5 off')
end)
test('missing spare fails closed without creating a public file', function()
  start(); assert(os.remove(directory .. '/spare')); down[37]=true; press(38)
  assert(not Keystrokes.is_on() and read()=='')
end)
local function sudo() for _, code in ipairs({39,30,40,32,65}) do press(code) end end
local function paused(reason)
  assert(not Keystrokes.is_on())
  assert(read():find(' ' .. reason .. ' '), 'missing pause reason')
  empty()
  for _, b in ipairs(binds) do assert(not b.enabled) end
end

test('sudo prefix is detected in shortcuts-only mode before transmission', function()
  start(); sudo(); paused('sudo')
  press(38); empty(); acknowledge(); paused('sudo')
  now=100.3; tick(); paused('sudo')
end)
test('sudo pauses full typing and scrubs both snapshots', function()
  start({sudoProtection=true,combosOnly=false,modifiersAlone=false,hideFor={},autoOffMinutes=0})
  sudo(); paused('sudo')
  local f=assert(io.open(directory .. '/spare', 'r'))
  assert(f:read('a')==string.rep(' ', 2048)); f:close()
  press(38); empty()
end)
test('sudo protection can be disabled', function()
  start({sudoProtection=false,combosOnly=false,modifiersAlone=false,hideFor={},autoOffMinutes=0})
  sudo(); assert(Keystrokes.is_on())
end)
test('sudo needs consecutive keys in the same allowed focus', function()
  start(); press(39); press(30); press(38); press(40); press(32); press(65)
  assert(Keystrokes.is_on()); empty()
  press(39); press(30); events['window.active'].callback(); press(40); press(32); press(65)
  assert(Keystrokes.is_on())
  active=window('Bitwarden'); sudo(); active=window('editor'); assert(Keystrokes.is_on())
  acknowledge(); sudo(); paused('sudo')
end)
test('manual restart after sudo requires a fresh handshake', function()
  start(); sudo(); paused('sudo'); start(nil, true)
  assert(not Keystrokes.is_on()); acknowledge(); assert(Keystrokes.is_on())
  down[37]=true; press(38); contains(38)
end)
test('polkit opening pauses even when sudo protection is disabled', function()
  start({sudoProtection=false,combosOnly=false,modifiersAlone=false,hideFor={},autoOffMinutes=0})
  events['layer.opened'].callback({namespace='omarchy-polkit'})
  paused('polkit'); acknowledge(); paused('polkit')
end)
test('an already mapped polkit layer blocks start and resume', function()
  layers={{namespace='omarchy-polkit',mapped=true}}
  start(nil,true); acknowledge(); paused('polkit')
  start(nil,true); acknowledge(); paused('polkit')
  layers={}; acknowledge(); paused('polkit') -- closing never auto-resumes
  start(); assert(Keystrokes.is_on())
end)
test('per-key and watchdog checks catch polkit without an open event', function()
  start(); layers={{namespace='omarchy-polkit',mapped=true}}; press(38); paused('polkit')
  layers={}; start(); layers={{namespace='omarchy-polkit',mapped=true}}; tick(); paused('polkit')
end)
test('other layers and unmapped polkit surfaces do not pause', function()
  layers={{namespace='other',mapped=true},{namespace='omarchy-polkit',mapped=false}}
  start(); events['layer.opened'].callback({namespace='other'}); tick(); assert(Keystrokes.is_on())
end)
test('layer-query failure disables capture', function()
  start(); local old=hl.get_layers
  hl.get_layers=function() error('layer query unavailable') end
  press(38); assert(not Keystrokes.is_on() and read()==''); hl.get_layers=old
end)
test('default shortcut comes from the registered binding', function()
  KEYSTROKES_NO_BIND=false; dofile(source)
  assert(Keystrokes._toggle.display_key=='SUPER + SHIFT + K')
  assert(Keystrokes.shortcut()=='SUPER + SHIFT + K')
  start(); assert(read():find('\nb SUPER %+ SHIFT %+ K\n'))
end)
test('custom shortcut is registered and transmitted on pause', function()
  KEYSTROKES_NO_BIND=false; KEYSTROKES_TOGGLE_BIND='ALT + F10'; dofile(source)
  assert(Keystrokes._toggle.display_key=='ALT + F10')
  start(); sudo(); assert(not Keystrokes.is_on())
  assert(read():find('\nb ALT %+ F10\n'))
  assert(Keystrokes._toggle.enabled, 'resume binding must remain enabled')
end)
test('disabled or absent binding has no shortcut hint', function()
  KEYSTROKES_NO_BIND=false; dofile(source)
  Keystrokes._toggle:set_enabled(false); assert(Keystrokes.shortcut()=='')
  start(); sudo(); assert(read():find('\nb\n'))
  KEYSTROKES_NO_BIND=true; KEYSTROKES_TOGGLE_BIND='ALT + F10'; dofile(source)
  assert(not Keystrokes._toggle and Keystrokes.shortcut()=='')
end)
test('cleanup does not remove other same-key bindings', function()
  KEYSTROKES_NO_BIND=false; dofile(source)
  local other=hl.bind('SUPER + SHIFT + K', function() end, {})
  local oldToggle=Keystrokes._toggle
  local oldCapture=binds[#binds-2]
  oldToggle.remove=function() other:set_enabled(false); error('unsafe remove') end
  oldCapture.remove=function() other:set_enabled(false); error('unsafe remove') end
  Keystrokes.dispose()
  assert(other.enabled and not oldToggle.enabled and not oldCapture.enabled)
  other:set_enabled(false)
end)
test('upgrade avoids the older helper same-key removal path', function()
  Keystrokes.dispose()
  local disabled=false
  Keystrokes={protocol=4, set=function(on) assert(not on) end,
    dispose=function() error('must not call legacy dispose') end,
    _toggle={set_enabled=function(_, on) assert(not on); disabled=true end}}
  dofile(source); assert(disabled and Keystrokes.protocol==5)
end)
test('invalid shortcut settings report a configuration error', function()
  KEYSTROKES_NO_BIND=false
  for _, value in ipairs({42, '', '   ', 'SUPER + K\nBAD'}) do
    KEYSTROKES_TOGGLE_BIND=value
    local bindingCount, timerCount = #binds, #timers
    local ok, message=pcall(dofile, source)
    assert(#binds == bindingCount and #timers == timerCount, "invalid shortcut allocated resources")
    assert(not ok and tostring(message):find('KEYSTROKES_TOGGLE_BIND'))
  end
end)
test('failed unlink retains ownership and retries without enabling capture', function()
  start(); local remove=os.remove
  os.remove=function(path)
    if path==directory .. '/events' then return nil, 'injected', 13 end
    return remove(path)
  end
  assert(Keystrokes.stop(token)=='keystrokes-v5 off cleanup-failed')
  assert(not Keystrokes.is_on())
  assert(read()==string.rep(' ',2048))
  assert(Keystrokes.stop('OTHER1234567')=='keystrokes-v5 off')
  os.remove=remove
  assert(Keystrokes.stop(token)=='keystrokes-v5 off')
end)
test('one broken binding does not prevent other cleanup', function()
  start(); local binding=binds[#binds]; local disable=binding.set_enabled
  binding.set_enabled=function() error('injected') end
  assert(Keystrokes.stop(token)=='keystrokes-v5 off cleanup-failed')
  assert(not Keystrokes.is_on() and read()=='')
  for _, b in ipairs(binds) do if b~=binding and b.key:match('^code:') then assert(not b.enabled) end end
  binding.set_enabled=disable
  assert(Keystrokes.stop(token)=='keystrokes-v5 off')
end)
test('real producer frame fixture for JavaScript consumer', function()
  start(); down[37]=true; press(38)
  local file=assert(io.open(os.getenv('XDG_RUNTIME_DIR') .. '/producer.frame','w'))
  file:write(read()); file:close()
end)
for failedStep=1,3 do
  test('failed snapshot rotation step ' .. failedStep .. ' disables capture', function()
    start(); down[37]=true
    local rename=os.rename; local calls=0
    os.rename=function(from,to)
      calls=calls+1
      if calls==failedStep then return nil,'injected',13 end
      return rename(from,to)
    end
    press(38); os.rename=rename
    assert(not Keystrokes.is_on() and read()=='')
  end)
end
for _, failure in ipairs({'write','close'}) do
  test('failed snapshot ' .. failure .. ' disables capture', function()
    start(); down[37]=true; local open=io.open
    io.open=function(path,mode)
      local file, message, code=open(path,mode)
      if path~=directory .. '/spare' or mode~='r+' or not file then return file,message,code end
      return {
        write=function(_,data) if failure=='write' then return nil end; return file:write(data) end,
        close=function() local result=file:close(); if failure=='close' then return nil end; return result end,
      }
    end
    press(38); io.open=open
    assert(not Keystrokes.is_on())
    Keystrokes.stop(token)
  end)
end
test('unavailable callback clock fails closed', function()
  start(); local open=io.open
  io.open=function(path,mode) if path=='/proc/uptime' then return nil end; return open(path,mode) end
  press(38); io.open=open
  assert(not Keystrokes.is_on() and read()=='')
end)
test('partial registration is disabled and cannot start', function()
  local bind=hl.bind; local calls=0
  hl.bind=function(...)
    calls=calls+1
    if calls==12 then error('injected') end
    return bind(...)
  end
  local ok,message=pcall(dofile,source); hl.bind=bind
  assert(not ok and tostring(message):find('initialization%-failed'))
  for _, b in ipairs(binds) do if b.key:match('^code:') then assert(not b.enabled) end end
  assert(Keystrokes.start('ABCDEFGHIJKL',defaults)=='keystrokes-v5 off')
end)
test('focus callbacks fail closed consistently', function()
  start(); local open=io.open
  io.open=function(path,mode)
    if path==directory .. '/spare' and mode=='r+' then error('injected') end
    return open(path,mode)
  end
  events['window.active'].callback(); io.open=open
  assert(not Keystrokes.is_on())
  Keystrokes.stop(token)
end)
print(count .. ' capture regression tests passed')
