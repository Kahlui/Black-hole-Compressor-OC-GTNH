-- Simulated complete cycles and dashboard rendering; run from repository root.
local sourcePath = ... or "bhc.lua"
local file = assert(io.open(sourcePath, "r"))
local source = file:read("*a")
file:close()
source = source:sub(1, assert(source:find("%-%- =+ STARTUP =+")) - 1)
local traces = {}
local scenarios = {
  "normal",
  "supermassive",
  "recipe",
  "external",
  "emergency",
  "fallback",
  "transmitter",
  "full",
  "compact",
  "full-empty",
  "compact-empty",
  "full-low",
  "compact-low",
}
for _, scenario in ipairs(scenarios) do
  local now, tx, sleeps, enabled = 0, 0, 0, true
  local hole = scenario == "external" or scenario == "emergency" or scenario == "fallback"
  local actions, pixels = {}, {}
  local function record(name, ...) actions[#actions + 1] = { name, now, ... } end
  local gpu = {}
  for _, name in ipairs({ "set", "fill", "setForeground", "setBackground" }) do
    gpu[name] = function(...) pixels[#pixels + 1] = { name, ... } end
  end
  local modules = {
    sides = { down = 0, up = 1, north = 2, south = 3, west = 4, east = 5 },
    computer = { uptime = function() return now end },
    term = { clear = function() end, setCursor = function() end },
    component = {
      gpu = gpu,
      list = function()
        return function() end
      end,
      gt_machine = {
        hasWork = function() return scenario == "recipe" and now < 104 end,
        getWorkProgress = function() return math.min(now * 20, 2080) end,
        getWorkMaxProgress = function() return 2080 end,
        setWorkAllowed = function(value)
          enabled = value
          record("controller", value)
          if scenario == "fallback" and enabled and now >= 906 then hole = false end
        end,
      },
      redstone = {
        getInput = function(side) return side == 0 and hole and 15 or 0 end,
        getOutput = function() return tx end,
        setOutput = function(_, value)
          record("transmitter", value)
          tx = scenario == "transmitter" and 0 or value
        end,
      },
      transposer = {
        getFluidInTank = function() return { amount = 1000000001 } end,
        getStackInSlot = function(_, slot)
          if slot == 2 and scenario == "fallback" then return nil end
          return { name = "gregtech:gt.metaitem.01", damage = scenario == "supermassive" and 32421 or 32418 }
        end,
        transferItem = function(_, _, _, slot)
          record("item", slot)
          hole = slot == 1
          return 1
        end,
      },
    },
  }
  local env = setmetatable({
    require = function(name) return assert(modules[name], "module unavailable: " .. name) end,
    print = function() end,
    os = {
      date = function() return "12:00:00" end,
      sleep = function(seconds)
        now, sleeps = now + seconds, sleeps + 1
        assert(sleeps < 10000, "simulation did not finish")
      end,
    },
  }, { __index = _G })
  local api = assert(load(source .. [[
    return {state=state, ui=ui, run=runCycle, takeover=adoptExternalBlackHole,
      emergency=emergencyClose, full=drawFullLayout, compact=drawCompactLayout}
  ]], sourcePath, "t", env))()
  if scenario:find("full", 1, true) or scenario:find("compact", 1, true) then
    local full = scenario:find("full", 1, true)
    api.ui.w, api.ui.h = full and 160 or 80, full and 50 or 25
    api.ui.lastSleepText = "Test quote"
    local sample = {
      stability = 18,
      stabilityType = "ACT",
      holeOpen = true,
      recipeActive = true,
      elapsed = 90,
      now = 90,
      tx = 15,
      progress = 400,
      maximum = 800,
      recipePercent = 50,
    }
    if scenario:find("empty", 1, true) then sample = nil end
    if scenario:find("low", 1, true) then sample.stability = 5 end
    local draw = full and api.full or api.compact
    draw(sample, "Test quote")
    assert(#pixels > 100, "dashboard did not render")
  else
    if scenario == "external" then
      api.takeover()
    elseif scenario == "emergency" or scenario == "fallback" then
      api.emergency({ stability = 5, stabilityType = "ACT" }, "Test emergency")
    else
      api.run()
    end
    assert(not hole and tx == 0 and enabled, scenario .. ": closure did not finish")
    assert(api.state.phase == "STANDBY", "state was not reset")
    assert(api.state.spacetimeBaseCost == 1, "seed cost was not reset")
    assert(api.state.holeStart == nil and api.state.spacetimeOnAt == nil, "stale timers after closure")
    assert(#actions >= 4, "no controller actions")
    if scenario == "normal" or scenario == "supermassive" then
      local firstOn
      for _, action in ipairs(actions) do
        if action[1] == "transmitter" and action[3] == 15 then
          firstOn = action[2]
          break
        end
      end
      local expected = 82
      assert(firstOn and math.abs(firstOn - expected) < 0.26, "Spacetime enabled before injection target")
    end
  end
  traces[scenario] = { actions = actions, pixels = pixels }
end
print(string.format("%d complete-cycle and dashboard scenarios passed", #scenarios))
return traces
