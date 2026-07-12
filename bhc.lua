-- Read config closely. Writen by Kahlui/Zach With use of GPT 5.6 for GTNH 2.9 Beta 1

local component = require("component")
local sides = require("sides")
local computer = require("computer")

local bhc = component.gt_machine
local redstone = component.redstone
local transposer = component.transposer

-- CTRL+ALT+C to stop the script.

-- ========================= CONFIG =========================

local maxRuntime = 100
local targetStability = 18
local emergencyCloseStability = 10
local manualCloseConfirmSeconds = 5
local sleepMessageInterval = 15

local closeWhenIdle = true
local idleCloseSeconds = 10
local minimumRuntimeBeforeIdleClose = 100

local useCollapser = true
local voidProtection = true

-- Keep this true so the program visibly reports every second.
local debugShowStatusEverySecond = false

-- Side Options: north, south, east, west, up, down
local receiverSide = sides.north
local transmitterSide = sides.south
local hatchSide = sides.down
local interfaceSide = sides.south
local busSide = sides.down

-- Every ST stocker touching the transposer.
-- Each entry is read separately and then added together.
local stockers = {
  {name = "UP", side = sides.up},
  {name = "WEST", side = sides.west}
}

-- ======================= END CONFIG =======================

local state = {
  seedInsertedAt = nil,
  holeStart = nil,
  stability = 100,
  stabilityTime = nil,
  spacetimeOn = false,
  spacetimeOnAt = nil,
  lastTank = nil,
  lastActualStability = nil,
  lastActualTime = nil,
  actualSeen = false,
  fallbackLossStart = nil,
  fallbackLossStability = nil,
  expectedClosing = false,
  emergencyClosing = false,
  idleSince = nil,
  lastSleepMessage = nil
}

local sleepMessages = {
  "BHC: Sleeping... dreaming of stable spacetime.",
  "BHC: No seeds detected. Reality remains disappointingly intact.",
  "BHC: Waiting for someone to manufacture another expensive mistake.",
  "BHC: The Black Hole is currently on a union-mandated break.",
  "BHC: Idle. EU-network destruction has been postponed.",
  "BHC: Greg reviewed the setup and found it insufficiently complicated.",
  "BHC: ST conserved. The power grid may relax temporarily.",
  "BHC: Nothing to compress. Have you tried building a larger factory?",
  "BHC: Standing by to turn several trillion EU into someone else's problem.",
  "BHC: The event horizon is unavailable. Please try again later.",
  "BHC: Waiting patiently. This is suspiciously unlike GregTech.",
  "BHC: No active request. The Collapser is enjoying its retirement.",
  "BHC: Sleeping lightly in case causality needs supervision.",
  "BHC: Current task: avoiding an exciting containment failure.",
  "BHC: Black Hole offline. Local physics operating within specifications.",
  "BHC: Automation idle. Manual labor remains strongly discouraged.",
  "BHC: The singularity has been asked to wait outside.",
  "BHC: No recipe queued. Progress is temporarily affordable.",
  "BHC: Waiting for more resources to disappear into science.",
  "BHC: System idle. Please insert one irresponsibly dense object.",
  "BHC: Reports of my instability have been greatly exaggerated.",
  "BHC: Experience is the name operators give to voided recipes.",
  "BHC: A Black Hole can resist everything except more ST.",
  "BHC: Good judgment comes from experience. Experience comes from ignoring alarms.",
  "BHC: Never argue with Greg. He will add six prerequisites and win by exhaustion.",
  "BHC: There are three kinds of lies: lies, damned lies, and crafting-time estimates.",
  "BHC: Common sense is not especially common in endgame automation.",
  "BHC: Behind every great factory is a cable carrying too much amperage.",
  "BHC: To err is human; to automate the error requires OpenComputers.",
  "BHC: If at first you do not succeed, increase parallel and blame the power grid.",
  "BHC: Reality is merely a suggestion until the Utility Hatch confirms it.",
  "BHC: The machine is resting. The recipe tree is merely gathering strength."
}

-- ========================== HELPERS ==========================

local function numberText(value)
value = tonumber(value) or 0

return tostring(math.floor(value))
:reverse()
:gsub("(%d%d%d)", "%1,")
:gsub(",(%-?)$", "%1")
:reverse()
end

local function cleanText(value)
return tostring(value or "")
:gsub("\194\167.", "")
:gsub("[\r\n]+", " / ")
:gsub("%s+", " ")
:gsub("^%s+", "")
:gsub("%s+$", "")
end

local function formatElapsed(seconds)
seconds = math.max(0, math.floor(tonumber(seconds) or 0))

local hours = math.floor(seconds / 3600)
local minutes = math.floor((seconds % 3600) / 60)
local remainingSeconds = seconds % 60

return string.format(
  "%02d:%02d:%02d",
  hours,
  minutes,
  remainingSeconds
)
end

