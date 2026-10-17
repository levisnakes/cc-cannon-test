-- Cannon Test v1.1.0
-- Test + calibrate a Create Radar turret (Auto Yaw/Pitch Controller + Fire Controller) from CC.
-- Type "help" for commands. Calibration is saved to cannon.cfg.

local FIRE_SECONDS_MAX = 10   -- longest burst allowed
local SWEEP_WAIT = 4          -- seconds per step in "sweep"
local CFG_FILE = "cannon.cfg"
local TRACK_STEP = 0.25       -- seconds between aim updates when tracking
local AIM_TOLERANCE = 3       -- degrees the aim may move per step and still count as on target
local MIN_TARGET_DIST = 12    -- ignore Sable tracks this close (your own turret/ship)

local cfg = { x = nil, y = nil, z = nil, yawOffset = 0, yawSign = 1, pitchOffset = 0, pitchSign = 1 }
local armed = false
local yawC, pitchC, fireC, radar
local lastTracks = {}

local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end

local function loadCfg()
  if not fs.exists(CFG_FILE) then return end
  local f = fs.open(CFG_FILE, "r"); local t = textutils.unserialize(f.readAll()); f.close()
  if type(t) == "table" then for k, v in pairs(t) do cfg[k] = v end end
end

local function saveCfg()
  local f = fs.open(CFG_FILE, "w"); f.write(textutils.serialize(cfg)); f.close()
end

local function say(color, text)
  if term.isColor() then term.setTextColor(color) end
  print(text)
  term.setTextColor(colors.white)
end

