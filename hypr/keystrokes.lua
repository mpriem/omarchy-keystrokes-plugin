-- Capture is off on every load. Non-consuming, non-repeating bindings use
-- locked=false so Hyprland suppresses them before dispatching locked input.
-- Only filtered events enter the private tmpfs transport; no raw key log.
if Keystrokes then
  if Keystrokes.protocol == 5 and Keystrokes.dispose then
    local ok, cleaned = pcall(Keystrokes.dispose)
    if not ok or cleaned == false then
      print('keystrokes: reload-cleanup-failed')
      return
    end
  else
    if Keystrokes.set then pcall(Keystrokes.set, false) end
    if Keystrokes._toggle then pcall(function() Keystrokes._toggle:set_enabled(false) end) end
    if Keystrokes._subscription then pcall(function() Keystrokes._subscription:remove() end) end
  end
end

local toggleKey = KEYSTROKES_TOGGLE_BIND
if not KEYSTROKES_NO_BIND then
  if toggleKey == nil then toggleKey = 'SUPER + SHIFT + K' end
  assert(type(toggleKey) == 'string' and #toggleKey <= 128 and toggleKey:find('%S') and not toggleKey:find('[^ -~]'),
    'KEYSTROKES_TOGGLE_BIND must be a non-empty shortcut string, e.g. SUPER + SHIFT + K')
end

local K = { protocol = 5 }
local available = false
Keystrokes = K
local bindings, subscriptions, queue = {}, {}, {}
local owner, directory, options, watchdog, autoOffAt
local enabled, pending, sequence, generation = false, false, 0, 0
local lastAck, lastPublish = 0, 0
local pauseReason, sudoMatch = nil, 0
local SUDO_KEYS = {39, 30, 40, 32, 65} -- s u d o Space, physical US layout
local MAX_EVENTS, LEASE_SECONDS = 32, 1
local MAX_COUNTER = 2147483647
local MODS = { [37]=1, [105]=1, [50]=2, [62]=2, [64]=4, [108]=4, [133]=8, [134]=8 }

-- Read the registered binding, so disabled or expired handles have no hint.
function K.shortcut()
  local b = K._toggle
  if not b or not b.enabled then return '' end
  local label = b.display_key
  if type(label) ~= 'string' or #label > 128 or label:find('[^ -~]') then return '' end
  return label:match('^%s*(.-)%s*$')
end

-- Linux uptime includes suspend and is independent of wall-clock adjustments.
-- Reading this small kernel file needs no native Lua module or child process.
local function clock()
  local f = io.open('/proc/uptime', 'r')
  if not f then return nil end
  local data = f:read(32)
  f:close()
  return data and tonumber(data:match('^(%d+%.%d+)'))
end

local function stop()
  enabled, pending = false, false
  queue = {}
  pauseReason, sudoMatch = nil, 0
  autoOffAt, options = nil, nil
  local ok = true
  local function attempt(fn)
    local success, result = pcall(fn)
    if not success or result == false then ok = false end
  end
  if watchdog then attempt(function() watchdog:set_enabled(false) end) end
  for _, binding in ipairs(bindings) do
    attempt(function() binding:set_enabled(false) end)
  end
  if directory then
    for _, name in ipairs({'events', 'spare', 'retired'}) do
      attempt(function()
        local f, _, code = io.open(directory .. '/' .. name, 'r+')
        if not f then return code == 2 end
        local written = pcall(function() assert(f:write(string.rep(' ', 2048))) end)
        local closed, result = pcall(function() return f:close() end)
        return written and closed and result ~= nil
      end)
    end
    for _, name in ipairs({'events', 'spare', 'retired', 'ack', 'owner', ''}) do
      attempt(function()
        local removed, _, code = os.remove(directory .. (name ~= '' and '/' .. name or ''))
        return removed or code == 2
      end)
    end
  end
  -- Retain ownership after any failure so stop(token) can retry safely.
  if ok then owner, directory = nil, nil end
  return ok
end

local function alive(now)
  if not directory then return false end
  now = now or clock()
  if not now or now < lastAck or now - lastAck >= LEASE_SECONDS
      or (autoOffAt and now >= autoOffAt) then stop(); return false end
  return true
end

