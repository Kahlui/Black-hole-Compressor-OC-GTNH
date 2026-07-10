local component = require("component")
local sides = require("sides")
local computer = require("computer")

local bhc = component.gt_machine
local r = component.redstone
local t = component.transposer

local n = 0

-- CTRL+ALT+C to stop the script at any time.

-- ========= CONFIG =========

-- The Maximum Runtime (s) before closing. Include the base 100s.
local maxRuntime = 660

-- The Target Stability (%) for halting decay.
-- The BHC requires this to be below 20%.
local targetStability = 18

-- How long hasWork() must remain false before the script accepts
-- that the Black Hole was manually or unexpectedly closed.
local manualCloseConfirmSeconds = 5

-- Whether or not to use collapsers.
local useCollapser = true

-- Whether or not to consume extra spacetime to save the last recipe.
local voidProtection = true

-- Side Options: [north, south, east, west, up, down]

-- Side of Redstone I/O with Wireless Receiver.
local receiverSide = sides.north

-- Side of Redstone I/O with Wireless Transmitter.
local transmitterSide = sides.south

-- Side of Redstone I/O with Black Hole Utility Hatch (Optional).
local hatchSide = sides.down

-- Side of Transposer with ME Interface.
local interfaceSide = sides.south

-- Side of Transposer with Super Stock Replenisher.
local stockerSide = sides.up

-- Side of Transposer with Input Bus.
local busSide = sides.down

-- ====== END CONFIG ======

local blackHoleStart = nil
local stabilityReference = 100
local stabilityReferenceTime = nil
local spacetimeEnabled = false
local lastSpacetimeAmount = nil

local function calcSpacetime(duration, amount)
  local total = 0

  for i = 101, duration do
    total = total + 2 ^ math.floor((i - 101) / 30)
  end

  return {
    amount - total,
    total
  }
end

-- Credits: Navatusein
local function parse(number)
  number = tonumber(number) or 0

  return tostring(math.floor(number))
    :reverse()
    :gsub("(%d%d%d)", "%1,")
    :gsub(",(%-?)$", "%1")
    :reverse()
end

local function getSpacetimeAmount()
  local tank = t.getFluidInTank(stockerSide, 1)

  if tank ~= nil and tank.amount ~= nil then
    return tank.amount
  end

  return 0
end

local function getEstimatedStability()
  if blackHoleStart == nil or stabilityReferenceTime == nil then
    return 100
  end

  if spacetimeEnabled then
    return math.max(0, stabilityReference)
  end

  return math.max(
    0,
    stabilityReference
      - (computer.uptime() - stabilityReferenceTime)
  )
end

local function getRecipeInformation()
  local progress = bhc.getWorkProgress() or 0
  local maximum = bhc.getWorkMaxProgress() or 0
  local percent = 0

  if maximum > 0 then
    percent = progress / maximum * 100
  end

  return progress, maximum, percent
end

local function printStatus()
  local currentSpacetime = getSpacetimeAmount()

  local progress, maximum, progressPercent =
    getRecipeInformation()

  local flowStatus

  if not spacetimeEnabled then
    flowStatus = "OFF"
  elseif lastSpacetimeAmount == nil then
    flowStatus = "ON - WAITING FOR SAMPLE"
  elseif currentSpacetime < lastSpacetimeAmount then
    flowStatus = string.format(
      "FLOWING - %s L USED",
      parse(lastSpacetimeAmount - currentSpacetime)
    )
  elseif currentSpacetime > lastSpacetimeAmount then
    flowStatus = string.format(
      "ON - STOCKER REFILLED %s L",
      parse(currentSpacetime - lastSpacetimeAmount)
    )
  else
    flowStatus = "ON - NO TANK DROP DETECTED"
  end

  print(string.format(
    "BHC: Stability ~%.1f%% | Recipe %.1f%% (%s/%s) | Spacetime %s | Tank %s L",
    getEstimatedStability(),
    progressPercent,
    parse(progress),
    parse(maximum),
    flowStatus,
    parse(currentSpacetime)
  ))

  lastSpacetimeAmount = currentSpacetime
end