-- remote peripherals show up twice with two modems, so de-duplicate
local function names()
  local seen, out = {}, {}
  for _, n in ipairs(peripheral.getNames()) do
    if not seen[n] then seen[n] = true; out[#out + 1] = n end
  end
  return out
end

local function isType(name, short)
  if peripheral.hasType and peripheral.hasType(name, "create_radar:" .. short) then return true end
  for _, t in ipairs({ peripheral.getType(name) }) do
    if t == "create_radar:" .. short or t == short then return true end
  end
  return false
end

local function hasMethod(name, m)
  for _, x in ipairs(peripheral.getMethods(name) or {}) do if x == m then return true end end
  return false
end

local function findAll()
  yawC, pitchC, fireC, radar = nil, nil, nil, nil
  for _, n in ipairs(names()) do
    if isType(n, "auto_yaw_controller") or isType(n, "yaw_controller") then yawC = yawC or n
    elseif isType(n, "auto_pitch_controller") or isType(n, "pitch_controller") then pitchC = pitchC or n
    elseif isType(n, "fire_controller") then fireC = fireC or n
    elseif hasMethod(n, "getTracks") and hasMethod(n, "getRange") then radar = radar or n end
  end
end

local function call(name, method, ...)
  if not name then return nil, "not connected" end
  local ok, a = pcall(peripheral.call, name, method, ...)
  if not ok then return nil, a end
  return a
end

local function fmt(n) return n and string.format("%.1f", n) or "?" end

local function status()
  findAll()
  say(colors.yellow, "-- Cannon Test --")
  print("Yaw ctrl:   " .. (yawC or "MISSING") .. (yawC and ("  target " .. fmt(call(yawC, "getAngle"))) or ""))
  print("Pitch ctrl: " .. (pitchC or "MISSING") .. (pitchC and ("  target " .. fmt(call(pitchC, "getAngle"))) or ""))
  print("Fire ctrl:  " .. (fireC or "MISSING") .. (fireC and ("  powered " .. tostring(call(fireC, "isPowered"))) or ""))
  print("Radar:      " .. (radar or "none") .. (radar and ("  range " .. fmt(call(radar, "getRange"))) or ""))
  print("Cannon pos: " .. (cfg.x and (cfg.x .. " " .. cfg.y .. " " .. cfg.z) or "not set (pos x y z)"))
  print("Calib: yaw " .. cfg.yawSign .. "x+" .. cfg.yawOffset .. "  pitch " .. cfg.pitchSign .. "x+" .. cfg.pitchOffset)
  if armed then say(colors.red, "ARMED") else say(colors.lime, "SAFE (type arm to allow firing)") end
end

local function setYaw(d)
  local _, err = call(yawC, "setAngle", d)
  if err then say(colors.red, "yaw: " .. tostring(err)) else print("yaw -> " .. fmt(d)) end
end

local function setPitch(d)
  local _, err = call(pitchC, "setAngle", d)
  if err then say(colors.red, "pitch: " .. tostring(err)) else print("pitch -> " .. fmt(d)) end
end

local function fireOff() pcall(peripheral.call, fireC, "fireOff") end

-- the Fire Controller turns itself off 0.5s after the last command,
-- so a held trigger is keepFiring() repeated every 0.25s
local function burst(seconds)
  if not armed then say(colors.red, "SAFE - type arm first"); return end
  if not fireC then say(colors.red, "no Fire Controller"); return end
  seconds = math.min(seconds, FIRE_SECONDS_MAX)
  say(colors.red, "FIRING " .. seconds .. "s (any key stops)")
  local stopAt = os.clock() + seconds
  local timer = os.startTimer(0)
  while os.clock() < stopAt do
    local ev = { os.pullEvent() }
    if ev[1] == "key" or ev[1] == "char" then break end
    if ev[1] == "timer" and ev[2] == timer then
      call(fireC, "keepFiring")
      timer = os.startTimer(0.25)
    end
  end
  fireOff()
  print("fire off")
end

local function wait(s)
  local t = os.startTimer(s)
  while true do
    local e, id = os.pullEvent()
    if e == "timer" and id == t then return true end
    if e == "key" then return false end
  end
end

local function sweep()
  say(colors.yellow, "Sweep: watch which way the barrel points. Any key stops.")
  for _, d in ipairs({ 0, 90, 180, 270, 0 }) do
    setYaw(d)
    if not wait(SWEEP_WAIT) then print("stopped"); return end
  end
  for _, d in ipairs({ 0, 15, 30, 45, 0 }) do
    setPitch(d)
    if not wait(SWEEP_WAIT) then print("stopped"); return end
  end
  print("Done. Tell yaw 0 = which compass direction, and if pitch went up or down.")
end

-- straight-line angles to a world point (no shell drop yet)
-- Minecraft yaw: 0 = south (+Z), 90 = west, 180 = north, 270 = east
local function anglesTo(x, y, z)
  local dx, dy, dz = x - cfg.x, y - cfg.y, z - cfg.z
  local yaw = math.deg(atan2(-dx, dz)) % 360
  local pitch = math.deg(atan2(dy, math.sqrt(dx * dx + dz * dz)))
  return (yaw * cfg.yawSign + cfg.yawOffset) % 360, pitch * cfg.pitchSign + cfg.pitchOffset,
    math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function tracks()
  if not radar then say(colors.red, "no radar connected"); return end
  local list, err = call(radar, "getTracks")
  if not list then say(colors.red, tostring(err)); return end
  lastTracks = {}
  for _, t in pairs(list) do
    if t.position then
      local d
      if cfg.x then d = select(3, anglesTo(t.position.x, t.position.y, t.position.z)) end
      lastTracks[#lastTracks + 1] = { t = t, d = d or 0 }
    end
  end
  table.sort(lastTracks, function(a, b) return a.d < b.d end)
  if #lastTracks == 0 then print("radar sees nothing"); return end
  for i = 1, math.min(#lastTracks, 8) do
    local t = lastTracks[i].t
    print(i .. ") " .. tostring(t.category) .. " " .. tostring(t.entityType or "") ..
      (cfg.x and ("  " .. fmt(lastTracks[i].d) .. "m") or ""))
  end
  print("aimat <n> to point at one")
end

local function aimAt(i)
  if not cfg.x then say(colors.red, "set the cannon position first: pos x y z  (or pos gps)"); return end
  local e = lastTracks[i]
  if not e then say(colors.red, "run tracks first, then aimat <n>"); return end
  local p = e.t.position
  local yaw, pitch, d = anglesTo(p.x, p.y, p.z)
  print("target " .. i .. " at " .. fmt(d) .. "m")
  setYaw(yaw); setPitch(pitch)
end

-- follow the nearest Sable ship; with fire=true, shoot once the aim settles
local function trackSable(fire)
  if not cfg.x then say(colors.red, "set the cannon position first: pos x y z"); return end
  if not radar then say(colors.red, "no radar connected"); return end
  if fire and not armed then say(colors.red, "SAFE - type arm first (or use: sable)"); return end
  say(colors.yellow, "Tracking nearest SABLE" .. (fire and " + FIRING" or "") .. " - any key stops")
  local lockId, lastYaw, lastPitch
  local timer = os.startTimer(0)
  local _, row = term.getCursorPos()
  while true do
    local ev = { os.pullEvent() }
    if ev[1] == "key" or ev[1] == "char" then break end
    if ev[1] == "timer" and ev[2] == timer then
      timer = os.startTimer(TRACK_STEP)
      local best, bestD, locked
      for _, t in pairs(call(radar, "getTracks") or {}) do
        if t.category == "SABLE" and t.position then
          local d = select(3, anglesTo(t.position.x, t.position.y, t.position.z))
          if d >= MIN_TARGET_DIST then
            if lockId ~= nil and t.id == lockId then locked = t end
            if not bestD or d < bestD then best, bestD = t, d end
          end
        end
      end
      local t = locked or best
      local line
      if not t then
        lockId, lastYaw = nil, nil
        fireOff()
        line = "no Sable in range"
      else
        lockId = t.id
        local yaw, pitch, d = anglesTo(t.position.x, t.position.y, t.position.z)
        call(yawC, "setAngle", yaw)
        call(pitchC, "setAngle", pitch)
        -- aim counts as settled when the target angle barely moved since last step
        local steady = lastYaw and math.abs(((yaw - lastYaw + 180) % 360) - 180) < AIM_TOLERANCE
          and math.abs(pitch - lastPitch) < AIM_TOLERANCE
        lastYaw, lastPitch = yaw, pitch
        local shooting = fire and armed and steady and d <= (call(radar, "getRange") or 0)
        if shooting then call(fireC, "keepFiring") else fireOff() end
        line = string.format("SHIP %s  %.0fm  yaw %.1f pitch %.1f %s", tostring(t.id):sub(1, 6), d, yaw, pitch,
          shooting and "FIRE" or (steady and "on target" or "turning"))
      end
      term.setCursorPos(1, row); term.clearLine(); write(line)
    end
  end
  fireOff()
  print(""); print("tracking stopped")
end

local HELP = {
  "status            what's connected",
  "yaw <deg>         turn the mount",
  "pitch <deg>       raise/lower the barrel",
  "aim <yaw> <pitch> both at once",
  "sweep             step yaw + pitch to learn directions",
  "arm / safe        allow / block firing",
  "fire              one shot (0.5s pulse)",
  "burst <sec>       hold the trigger",
  "stop              cease fire + release controllers",
  "pos x y z | pos gps   cannon position (for aiming)",
  "yawoff <deg> | yawflip | pitchoff <deg> | pitchflip",
  "tracks / aimat <n>     list radar contacts / point at one",
  "sable             follow the nearest Sable ship (no firing)",
  "sable fire        follow it and shoot (needs arm)",
  "exit",
}

local function run()
  loadCfg()
  term.clear(); term.setCursorPos(1, 1)
  status()
  print("type help for commands")
  while true do
    if term.isColor() then term.setTextColor(armed and colors.red or colors.lime) end
    write(armed and "ARMED> " or "safe> ")
    term.setTextColor(colors.white)
    local line = read()
    local w = {}
    for p in line:gmatch("%S+") do w[#w + 1] = p end
    local c, a, b = (w[1] or ""):lower(), tonumber(w[2]), tonumber(w[3])
    if c == "help" then for _, h in ipairs(HELP) do print(h) end
    elseif c == "status" then status()
    elseif c == "yaw" and a then setYaw(a)
    elseif c == "pitch" and a then setPitch(a)
    elseif c == "aim" and a and b then setYaw(a); setPitch(b)
    elseif c == "sweep" then sweep()
    elseif c == "arm" then armed = true; say(colors.red, "ARMED")
    elseif c == "safe" then armed = false; fireOff(); say(colors.lime, "SAFE")
    elseif c == "fire" then
      if not armed then say(colors.red, "SAFE - type arm first")
      elseif not fireC then say(colors.red, "no Fire Controller")
      else call(fireC, "fireOn"); say(colors.red, "BANG") end
    elseif c == "burst" then burst(a or 1)
    elseif c == "stop" then
      fireOff(); call(yawC, "stopAuto"); call(pitchC, "stopAuto"); print("stopped")
    elseif c == "pos" and w[2] == "gps" then
      local x, y, z = gps.locate(2)
      if x then cfg.x, cfg.y, cfg.z = math.floor(x), math.floor(y), math.floor(z); saveCfg(); print("pos " .. cfg.x .. " " .. cfg.y .. " " .. cfg.z)
      else say(colors.red, "no GPS fix - use pos x y z") end
    elseif c == "pos" and a and b and tonumber(w[4]) then
      cfg.x, cfg.y, cfg.z = a, b, tonumber(w[4]); saveCfg(); print("saved")
    elseif c == "yawoff" and a then cfg.yawOffset = a; saveCfg(); print("saved")
    elseif c == "pitchoff" and a then cfg.pitchOffset = a; saveCfg(); print("saved")
    elseif c == "yawflip" then cfg.yawSign = -cfg.yawSign; saveCfg(); print("yaw sign " .. cfg.yawSign)
    elseif c == "pitchflip" then cfg.pitchSign = -cfg.pitchSign; saveCfg(); print("pitch sign " .. cfg.pitchSign)
    elseif c == "tracks" then tracks()
    elseif c == "aimat" and a then aimAt(a)
    elseif c == "sable" then trackSable(w[2] == "fire")
    elseif c == "exit" then fireOff(); return
    elseif c ~= "" then say(colors.orange, "unknown - type help") end
  end
end

local ok, err = pcall(run)
fireOff()
if not ok and err ~= "Terminated" then printError(err) end