local function elapsedRuntime(now)
if not state.seedInsertedAt then
  return 0
  end

  return math.max(
    0,
    (now or computer.uptime()) - state.seedInsertedAt
  )
  end

  local function calculateSpacetime(duration, available)
  local needed = 0

  for second = 101, duration do
    needed = needed
    + 2 ^ math.floor((second - 101) / 30)
    end

    return available - needed, needed
    end

    local function readStocker(stocker)
    if not stocker or type(stocker.side) ~= "number" then
      return 0, false
      end

      local ok, tank = pcall(
        transposer.getFluidInTank,
        stocker.side,
        1
      )

      if not ok or not tank or tank.amount == nil then
        return 0, false
        end

        return tonumber(tank.amount) or 0, true
        end

        local function getTankInformation()
        local total = 0
        local details = {}
        local readable = 0

        for _, stocker in ipairs(stockers) do
          local amount, wasReadable = readStocker(stocker)

          total = total + amount

          if wasReadable then
            readable = readable + 1
            end

            details[#details + 1] = string.format(
              "%s %s L",
              stocker.name or "?",
              numberText(amount)
            )
            end

            return total, details, readable
            end

            local function getTankAmount()
            local total = getTankInformation()
            return total
            end

            local function isHoleOpen()
            return redstone.getInput(hatchSide) > 0
            end

            local function isRecipeActive()
            local ok, result = pcall(bhc.hasWork)
            return ok and result == true
            end

            local function getTX()
            local ok, value = pcall(
              redstone.getOutput,
              transmitterSide
            )

            if ok then
              return tonumber(value) or 0
              end

              return state.spacetimeOn and 15 or 0
              end

              local function enableController(showError)
              local ok, result = pcall(
                bhc.setWorkAllowed,
                true
              )

              if not ok and showError then
                print(
                  "BHC WARNING: Could not enable controller: "
                  .. cleanText(result)
                )
                end

                return ok
                end

                local function resetState()
                local previousSleepMessage = state.lastSleepMessage

                state.seedInsertedAt = nil
                state.holeStart = nil
                state.stability = 100
                state.stabilityTime = nil
                state.spacetimeOn = false
                state.spacetimeOnAt = nil
                state.lastTank = nil
                state.lastActualStability = nil
                state.lastActualTime = nil
                state.actualSeen = false
                state.fallbackLossStart = nil
                state.fallbackLossStability = nil
                state.expectedClosing = false
                state.emergencyClosing = false
                state.idleSince = nil
                state.lastSleepMessage = previousSleepMessage
                end

                -- ===================== STABILITY DATA =====================

                local controllerAddress = bhc.address
                local controllerMethods = nil

                local function sortedKeys(tbl)
                local keys = {}

                for key in pairs(tbl or {}) do
                  keys[#keys + 1] = key
                  end

                  table.sort(keys, function(a, b)
                  return tostring(a) < tostring(b)
                  end)

                  return keys
                  end

                  local function getControllerAddress()
                  if controllerAddress then
                    return controllerAddress
                    end

                    local iterator = component.list("gt_machine", true)

                    if iterator then
                      controllerAddress = iterator()
                      end

                      return controllerAddress
                      end

                      local function getControllerMethods()
                      if controllerMethods then
                        return controllerMethods
                        end

                        local address = getControllerAddress()

                        if not address then
                          return nil
                          end

                          local ok, methods = pcall(component.methods, address)

                          if ok and type(methods) == "table" then
                            controllerMethods = methods
                            return controllerMethods
                            end

                            return nil
                            end

                            local function isReaderMethod(name)
                            return name:match("^get")
                            or name:match("^is")
                            or name:match("^has")
                            or name:match("^can")
                            end

                            local function invokeReader(name)
                            local address = getControllerAddress()

                            if not address then
                              return false, nil
                              end

                              local result = {
                                pcall(component.invoke, address, name)
                              }

                              if not result[1] then
                                return false, nil
                                end

                                table.remove(result, 1)
                                return true, result
                                end

                                local function findStability(value, context, seen, depth)
                                context = tostring(context or "")
                                seen = seen or {}
                                depth = depth or 0

                                if type(value) == "number" then
                                  if context:lower():find("stability", 1, true) then
                                    return tonumber(value)
                                    end

                                    return nil
                                    end

                                    if type(value) == "string" then
                                      local text = cleanText(value)
                                      local lowerText = text:lower()
                                      local lowerContext = context:lower()

                                      if lowerText:find("stability", 1, true)
                                        or lowerContext:find("stability", 1, true) then

                                        local found =
                                        text:match("([%d%.]+)%s*%%")
                                        or text:match("[Ss]tability[^%d]*([%d%.]+)")

                                        if tonumber(found) then
                                          return tonumber(found)
                                          end
                                          end

                                          return nil
                                          end

                                          if type(value) ~= "table"
                                            or seen[value]
                                            or depth >= 4 then

                                            return nil
                                            end

                                            seen[value] = true

                                            for _, key in ipairs(sortedKeys(value)) do
                                              local found = findStability(
                                                value[key],
                                                context .. "[" .. tostring(key) .. "]",
                                                                          seen,
                                                                          depth + 1
                                              )

                                              if found ~= nil then
                                                seen[value] = nil
                                                return found
                                                end
                                                end

                                                seen[value] = nil
                                                return nil
                                                end

                                                local function readActualStability()
                                                local methods = getControllerMethods()

                                                if not methods then
                                                  return nil
                                                  end

                                                  for _, name in ipairs(sortedKeys(methods)) do
                                                    if isReaderMethod(name)
                                                      and name:lower():find("stability", 1, true) then

                                                      local ok, values = invokeReader(name)

                                                      if ok then
                                                        for _, value in ipairs(values) do
                                                          if type(value) == "number" then
                                                            return tonumber(value)
                                                            end

                                                            local found = findStability(value, name, {}, 0)

                                                            if found ~= nil then
                                                              return found
                                                              end
                                                              end
                                                              end
                                                              end
                                                              end

                                                              if methods.getSensorInformation then
                                                                local ok, values = invokeReader("getSensorInformation")

                                                                if ok then
                                                                  for _, value in ipairs(values) do
                                                                    local found = findStability(
                                                                      value,
                                                                      "getSensorInformation",
                                                                      {},
                                                                      0
                                                                    )

                                                                    if found ~= nil then
                                                                      return found
                                                                      end
                                                                      end
                                                                      end
                                                                      end

                                                                      return nil
                                                                      end

                                                                      local function getEstimatedStability(now, tankAmount, tx)
                                                                      now = now or computer.uptime()
                                                                      tankAmount = tankAmount or getTankAmount()
                                                                      tx = tx or getTX()

                                                                      if not state.holeStart or not state.stabilityTime then
                                                                        return nil
                                                                        end

                                                                        if state.spacetimeOn then
                                                                          if tx >= 15 and tankAmount > 0 then
                                                                            state.fallbackLossStart = nil
                                                                            state.fallbackLossStability = nil
                                                                            return math.max(0, state.stability)
                                                                            end

                                                                            if not state.fallbackLossStart then
                                                                              state.fallbackLossStart = now
                                                                              state.fallbackLossStability = state.stability
                                                                              end

                                                                              return math.max(
                                                                                0,
                                                                                state.fallbackLossStability
                                                                                - (now - state.fallbackLossStart)
                                                                              )
                                                                              end

                                                                              return math.max(
                                                                                0,
                                                                                state.stability - (now - state.stabilityTime)
                                                                              )
                                                                              end

                                                                              local function getRecipeData()
                                                                              local progress = bhc.getWorkProgress() or 0
                                                                              local maximum = bhc.getWorkMaxProgress() or 0
                                                                              local percent = 0

                                                                              if maximum > 0 then
                                                                                percent = progress / maximum * 100
                                                                                end

                                                                                return progress, maximum, percent
                                                                                end

                                                                                local function sampleStatus()
                                                                                local now = computer.uptime()
                                                                                local tank = getTankAmount()
                                                                                local tx = getTX()

                                                                                local tankDelta = nil

                                                                                if state.lastTank ~= nil then
                                                                                  tankDelta = state.lastTank - tank
                                                                                  end

                                                                                  state.lastTank = tank

                                                                                  local actual = readActualStability()
                                                                                  local stability
                                                                                  local stabilityType

                                                                                  if actual ~= nil then
                                                                                    state.actualSeen = true
                                                                                    state.lastActualStability = actual
                                                                                    state.lastActualTime = now
                                                                                    state.stability = actual
                                                                                    state.stabilityTime = now
                                                                                    state.fallbackLossStart = nil
                                                                                    state.fallbackLossStability = nil

                                                                                    stability = actual
                                                                                    stabilityType = "ACT"
                                                                                    else
                                                                                      stability = getEstimatedStability(now, tank, tx)
                                                                                      stabilityType = "EST"
                                                                                      end

                                                                                      local progress, maximum, percent = getRecipeData()

                                                                                      return {
                                                                                        now = now,
                                                                                        elapsed = elapsedRuntime(now),
                                                                                        holeOpen = isHoleOpen(),
                                                                                        recipeActive = isRecipeActive(),
                                                                                        progress = progress,
                                                                                        maximum = maximum,
                                                                                        recipePercent = percent,
                                                                                        tank = tank,
                                                                                        tankDelta = tankDelta,
                                                                                        tx = tx,
                                                                                        stability = stability,
                                                                                        stabilityType = stabilityType
                                                                                      }
                                                                                      end

                                                                                      local function flowText(sample)
                                                                                      if not state.spacetimeOn then
                                                                                        return "OFF"
                                                                                        end

                                                                                        if sample.tankDelta == nil then
                                                                                          return "ON - WAITING"
                                                                                          end

                                                                                          if sample.tankDelta > 0 then
                                                                                            return "FLOW "
                                                                                            .. numberText(sample.tankDelta)
                                                                                            .. " L"
                                                                                            end

                                                                                            if sample.tankDelta < 0 then
                                                                                              return "REFILL +"
                                                                                              .. numberText(-sample.tankDelta)
                                                                                              .. " L"
                                                                                              end

                                                                                              return "ON - NO TANK CHANGE"
                                                                                              end

                                                                                              local function printStatus(sample)
                                                                                              sample = sample or sampleStatus()

                                                                                              local stabilityText = "UNKNOWN"

                                                                                              if sample.stability ~= nil then
                                                                                                stabilityText = string.format(
                                                                                                  "%.1f%% %s",
                                                                                                  sample.stability,
                                                                                                  sample.stabilityType
                                                                                                )
                                                                                                end

                                                                                                print(string.format(
                                                                                                  "BHC: T %s | Hole %s | STAB %s | Recipe %s %.1f%% (%s/%s) | ST %s | TX %d | Tank %s L",
                                                                                                                    formatElapsed(sample.elapsed),
                                                                                                                      sample.holeOpen and "OPEN" or "CLOSED",
                                                                                                                    stabilityText,
                                                                                                                    sample.recipeActive and "ACTIVE" or "IDLE",
                                                                                                                    sample.recipePercent,
                                                                                                                    numberText(sample.progress),
                                                                                                                    numberText(sample.maximum),
                                                                                                                    flowText(sample),
                                                                                                                    sample.tx,
                                                                                                                    numberText(sample.tank)
                                                                                                ))
                                                                                                end

                                                                                                local function enableSpacetime()
                                                                                                local now = computer.uptime()
                                                                                                local estimated = getEstimatedStability(
                                                                                                  now,
                                                                                                  getTankAmount(),
                                                                                                                                        getTX()
                                                                                                )

                                                                                                if state.lastActualStability
                                                                                                  and state.lastActualTime
                                                                                                  and now - state.lastActualTime <= 2 then

                                                                                                  estimated = state.lastActualStability
                                                                                                  end

                                                                                                  state.stability = estimated or targetStability
                                                                                                  state.stabilityTime = now
                                                                                                  state.spacetimeOn = true
                                                                                                  state.spacetimeOnAt = now
                                                                                                  state.lastTank = getTankAmount()
                                                                                                  state.fallbackLossStart = nil
                                                                                                  state.fallbackLossStability = nil

                                                                                                  redstone.setOutput(transmitterSide, 15)
                                                                                                  print("BHC: ST transmitter enabled!")
                                                                                                  end

                                                                                                  local function disableSpacetime(showMessage)
                                                                                                  local now = computer.uptime()
                                                                                                  local estimated = getEstimatedStability(
                                                                                                    now,
                                                                                                    getTankAmount(),
                                                                                                                                          getTX()
                                                                                                  )

                                                                                                  if state.lastActualStability
                                                                                                    and state.lastActualTime
                                                                                                    and now - state.lastActualTime <= 2 then

                                                                                                    estimated = state.lastActualStability
                                                                                                    end

                                                                                                    state.stability = estimated or state.stability
                                                                                                    state.stabilityTime = now
                                                                                                    state.spacetimeOn = false
                                                                                                    state.spacetimeOnAt = nil
                                                                                                    state.lastTank = getTankAmount()
                                                                                                    state.fallbackLossStart = nil
                                                                                                    state.fallbackLossStability = nil

                                                                                                    redstone.setOutput(transmitterSide, 0)

                                                                                                    if showMessage then
                                                                                                      print("BHC: ST transmitter disabled!")
                                                                                                      end
                                                                                                      end

                                                                                                      -- ==================== CLOSURE HANDLING ====================

                                                                                                      local function confirmHoleClosed()
                                                                                                      if isHoleOpen() then
                                                                                                        return false
                                                                                                        end

                                                                                                        local started = computer.uptime()

                                                                                                        while computer.uptime() - started
                                                                                                          < manualCloseConfirmSeconds do

                                                                                                          if isHoleOpen() then
                                                                                                            print(
                                                                                                              "BHC: Hatch signal returned; ignoring temporary closed reading."
                                                                                                            )

                                                                                                            return false
                                                                                                            end

                                                                                                            os.sleep(0.1)
                                                                                                            end

                                                                                                            return not isHoleOpen()
                                                                                                            end

                                                                                                            local function unexpectedClosureReset()
                                                                                                            disableSpacetime(false)
                                                                                                            enableController(false)
                                                                                                            resetState()

                                                                                                            print(
                                                                                                              "BHC: Utility hatch remained closed for "
                                                                                                              .. manualCloseConfirmSeconds
                                                                                                              .. " seconds. Controller reset."
                                                                                                            )
                                                                                                            end

                                                                                                            local function holeStillOpen()
                                                                                                            if isHoleOpen() then
                                                                                                              return true
                                                                                                              end

                                                                                                              if state.expectedClosing then
                                                                                                                return false
                                                                                                                end

                                                                                                                if confirmHoleClosed() then
                                                                                                                  unexpectedClosureReset()
                                                                                                                  return false
                                                                                                                  end

                                                                                                                  return true
                                                                                                                  end

                                                                                                                  local function insertCollapserWithRetry()
                                                                                                                  local nextWarning = 0

                                                                                                                  enableController(true)

                                                                                                                  while isHoleOpen() do
                                                                                                                    enableController(false)

                                                                                                                    local moved = transposer.transferItem(
                                                                                                                      interfaceSide,
                                                                                                                      busSide,
                                                                                                                      1,
                                                                                                                      2
                                                                                                                    )

                                                                                                                    if moved and moved > 0 then
                                                                                                                      print(
                                                                                                                        "BHC: Collapser inserted; controller remains enabled."
                                                                                                                      )

                                                                                                                      return true
                                                                                                                      end

                                                                                                                      if computer.uptime() >= nextWarning then
                                                                                                                        print(
                                                                                                                          "BHC CRITICAL: Could not insert Collapser; retrying every second!"
                                                                                                                        )

                                                                                                                        nextWarning = computer.uptime() + 1
                                                                                                                        end

                                                                                                                        os.sleep(1)
                                                                                                                        end

                                                                                                                        return false
                                                                                                                        end

                                                                                                                        local function waitForHoleToClose()
                                                                                                                        local nextPrint = computer.uptime()

                                                                                                                        while isHoleOpen() do
                                                                                                                          enableController(false)

                                                                                                                          if computer.uptime() >= nextPrint then
                                                                                                                            if debugShowStatusEverySecond then
                                                                                                                              printStatus(sampleStatus())
                                                                                                                              end

                                                                                                                              nextPrint = nextPrint + 1
                                                                                                                              end

                                                                                                                              os.sleep(0.1)
                                                                                                                              end
                                                                                                                              end

                                                                                                                              local function normalClose(reason)
                                                                                                                              if state.expectedClosing then
                                                                                                                                return
                                                                                                                                end

                                                                                                                                state.expectedClosing = true

                                                                                                                                if reason then
                                                                                                                                  print("")
                                                                                                                                  print("BHC: " .. reason)
                                                                                                                                  end

                                                                                                                                  enableController(true)

                                                                                                                                  if useCollapser then
                                                                                                                                    print("BHC: Closing Black Hole!")
                                                                                                                                    insertCollapserWithRetry()
                                                                                                                                    else
                                                                                                                                      print(
                                                                                                                                        "BHC: Waiting for the 15-minute utility-hatch automatic shutdown."
                                                                                                                                      )
                                                                                                                                      end

                                                                                                                                      waitForHoleToClose()
                                                                                                                                      disableSpacetime(false)
                                                                                                                                      enableController(false)

                                                                                                                                      print(
                                                                                                                                        "BHC: Utility hatch confirms Black Hole is closed!"
                                                                                                                                      )

                                                                                                                                      resetState()
                                                                                                                                      end

                                                                                                                                      local function emergencyClose(sample, reason)
                                                                                                                                      if state.emergencyClosing then
                                                                                                                                        return false
                                                                                                                                        end

                                                                                                                                        state.emergencyClosing = true
                                                                                                                                        state.expectedClosing = true

                                                                                                                                        print("")
                                                                                                                                        print("BHC EMERGENCY: " .. reason)

                                                                                                                                        if sample and sample.stability ~= nil then
                                                                                                                                          print(string.format(
                                                                                                                                            "BHC EMERGENCY: STAB %.1f%% (%s).",
                                                                                                                                                              sample.stability,
                                                                                                                                                              sample.stabilityType
                                                                                                                                          ))
                                                                                                                                          end

                                                                                                                                          print(
                                                                                                                                            "BHC EMERGENCY: Inserting a Collapser while keeping the controller enabled!"
                                                                                                                                          )

                                                                                                                                          enableController(true)

                                                                                                                                          if useCollapser then
                                                                                                                                            insertCollapserWithRetry()
                                                                                                                                            else
                                                                                                                                              print(
                                                                                                                                                "BHC CRITICAL: Emergency closure requires useCollapser = true."
                                                                                                                                              )
                                                                                                                                              end

                                                                                                                                              waitForHoleToClose()
                                                                                                                                              disableSpacetime(false)
                                                                                                                                              enableController(false)

                                                                                                                                              print(
                                                                                                                                                "BHC: Emergency closure complete; Black Hole is closed."
                                                                                                                                              )

                                                                                                                                              resetState()
                                                                                                                                              return false
                                                                                                                                              end

                                                                                                                                              local function checkEmergency(sample)
                                                                                                                                              if state.expectedClosing or state.emergencyClosing then
                                                                                                                                                return true
                                                                                                                                                end

                                                                                                                                                if sample.stability ~= nil
                                                                                                                                                  and sample.stability <= emergencyCloseStability then

                                                                                                                                                  local reason

                                                                                                                                                  if sample.stabilityType == "ACT" then
                                                                                                                                                    reason = string.format(
                                                                                                                                                      "Actual STAB reached the %.1f%% safety threshold.",
                                                                                                                                                      emergencyCloseStability
                                                                                                                                                    )
                                                                                                                                                    else
                                                                                                                                                      reason = string.format(
                                                                                                                                                        "Estimated STAB reached the %.1f%% safety threshold after TX loss or empty ST stockers.",
                                                                                                                                                        emergencyCloseStability
                                                                                                                                                      )
                                                                                                                                                      end

                                                                                                                                                      emergencyClose(sample, reason)
                                                                                                                                                      return false
                                                                                                                                                      end

                                                                                                                                                      return true
                                                                                                                                                      end

                                                                                                                                                      local function checkIdleClose(sample)
                                                                                                                                                      if not closeWhenIdle
                                                                                                                                                        or not useCollapser
                                                                                                                                                        or state.expectedClosing
                                                                                                                                                        or state.emergencyClosing then

                                                                                                                                                        return true
                                                                                                                                                        end

                                                                                                                                                        if sample.recipeActive then
                                                                                                                                                          state.idleSince = nil
                                                                                                                                                          return true
                                                                                                                                                          end

                                                                                                                                                          if not state.idleSince then
                                                                                                                                                            state.idleSince = sample.now
                                                                                                                                                            end

                                                                                                                                                            local configuredSeconds = math.max(
                                                                                                                                                              0,
                                                                                                                                                              tonumber(idleCloseSeconds) or 0
                                                                                                                                                            )

                                                                                                                                                            local minimumRuntime = math.max(
                                                                                                                                                              0,
                                                                                                                                                              tonumber(minimumRuntimeBeforeIdleClose) or 0
                                                                                                                                                            )

                                                                                                                                                            local idleFor = sample.now - state.idleSince
                                                                                                                                                            local runtimeSinceSeed = elapsedRuntime(sample.now)

                                                                                                                                                            if idleFor >= configuredSeconds
                                                                                                                                                              and runtimeSinceSeed >= minimumRuntime then

                                                                                                                                                              normalClose(string.format(
                                                                                                                                                                "No recipe has been active for %.1f seconds and the %.1f-second minimum runtime has elapsed; closing early.",
                                                                                                                                                                idleFor,
                                                                                                                                                                minimumRuntime
                                                                                                                                                              ))

                                                                                                                                                              return false
                                                                                                                                                              end

                                                                                                                                                              return true
                                                                                                                                                              end

                                                                                                                                                              local function statusSleep(seconds)
                                                                                                                                                              local finish = computer.uptime()
                                                                                                                                                              + math.max(tonumber(seconds) or 0, 0)

                                                                                                                                                              while computer.uptime() < finish do
                                                                                                                                                                if not holeStillOpen() then
                                                                                                                                                                  return false
                                                                                                                                                                  end

                                                                                                                                                                  local sample = sampleStatus()

                                                                                                                                                                  if debugShowStatusEverySecond then
                                                                                                                                                                    printStatus(sample)
                                                                                                                                                                    end

                                                                                                                                                                    if not checkEmergency(sample) then
                                                                                                                                                                      return false
                                                                                                                                                                      end

                                                                                                                                                                      if not checkIdleClose(sample) then
                                                                                                                                                                        return false
                                                                                                                                                                        end

                                                                                                                                                                        local remaining = finish - computer.uptime()

                                                                                                                                                                        if remaining > 0 then
                                                                                                                                                                          os.sleep(math.min(1, remaining))
                                                                                                                                                                          end
                                                                                                                                                                          end

                                                                                                                                                                          return true
                                                                                                                                                                          end

                                                                                                                                                                          -- ==================== BLACK HOLE CYCLE ====================

                                                                                                                                                                          local function waitForHoleOpen()
                                                                                                                                                                          local nextPrint = computer.uptime()

                                                                                                                                                                          while not isHoleOpen() do
                                                                                                                                                                            local now = computer.uptime()

                                                                                                                                                                            if now >= nextPrint then
                                                                                                                                                                              print(string.format(
                                                                                                                                                                                "BHC: T %s | Waiting for Utility Hatch open signal...",
                                                                                                                                                                                formatElapsed(elapsedRuntime(now))
                                                                                                                                                                              ))

                                                                                                                                                                              nextPrint = nextPrint + 1
                                                                                                                                                                              end

                                                                                                                                                                              os.sleep(0.1)
                                                                                                                                                                              end

                                                                                                                                                                              state.holeStart = computer.uptime()
                                                                                                                                                                              state.stability = 100
                                                                                                                                                                              state.stabilityTime = state.holeStart
                                                                                                                                                                              state.spacetimeOn = false
                                                                                                                                                                              state.spacetimeOnAt = nil
                                                                                                                                                                              state.lastTank = getTankAmount()
                                                                                                                                                                              state.lastActualStability = nil
                                                                                                                                                                              state.lastActualTime = nil
                                                                                                                                                                              state.actualSeen = false
                                                                                                                                                                              state.fallbackLossStart = nil
                                                                                                                                                                              state.fallbackLossStability = nil
                                                                                                                                                                              state.expectedClosing = false
                                                                                                                                                                              state.emergencyClosing = false
                                                                                                                                                                              state.idleSince = nil

                                                                                                                                                                              print(
                                                                                                                                                                                "BHC: Utility hatch confirms Black Hole is open!"
                                                                                                                                                                              )

                                                                                                                                                                              if debugShowStatusEverySecond then
                                                                                                                                                                                printStatus(sampleStatus())
                                                                                                                                                                                end
                                                                                                                                                                                end

                                                                                                                                                                                local function runCycle()
                                                                                                                                                                                local available, tankDetails, readableStockers =
                                                                                                                                                                                getTankInformation()

                                                                                                                                                                                local remaining, needed = calculateSpacetime(
                                                                                                                                                                                  maxRuntime,
                                                                                                                                                                                  available
                                                                                                                                                                                )

                                                                                                                                                                                print("")
                                                                                                                                                                                print(
                                                                                                                                                                                  "BHC: ST stockers: "
                                                                                                                                                                                  .. table.concat(tankDetails, " | ")
                                                                                                                                                                                )

                                                                                                                                                                                if readableStockers == 0 then
                                                                                                                                                                                  print(
                                                                                                                                                                                    "BHC ERROR: No configured ST stocker could be read by the transposer."
                                                                                                                                                                                  )

                                                                                                                                                                                  return
                                                                                                                                                                                  end

                                                                                                                                                                                  if remaining < 0 then
                                                                                                                                                                                    print(
                                                                                                                                                                                      "BHC: Missing "
                                                                                                                                                                                      .. numberText(-remaining)
                                                                                                                                                                                      .. " L ST!"
                                                                                                                                                                                    )

                                                                                                                                                                                    print(
                                                                                                                                                                                      "BHC: Required "
                                                                                                                                                                                      .. numberText(needed)
                                                                                                                                                                                      .. " L | Available "
                                                                                                                                                                                      .. numberText(available)
                                                                                                                                                                                      .. " L"
                                                                                                                                                                                    )

                                                                                                                                                                                    return
                                                                                                                                                                                    end

                                                                                                                                                                                    print(
                                                                                                                                                                                      "BHC: Target "
                                                                                                                                                                                      .. numberText(maxRuntime)
                                                                                                                                                                                      .. "s with "
                                                                                                                                                                                      .. numberText(needed)
                                                                                                                                                                                      .. " L ST!"
                                                                                                                                                                                    )

                                                                                                                                                                                    print(
                                                                                                                                                                                      "BHC: Available ST: "
                                                                                                                                                                                      .. numberText(available)
                                                                                                                                                                                      .. " L"
                                                                                                                                                                                    )

                                                                                                                                                                                    print(string.format(
                                                                                                                                                                                      "BHC: Emergency close threshold: %.1f%% STAB.",
                                                                                                                                                                                      emergencyCloseStability
                                                                                                                                                                                    ))

                                                                                                                                                                                    if closeWhenIdle and useCollapser then
                                                                                                                                                                                      print(string.format(
                                                                                                                                                                                        "BHC: Idle close after %.1fs idle, never before %.1fs after seed insertion.",
                                                                                                                                                                                        math.max(0, tonumber(idleCloseSeconds) or 0),
                                                                                                                                                                                                          math.max(0, tonumber(minimumRuntimeBeforeIdleClose) or 0)
                                                                                                                                                                                      ))
                                                                                                                                                                                      end

                                                                                                                                                                                      print("BHC: Opening Black Hole!")
                                                                                                                                                                                      enableController(true)

                                                                                                                                                                                      local moved = transposer.transferItem(
                                                                                                                                                                                        interfaceSide,
                                                                                                                                                                                        busSide,
                                                                                                                                                                                        1,
                                                                                                                                                                                        1
                                                                                                                                                                                      )

                                                                                                                                                                                      if not moved or moved == 0 then
                                                                                                                                                                                        print(
                                                                                                                                                                                          "BHC ERROR: Failed to transfer Black Hole Seed!"
                                                                                                                                                                                        )

                                                                                                                                                                                        return
                                                                                                                                                                                        end

                                                                                                                                                                                        state.seedInsertedAt = computer.uptime()
                                                                                                                                                                                        waitForHoleOpen()

                                                                                                                                                                                        if maxRuntime > 100 then
                                                                                                                                                                                          if not statusSleep(
                                                                                                                                                                                            math.max(100 - targetStability, 0)
                                                                                                                                                                                          ) then
                                                                                                                                                                                          return
                                                                                                                                                                                          end

                                                                                                                                                                                          if not holeStillOpen() then
                                                                                                                                                                                            return
                                                                                                                                                                                            end

                                                                                                                                                                                            local beforeInjection = sampleStatus()

                                                                                                                                                                                            if not checkEmergency(beforeInjection) then
                                                                                                                                                                                              return
                                                                                                                                                                                              end

                                                                                                                                                                                              print(string.format(
                                                                                                                                                                                                "BHC: Injecting ST at approximately %.1f%% STAB!",
                                                                                                                                                                                                beforeInjection.stability or targetStability
                                                                                                                                                                                              ))

                                                                                                                                                                                              enableSpacetime()

                                                                                                                                                                                              local afterInjection = sampleStatus()

                                                                                                                                                                                              if debugShowStatusEverySecond then
                                                                                                                                                                                                printStatus(afterInjection)
                                                                                                                                                                                                end

                                                                                                                                                                                                if not checkEmergency(afterInjection) then
                                                                                                                                                                                                  return
                                                                                                                                                                                                  end

                                                                                                                                                                                                  if not checkIdleClose(afterInjection) then
                                                                                                                                                                                                    return
                                                                                                                                                                                                    end

                                                                                                                                                                                                    if not statusSleep(
                                                                                                                                                                                                      math.max(maxRuntime - 100, 0)
                                                                                                                                                                                                    ) then
                                                                                                                                                                                                    return
                                                                                                                                                                                                    end

                                                                                                                                                                                                    if not holeStillOpen() then
                                                                                                                                                                                                      return
                                                                                                                                                                                                      end

                                                                                                                                                                                                      local shutdownSample = sampleStatus()

                                                                                                                                                                                                      if not checkEmergency(shutdownSample) then
                                                                                                                                                                                                        return
                                                                                                                                                                                                        end

                                                                                                                                                                                                        if voidProtection and isRecipeActive() then
                                                                                                                                                                                                          local maxProgress = bhc.getWorkMaxProgress() or 0
                                                                                                                                                                                                          local progress = bhc.getWorkProgress() or 0
                                                                                                                                                                                                          local timeNeeded = (maxProgress - progress) / 20
                                                                                                                                                                                                          local stability = shutdownSample.stability or targetStability
                                                                                                                                                                                                          local extra = math.max(timeNeeded - stability + 1, 0)

                                                                                                                                                                                                          if extra > 0 then
                                                                                                                                                                                                            print(string.format(
                                                                                                                                                                                                              "BHC: Void protection waiting %.1f additional seconds.",
                                                                                                                                                                                                              extra
                                                                                                                                                                                                            ))

                                                                                                                                                                                                            if not statusSleep(extra) then
                                                                                                                                                                                                              return
                                                                                                                                                                                                              end
                                                                                                                                                                                                              else
                                                                                                                                                                                                                print(
                                                                                                                                                                                                                  "BHC: Current recipe does not require additional protection time."
                                                                                                                                                                                                                )
                                                                                                                                                                                                                end
                                                                                                                                                                                                                elseif voidProtection then
                                                                                                                                                                                                                  print(
                                                                                                                                                                                                                    "BHC: No recipe active at shutdown; no protection wait needed."
                                                                                                                                                                                                                  )
                                                                                                                                                                                                                  end
                                                                                                                                                                                                                  else
                                                                                                                                                                                                                    if not statusSleep(60) then
                                                                                                                                                                                                                      return
                                                                                                                                                                                                                      end

                                                                                                                                                                                                                      if isRecipeActive() then
                                                                                                                                                                                                                        local maxProgress = bhc.getWorkMaxProgress() or 0
                                                                                                                                                                                                                        local progress = bhc.getWorkProgress() or 0
                                                                                                                                                                                                                        local recipeSeconds = math.max(1, maxProgress / 20)
                                                                                                                                                                                                                        local timeRemaining = 40 - (maxProgress - progress) / 20
                                                                                                                                                                                                                        local waitTime = math.floor(
                                                                                                                                                                                                                          timeRemaining / recipeSeconds
                                                                                                                                                                                                                        ) * recipeSeconds - 1

                                                                                                                                                                                                                        if not statusSleep(math.max(waitTime, 0)) then
                                                                                                                                                                                                                          return
                                                                                                                                                                                                                          end
                                                                                                                                                                                                                          end
                                                                                                                                                                                                                          end

                                                                                                                                                                                                                          if not holeStillOpen() then
                                                                                                                                                                                                                            return
                                                                                                                                                                                                                            end

                                                                                                                                                                                                                            normalClose()
                                                                                                                                                                                                                            end

                                                                                                                                                                                                                            -- ======================= SLEEP MODE =======================

                                                                                                                                                                                                                            local function printSleepMessage()
                                                                                                                                                                                                                            if #sleepMessages == 0 then
                                                                                                                                                                                                                              print("BHC: Sleeping...")
                                                                                                                                                                                                                              return
                                                                                                                                                                                                                              end

                                                                                                                                                                                                                              local index = math.random(1, #sleepMessages)

                                                                                                                                                                                                                              while #sleepMessages > 1
                                                                                                                                                                                                                                and index == state.lastSleepMessage do

                                                                                                                                                                                                                                index = math.random(1, #sleepMessages)
                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                state.lastSleepMessage = index
                                                                                                                                                                                                                                print(sleepMessages[index])
                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                local function sleepUntilRequested()
                                                                                                                                                                                                                                printSleepMessage()

                                                                                                                                                                                                                                local nextMessage = computer.uptime()
                                                                                                                                                                                                                                + sleepMessageInterval

                                                                                                                                                                                                                                while redstone.getInput(receiverSide) <= 0 do
                                                                                                                                                                                                                                  if computer.uptime() >= nextMessage then
                                                                                                                                                                                                                                    printSleepMessage()
                                                                                                                                                                                                                                    nextMessage = computer.uptime()
                                                                                                                                                                                                                                    + sleepMessageInterval
                                                                                                                                                                                                                                    end

                                                                                                                                                                                                                                    os.sleep(1)
                                                                                                                                                                                                                                    end
                                                                                                                                                                                                                                    end

                                                                                                                                                                                                                                    -- ======================== STARTUP =========================

                                                                                                                                                                                                                                    math.randomseed(math.floor(computer.uptime() * 1000))
                                                                                                                                                                                                                                    math.random()
                                                                                                                                                                                                                                    math.random()
                                                                                                                                                                                                                                    math.random()

                                                                                                                                                                                                                                    redstone.setOutput(transmitterSide, 0)
                                                                                                                                                                                                                                    enableController(true)
                                                                                                                                                                                                                                    resetState()

                                                                                                                                                                                                                                    if closeWhenIdle then
                                                                                                                                                                                                                                      if useCollapser then
                                                                                                                                                                                                                                        print(string.format(
                                                                                                                                                                                                                                          "BHC: Early idle close enabled after %.1f seconds without a recipe, but never before %.1f seconds after seed insertion.",
                                                                                                                                                                                                                                          math.max(0, tonumber(idleCloseSeconds) or 0),
                                                                                                                                                                                                                                                            math.max(0, tonumber(minimumRuntimeBeforeIdleClose) or 0)
                                                                                                                                                                                                                                        ))
                                                                                                                                                                                                                                        else
                                                                                                                                                                                                                                          print(
                                                                                                                                                                                                                                            "BHC WARNING: Idle close is enabled, but useCollapser is false."
                                                                                                                                                                                                                                          )
                                                                                                                                                                                                                                          end
                                                                                                                                                                                                                                          end

                                                                                                                                                                                                                                          while true do
                                                                                                                                                                                                                                            if redstone.getInput(receiverSide) > 0 then
                                                                                                                                                                                                                                              if transposer.getStackInSlot(interfaceSide, 1) == nil then
                                                                                                                                                                                                                                                print("BHC: No Seeds Available!")
                                                                                                                                                                                                                                                elseif useCollapser
                                                                                                                                                                                                                                                  and transposer.getStackInSlot(interfaceSide, 2) == nil then
                                                                                                                                                                                                                                                  print("BHC: No Collapsers Available!")
                                                                                                                                                                                                                                                  else
                                                                                                                                                                                                                                                    runCycle()
                                                                                                                                                                                                                                                    end

                                                                                                                                                                                                                                                    os.sleep(3)
                                                                                                                                                                                                                                                    else
                                                                                                                                                                                                                                                      sleepUntilRequested()
                                                                                                                                                                                                                                                      end
                                                                                                                                                                                                                                                      end