local function enableSpacetime()
  local currentStability = getEstimatedStability()

  stabilityReference = currentStability
  stabilityReferenceTime = computer.uptime()
  spacetimeEnabled = true
  lastSpacetimeAmount = getSpacetimeAmount()

  r.setOutput(transmitterSide, 15)

  print("BHC: Spacetime transmitter enabled!")
end

local function disableSpacetime(showMessage)
  local currentStability = getEstimatedStability()

  stabilityReference = currentStability
  stabilityReferenceTime = computer.uptime()
  spacetimeEnabled = false
  lastSpacetimeAmount = getSpacetimeAmount()

  r.setOutput(transmitterSide, 0)

  if showMessage then
    print("BHC: Spacetime transmitter disabled!")
  end
end

local function resetRuntimeState()
  blackHoleStart = nil
  stabilityReference = 100
  stabilityReferenceTime = nil
  spacetimeEnabled = false
  lastSpacetimeAmount = nil
end

local function resetAfterUnexpectedClose()
  disableSpacetime(false)
  bhc.setWorkAllowed(true)
  resetRuntimeState()
  n = 0

  print(
    "BHC: Black Hole remained inactive for "
      .. manualCloseConfirmSeconds
      .. " seconds."
  )

  print(
    "BHC: Treating this as a manual or unexpected shutdown."
  )

  print(
    "BHC: Controller reset and ready for the next Black Hole."
  )
end

local function confirmBlackHoleClosed()
  if bhc.hasWork() then
    return false
  end

  local confirmationStart = computer.uptime()
  local nextMessage = confirmationStart

  while computer.uptime() - confirmationStart
      < manualCloseConfirmSeconds do

    if bhc.hasWork() then
      print(
        "BHC: Work resumed. Ignoring temporary inactive state."
      )

      return false
    end

    local now = computer.uptime()

    if now >= nextMessage then
      local elapsed = now - confirmationStart
      local remaining = math.max(
        0,
        manualCloseConfirmSeconds - elapsed
      )

      print(string.format(
        "BHC: No active work detected; confirming shutdown for %.1f more seconds...",
        remaining
      ))

      nextMessage = nextMessage + 1
    end

    os.sleep(0.1)
  end

  return not bhc.hasWork()
end

local function blackHoleStillOpen()
  if bhc.hasWork() then
    return true
  end

  if confirmBlackHoleClosed() then
    resetAfterUnexpectedClose()
    return false
  end

  return true
end

local function statusSleep(duration)
  duration = math.max(
    tonumber(duration) or 0,
    0
  )

  local finishTime = computer.uptime() + duration

  while computer.uptime() < finishTime do
    if not blackHoleStillOpen() then
      return false
    end

    printStatus()

    local remaining = finishTime - computer.uptime()

    if remaining > 0 then
      os.sleep(math.min(1, remaining))
    end
  end

  return true
end

local function waitForBlackHoleStart()
  while not bhc.hasWork() do
    os.sleep(0.1)
  end

  blackHoleStart = computer.uptime()
  stabilityReference = 100
  stabilityReferenceTime = blackHoleStart
  spacetimeEnabled = false
  lastSpacetimeAmount = getSpacetimeAmount()

  print("BHC: Black Hole started!")
  printStatus()
end

local function waitForBlackHoleFinish()
  local inactiveSince = nil

  while true do
    if bhc.hasWork() then
      inactiveSince = nil
      printStatus()
      os.sleep(1)
    else
      if inactiveSince == nil then
        inactiveSince = computer.uptime()
      end

      if computer.uptime() - inactiveSince >= 1 then
        return
      end

      os.sleep(0.1)
    end
  end
end

