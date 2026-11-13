-- Run from the repository root with Lua 5.2 or 5.3.
local logs, transfers, reserve, seed, enabled = {}, 0, 0, nil, false
local sides = { down = 0, up = 1, north = 2, south = 3, west = 4, east = 5 }
package.preload.sides = function() return sides end
package.preload.computer = function()
  return {
    uptime = function() return 0 end,
  }
end
package.preload.term = function() return {} end
package.preload.component = function()
  return {
    gt_machine = {
      setWorkAllowed = function(v) enabled = v end,
    },
    redstone = {
      getInput = function() return 0 end,
    },
    transposer = {
      getStackInSlot = function(side, slot)
        assert(side == sides.south and slot == 1)
        return seed
      end,
      getFluidInTank = function(side)
        assert(side == sides.up, "only the single configured stocker should be read")
        if reserve == nil then error("stocker missing") end
        return { amount = reserve }
      end,
      transferItem = function(from, to, count, slot)
        assert(from == sides.south and to == sides.down and count == 1 and slot == 1)
        transfers = transfers + 1
        return 0 -- Stop before waiting for real hardware to open the hole.
      end,
    },
  }
end
local originalPrint = print
print = function(message) logs[#logs + 1] = tostring(message) end

-- Expose local functions in this test chunk without starting the infinite loop.
local file = assert(io.open("bhc.lua", "r"))
local source = file:read("*a")
file:close()
local startup = assert(source:find("%-%- =+ STARTUP =+"))
local api = assert(load(source:sub(1, startup - 1) .. [[
return {detect=detectSeed, calculate=calculateSpacetime,
  accept=acceptSpacetimeReserve, reset=resetState, run=runCycle,
  state=state, runtime=function(v) maxRuntime=v end}
]]))()

local checks = 0
local function check(value, message)
  assert(value, message)
  checks = checks + 1
end
local function stack(damage, name)
  return { name = name or "gregtech:gt.metaitem.01", damage = damage, label = "A renamed or localized item" }
end

local name, cost = api.detect(stack(32418))
check(name == "Black Hole Seed" and cost == 1, "normal seed identity")
name, cost = api.detect(stack(32421))
check(name == "Supermassive Black Hole Seed" and cost == 64, "supermassive seed identity")
check(api.detect(stack(32421, "other:item")) == nil, "reject unrelated registry name")
check(api.detect(stack(32420)) == nil, "reject stabilizer")
check(api.detect(stack(30418)) == nil, "reject incorrect normal seed offset")
check(api.detect(stack(30421)) == nil, "reject incorrect supermassive seed offset")
check(api.detect(nil) == nil, "reject empty slot")

for _, base in ipairs({ 1, 64 }) do
  api.state.spacetimeBaseCost = base
  for _, case in ipairs({ { 100, 0 }, { 101, 1 }, { 130, 30 }, { 131, 32 }, { 160, 90 }, { 161, 94 } }) do
    local remaining, needed = api.calculate(case[1], 10000)
    check(needed == case[2] * base and remaining == 10000 - needed, "cost and doubling boundary")
  end
end

for _, case in ipairs({
  { -1, { 1000000001 }, 1, true, true },
  { -1, { 1000000000 }, 1, false, false },
  { -1, { 999999999 }, 1, false, false },
  { -1, { 600000000, 400000001 }, 2, true, true },
  { -1, { 1000000001 }, 0, false, false },
  { 0, { 64 }, 1, true, false },
}) do
  local ok, bypass = api.accept(case[1], case[2], case[3])
  check(ok == case[4] and bypass == case[5], "reserve acceptance boundary")
end

local function attempt(item, amount, runtime)
  api.reset()
  seed, reserve, transfers, logs, enabled = item, amount, 0, {}, false
  api.runtime(runtime)
  api.run()
  return transfers
end
check(attempt(stack(32418), 1, 100) == 1, "normal seed needs 1 L for protection")
check(attempt(stack(32421), 63, 100) == 0, "supermassive reserve rejected before transfer")
check(attempt(stack(32421), 64, 100) == 1, "supermassive seed needs 64 L for protection")
check(api.state.spacetimeBaseCost == 64 and enabled, "seed type recorded before opening")
check(attempt(stack(32418), 1, 100) == 1 and api.state.spacetimeBaseCost == 1, "switching back to normal resets cost")
check(attempt(stack(32421), 1000000001, 1101) == 1, "single stocker above 1G overrides high requirement")
check(table.concat(logs, "\n"):find("accepting the refill setup", 1, true), "override is reported")
check(attempt(stack(32421), 1000000000, 1101) == 0, "exactly 1G does not override")
check(attempt(stack(32421), nil, 100) == 0, "unreadable stocker prevents opening")
check(attempt(stack(32420), 1000000001, 100) == 0, "wrong item never transfers")
check(table.concat(logs, "\n"):find("damage 32420", 1, true), "rejection reports actual metadata")
api.reset()
check(api.state.spacetimeBaseCost == 1, "reset clears previous seed type")
originalPrint(string.format("%d seed/reserve checks passed", checks))