local function publish(now)
  if not directory then return false end
  now = now or clock()
  if not now then stop(); return false end
  if sequence >= MAX_COUNTER then stop(); return false end
  sequence = sequence + 1
  local lines = {string.format('keystrokes-v5 %s %s %d %d', owner, pauseReason or (enabled and 'on' or 'waiting'), generation, sequence)}
  local shortcut = K.shortcut()
  lines[#lines + 1] = shortcut ~= '' and ('b ' .. shortcut) or 'b'
  for _, event in ipairs(queue) do
    if now - event.at < LEASE_SECONDS then lines[#lines + 1] = event.line end
  end
  local payload = table.concat(lines, '\n') .. '\n'
  -- Rotate only pre-created mode-0600 files, never create an event file with
  -- the compositor's umask. The UI retries a brief rename gap or failed read.
  local spare = directory .. '/spare'
  local f = io.open(spare, 'r+')
  if not f then stop(); return false end
  local ok = f:write(payload .. string.rep(' ', 2048 - #payload))
  local closed = f:close()
  if not ok or not closed
      or not os.rename(directory .. '/events', directory .. '/retired')
      or not os.rename(spare, directory .. '/events')
      or not os.rename(directory .. '/retired', spare) then stop(); return false end
  queue, pending, lastPublish = {}, true, now
  return true
end

local function clear()
  sudoMatch = 0
  queue = {}
  if generation >= MAX_COUNTER then stop(); return end
  generation = generation + 1
  if directory then publish() end
end

-- Layer mapping is checked on start, at every key, and by the watchdog.
-- The opened event below stops capture immediately, before password input.
local function polkit_active()
  for _, layer in ipairs(hl.get_layers({namespace='omarchy-polkit'})) do
    if layer.namespace == 'omarchy-polkit' and layer.mapped then return true end
  end
  return false
end

local function pause(reason)
  if not directory or pauseReason == reason then return end
  enabled, pauseReason, sudoMatch, queue = false, reason, 0, {}
  for _, binding in ipairs(bindings) do binding:set_enabled(false) end
  -- Remove the previous frame from both inodes before publishing the reason.
  for _, name in ipairs({'events', 'spare'}) do
    local f = io.open(directory .. '/' .. name, 'r+')
    if not f then stop(); return end
    local ok = f:write(string.rep(' ', 2048)); local closed = f:close()
    if not ok or not closed then stop(); return end
  end
  if generation >= MAX_COUNTER then stop(); return end
  generation = generation + 1
  publish()
end

-- Retain only a prefix length, never a buffer of the user's typed text.
local function detect_sudo(code, mods)
  if not options.sudoProtection then return false end
  if mods ~= 0 then sudoMatch = 0; return false end
  if code == SUDO_KEYS[sudoMatch + 1] then sudoMatch = sudoMatch + 1
  else sudoMatch = code == SUDO_KEYS[1] and 1 or 0 end
  if sudoMatch == #SUDO_KEYS then pause('sudo'); return true end
  return false
end

local function allowed_app()
  local window = hl.get_active_window()
  if not window or window.active ~= true or type(window.class) ~= 'string' or window.class == '' then return false end
  local class = window.class:lower()
  for _, excluded in ipairs(options.hideFor) do
    if class:find(excluded, 1, true) then return false end
  end
  return true
end

local function capture(code)
  local now = clock()
  if not enabled or not now or not alive(now) then
    if enabled and not now then stop() end
    return
  end
  if polkit_active() then pause('polkit'); return end
  if not allowed_app() then clear(); return end
  local mods = 0
  for key, bit in pairs(MODS) do
    if key == code or hl.is_key_down(key) then mods = mods | bit end
  end
  if detect_sudo(code, mods) then return end
  if MODS[code] then
    if not options.modifiersAlone or mods & ~MODS[code] ~= 0 then return end
  elseif options.combosOnly and mods & 13 == 0 then return end
  if #queue >= MAX_EVENTS then table.remove(queue, 1) end
  queue[#queue + 1] = { line = string.format('p %d %d 0', code, mods), at = now }
  if not pending then publish(now) end
end

local function tick()
  local now = clock()
  if not now then stop(); return end
  if not alive(now) then return end
  if polkit_active() then pause('polkit') end
  if not directory then return end
  local f = io.open(directory .. '/ack', 'r')
  if not f then stop(); return end
  local ack = f:read(128)
  f:close()
  -- An unchanged/stale acknowledgement never extends the capture lease.
  if pending and ack and ack:match('^' .. owner .. ' ' .. sequence .. '\n?$') then
    lastAck, pending = now, false
    if not lastAck then stop(); return end
    if not enabled and not pauseReason then
      enabled = true
      for _, binding in ipairs(bindings) do binding:set_enabled(true) end
    end
  end
  if not allowed_app() and #queue > 0 then clear() end
  if not pending and (#queue > 0 or now - lastPublish >= 0.2) then publish(now) end
end

function K.start(token, cfg)
  if not available then return 'keystrokes-v5 off' end
  if not stop() then return 'keystrokes-v5 off cleanup-failed' end
  if type(token) ~= 'string' or #token ~= 12 or not token:match('^%w+$') or type(cfg) ~= 'table'
      or type(cfg.combosOnly) ~= 'boolean' or type(cfg.sudoProtection) ~= 'boolean' or type(cfg.modifiersAlone) ~= 'boolean'
      or type(cfg.hideFor) ~= 'table' or #cfg.hideFor > 64
      or type(cfg.autoOffMinutes) ~= 'number' or cfg.autoOffMinutes < 0 or cfg.autoOffMinutes > 1440
      or cfg.autoOffMinutes ~= cfg.autoOffMinutes then return 'keystrokes-v5 off' end
  local exclusions = {}
  for _, value in ipairs(cfg.hideFor) do
    if type(value) ~= 'string' or #value > 512 then return 'keystrokes-v5 off' end
    local normalized = value:lower():match('^%s*(.-)%s*$')
    if normalized ~= '' then exclusions[#exclusions + 1] = normalized end
  end
  local runtime = os.getenv('XDG_RUNTIME_DIR')
  if not runtime or runtime:sub(1, 1) ~= '/' or runtime == '/' or runtime:sub(-1) == '/' then return 'keystrokes-v5 off' end
  local candidate = runtime .. '/omarchy-keystrokes.' .. token
  local f = io.open(candidate .. '/owner', 'r')
  if not f then return 'keystrokes-v5 off' end
  local marker = f:read(32); f:close()
  if marker ~= token .. '\n' then return 'keystrokes-v5 off' end
  owner, directory = token, candidate
  options = { combosOnly=cfg.combosOnly, sudoProtection=cfg.sudoProtection, modifiersAlone=cfg.modifiersAlone, hideFor=exclusions }
  sequence, generation, lastAck = 0, 0, clock()
  if polkit_active() then pauseReason = 'polkit' end
  if not lastAck or not publish() then stop(); return 'keystrokes-v5 off' end
  watchdog:set_enabled(true)
  autoOffAt = cfg.autoOffMinutes > 0 and lastAck + cfg.autoOffMinutes * 60 or nil
  return 'keystrokes-v5 waiting'
end

function K.stop(token)
  if token == nil or token == owner then
    if not stop() then return 'keystrokes-v5 off cleanup-failed' end
  end
  return 'keystrokes-v5 off'
end
function K.set(on) if not on then stop() end end
function K.is_on() return enabled and alive() end
function K.dispose()
  available = false
  local cleaned = stop()
  for _, subscription in ipairs(subscriptions) do
    if not pcall(function() subscription:remove() end) then cleaned = false end
  end
  -- Hyprland 0.56.2 removes bindings by key/modifier combination, even through
  -- a handle. Disable only ours; config reload retires them without touching
  -- another binding that happens to use the same combination.
  if K._toggle and not pcall(function() K._toggle:set_enabled(false) end) then cleaned = false end
  return cleaned
end

local function guarded(fn)
  return function(...)
    if not pcall(fn, ...) then
      stop()
      print('keystrokes: callback-failed')
    end
  end
end

local initialized = pcall(function()
  watchdog = hl.timer(guarded(tick), {timeout=100, type='repeat'})
  watchdog:set_enabled(false)
  for code = 9, 255 do
    local binding = hl.bind('code:' .. code, guarded(function() capture(code) end), {
      non_consuming=true, transparent=true, ignore_mods=true, submap_universal=true,
      locked=false, repeating=false,
    })
    bindings[#bindings + 1] = binding
    binding:set_enabled(false)
  end
  subscriptions[#subscriptions + 1] = hl.on('layer.opened', guarded(function(layer)
    if layer.namespace == 'omarchy-polkit' then pause('polkit') end
  end))
  subscriptions[#subscriptions + 1] = hl.on('window.active', guarded(clear))
  subscriptions[#subscriptions + 1] = hl.on('window.class', guarded(clear))
  subscriptions[#subscriptions + 1] = hl.on('config.reloaded', stop)
  subscriptions[#subscriptions + 1] = hl.on('hyprland.shutdown', stop)
  if not KEYSTROKES_NO_BIND then
    K._toggle = hl.bind(toggleKey, hl.dsp.exec_cmd('omarchy-shell markpriem.keystrokes toggle'), {description='Toggle keystroke overlay'})
  end
end)
if not initialized then
  K.dispose()
  error('keystrokes: initialization-failed', 0)
end

available = true