local function runBlackHoleCycle()
  local availableSpacetime = getSpacetimeAmount()

  local spacetimeCheck = calcSpacetime(
    maxRuntime,
    availableSpacetime
  )

  if spacetimeCheck[1] < 0 then
    print(string.format(
      "BHC: Missing %s L Spacetime!",
      parse(-spacetimeCheck[1])
    ))

    return
  end

  print("")

  print(string.format(
    "BHC: Target %ss with %s L Spacetime!",
    parse(maxRuntime),
    parse(spacetimeCheck[2])
  ))

  print(string.format(
    "BHC: Available Spacetime: %s L",
    parse(availableSpacetime)
  ))

  print("BHC: Opening Black Hole!")

  local seedMoved = t.transferItem(
    interfaceSide,
    busSide,
    1,
    1
  )

  if seedMoved == 0 then
    print(
      "BHC ERROR: Failed to transfer Black Hole Seed!"
    )

    return
  end

  waitForBlackHoleStart()

  if maxRuntime > 100 then
    -- With targetStability = 18, this waits about 82 seconds.
    if not statusSleep(
      math.max(100 - targetStability, 0)
    ) then
      return
    end

    if not blackHoleStillOpen() then
      return
    end

    print(string.format(
      "BHC: Injecting Spacetime at approximately %.1f%% stability!",
      getEstimatedStability()
    ))

    enableSpacetime()
    printStatus()

    if not statusSleep(
      math.max(maxRuntime - 100, 0)
    ) then
      return
    end

    if not blackHoleStillOpen() then
      return
    end

    if voidProtection then
      local maxProgress =
        bhc.getWorkMaxProgress() or 0

      local currentProgress =
        bhc.getWorkProgress() or 0

      local timeNeeded =
        (maxProgress - currentProgress) / 20

      local extraTime = math.max(
        timeNeeded - targetStability + 1,
        0
      )

      if extraTime > 0 then
        print(string.format(
          "BHC: Void protection waiting %.1f additional seconds.",
          extraTime
        ))

        if not statusSleep(extraTime) then
          return
        end
      else
        print(
          "BHC: Current recipe does not require additional protection time."
        )
      end
    end

    disableSpacetime(true)
    printStatus()
  else
    if not statusSleep(60) then
      return
    end

    local maxProgress =
      bhc.getWorkMaxProgress() or 0

    local currentProgress =
      bhc.getWorkProgress() or 0

    local timeNeeded = math.max(
      1,
      maxProgress / 20
    )

    local timeRemaining =
      40
      - (
        maxProgress
        - currentProgress
      ) / 20

    local alignmentWait =
      (
        math.floor(
          timeRemaining / timeNeeded
        ) * timeNeeded
      ) - 1

    if not statusSleep(
      math.max(alignmentWait, 0)
    ) then
      return
    end
  end

  if not blackHoleStillOpen() then
    return
  end

  bhc.setWorkAllowed(false)

  if useCollapser then
    print("BHC: Closing Black Hole!")

    local collapserMoved = t.transferItem(
      interfaceSide,
      busSide,
      1,
      2
    )

    if collapserMoved == 0 then
      print(
        "BHC ERROR: Failed to transfer Collapser!"
      )

      bhc.setWorkAllowed(true)
      return
    end
  else
    local c = 0

    print(
      "BHC: Waiting for utility hatch shutdown."
    )

    while r.getInput(hatchSide) > 0 do
      os.sleep(20)
      c = c + 1

      if c > 47 then
        print(
          "BHC WARNING: Utility hatch timeout reached."
        )

        break
      end
    end
  end

  waitForBlackHoleFinish()

  bhc.setWorkAllowed(true)

  print("BHC: Black Hole closed!")

  resetRuntimeState()
  n = 0
end

-- Ensure the Spacetime transmitter is off when the script starts.
r.setOutput(transmitterSide, 0)
resetRuntimeState()

-- ==========================
--          MAIN LOOP
-- ==========================

while true do
  -- Subnet has items and manual override is NOT set.
  if r.getInput(receiverSide) > 0 then

    -- There is a seed available in interface slot 1.
    if t.getStackInSlot(
      interfaceSide,
      1
    ) ~= nil then

      -- There is a collapser available in interface slot 2,
      -- unless collapsers are disabled in the config.
      if t.getStackInSlot(
        interfaceSide,
        2
      ) ~= nil or not useCollapser then

        runBlackHoleCycle()
      else
        print(
          "BHC: No Collapsers Available!"
        )
      end
    else
      print(
        "BHC: No Seeds Available!"
      )
    end
  elseif n == 0 then
    print(
      "BHC: Sleeping..."
    )

    n = 1
  end

  os.sleep(3)
end
