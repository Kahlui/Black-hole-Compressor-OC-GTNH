-- Read the config closely. Written by Kahlui/Zach with help from GPT 5.6 for GTNH 2.9 Beta 1
-- bhc_011: fast two-stocker >1G Spacetime bypass

local component = require("component")
local sides = require("sides")
local computer = require("computer")
local term = require("term")

local unicodeOK, unicode = pcall(require, "unicode")
if not unicodeOK then
  unicode = {
    len = string.len,
    sub = string.sub
  }
  end

  local bhc = component.gt_machine
  local redstone = component.redstone
  local transposer = component.transposer
  local gpu = component.gpu

  -- CTRL+ALT+C to stop the script.

  -- ========================= CONFIG =========================

  local maxRuntime = 100
  local targetStability = 18
  local emergencyCloseStability = 10
  local manualCloseConfirmSeconds = 5

  -- How often the QUOTES panel changes, whether idle or actively running.
  local sleepMessageInterval = 15

  -- Emergency fallback: disable the controller for 15.1 minutes, then briefly
  -- re-enable it so the Utility Hatch can update and confirm closure.
  local emergencyControllerOffSeconds = 15.1 * 60
  local emergencyControllerVerifyDelaySeconds = 1
  local collapserInsertTimeoutSeconds = 5

  local closeWhenIdle = true
  local idleCloseSeconds = 10
  local minimumRuntimeBeforeIdleClose = 100

  local useCollapser = true
  local voidProtection = true

  -- Keep this true so the program continually refreshes status output.
  local debugShowStatusEverySecond = true

  -- Dashboard settings. The control logic continues in console mode if the UI fails.
  local uiEnabled = true
  local uiUseMaximumResolution = true
  local uiMaxStoredLogLines = 40
  local uiRefreshInterval = 0.25
  local flowRefreshInterval = 1

  -- The stocker API only exposes the first/clamped fluid amount. When both
  -- configured stockers report more than this amount, trust the refill setup
  -- and allow the Black Hole to open even if the calculated total looks short.
  local minimumPerStockerToForceStart = 1000000000

  -- Side Options: north, south, east, west, up, down
  local receiverSide = sides.north
  local transmitterSide = sides.south
  local hatchSide = sides.down
  local interfaceSide = sides.south
  local busSide = sides.down

  -- Every Spacetime stocker touching the transposer.
  -- Each entry is read separately and then added together.
  local stockers = {
    {name = "UP", side = sides.up},
    {name = "WEST", side = sides.west}
  }

  -- ======================= END CONFIG =======================

  local C = {
    bg = 0x111318,
    panel = 0x1B1F2A,
    panel2 = 0x242A38,
    border = 0x3A4256,
    text = 0xE6ECF2,
    dim = 0x9AA7B5,
    good = 0x58D68D,
    warn = 0xF5B041,
    bad = 0xEC7063,
    accent = 0x5DADE2,
    accent2 = 0xAF7AC5,
    white = 0xFFFFFF
  }

  local ui = nil

  local function automaticLogColor(message)
  local lower = tostring(message or ""):lower()

  if lower:find("critical", 1, true)
    or lower:find("emergency", 1, true)
    or lower:find("error", 1, true) then
    return C.bad
    end

    if lower:find("warning", 1, true)
      or lower:find("missing", 1, true)
      or lower:find("no seeds", 1, true)
      or lower:find("no collapsers", 1, true)
      or lower:find("failed", 1, true) then
      return C.warn
      end

      if lower:find("enabled", 1, true)
        or lower:find("confirms", 1, true)
        or lower:find("inserted", 1, true)
        or lower:find("complete", 1, true) then
        return C.good
        end

        return C.text
        end

        local function emit(message, color)
        message = tostring(message or "")

        if message == "" then
          return
          end

          color = color or automaticLogColor(message)

          if ui and ui.ready then
            ui.log(message, color)
            else
              print(message)
              end
              end

              local state = {
                phase = "STANDBY",
                seedInsertedAt = nil,
                holeStart = nil,
                stability = 100,
                stabilityTime = nil,
                spacetimeOn = false,
                spacetimeOnAt = nil,
                lastTank = nil,
                flowLastTank = nil,
                flowLastAt = nil,
                flowDelta = nil,
                flowDisplay = "OFF",
                lastActualStability = nil,
                lastActualTime = nil,
                actualSeen = false,
                fallbackLossStart = nil,
                fallbackLossStability = nil,
                expectedClosing = false,
                emergencyClosing = false,
                emergencyFallbackStartedAt = nil,
                emergencyFallbackDeadline = nil,
                emergencyFallbackCycle = 0,
                emergencyReason = nil,
                controllerForcedOff = false,
                externalTakeover = false,
                largeStockerBypassLogged = false,
                idleSince = nil,
                lastSleepMessage = nil
              }

              -- Quotes shown in the QUOTES panel during every operating state.
              local sleepMessages = {
                "BHC: Sleeping... dreaming of stable spacetime.",
                "BHC: No seeds detected. Reality remains disappointingly intact.",
                "BHC: Waiting for someone to manufacture another expensive mistake.",
                "BHC: The Black Hole is currently on a union-mandated break.",
                "BHC: Idle. EU-network destruction has been postponed.",
                "BHC: Greg reviewed the setup and found it insufficiently complicated.",
                "BHC: Spacetime conserved. The power grid may relax temporarily.",
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
                "BHC: The machine is resting. The recipe tree is merely gathering strength.",

                -- Kahlui
                "BHC: Kahlui finished upgrading the infrastructure. Somehow, there is even less power now.",
                "BHC: Kahlui says he is not stealing the power; he is reallocating it toward larger infrastructure.",
                "BHC: Power shortage detected. Kahlui has probably built another machine that consumes several suns.",
                "BHC: Kahlui upgraded the cables so he could steal the power more efficiently.",
                "BHC: Kahlui promised the new infrastructure would solve the power problem. It created three new ones.",
                "BHC: The grid had spare capacity for almost four seconds before Kahlui noticed.",
                "BHC: Kahlui has confirmed the infrastructure is future-proof until his next project starts.",
                "BHC: Every time the power grid catches up, Kahlui increases the infrastructure requirements.",
                "BHC: Kahlui is not draining the grid. The grid simply lacks the ambition to keep up.",
                "BHC: Infrastructure report: Kahlui found unused power and corrected the oversight.",

                -- Superfrogman98
                "BHC: Superfrogman98 says bees are frogs. No supporting evidence has survived review.",
                "BHC: Superfrogman98 insists bees are frogs with wings. Biology has filed a complaint.",
                "BHC: Superfrogman98 identified another bee as a frog. The bee declined to comment.",
                "BHC: According to Superfrogman98, honey is simply frog syrup.",
                "BHC: Superfrogman98 says buzzing is just advanced croaking.",
                "BHC: Superfrogman98 has classified the apiary as a very small frog pond.",
                "BHC: A bee flew past. Superfrogman98 immediately called it an airborne frog.",
                "BHC: Superfrogman98 remains certain that bees are frogs. Reality remains unconvinced.",
                "BHC: Superfrogman98 claims the wings are merely a frog mobility upgrade.",
                "BHC: Scientific consensus says bee. Superfrogman98 says frog. The argument continues.",

                -- Craftspirit_MC
                "BHC: Craftspirit_MC finished expanding power generation. Kahlui immediately expanded everything else.",
                "BHC: Craftspirit_MC added more power. Kahlui interpreted this as permission to scale the infrastructure again.",
                "BHC: Craftspirit_MC cannot catch a break because Kahlui keeps catching every spare amp first.",
                "BHC: The grid was finally stable until Kahlui told Craftspirit_MC about the next infrastructure upgrade.",
                "BHC: Craftspirit_MC built enough power for the factory. Kahlui then built enough factory for twice that power.",
                "BHC: Craftspirit_MC has requested one day without Kahlui scaling the infrastructure. Request denied.",
                "BHC: Craftspirit_MC increased generation by ten percent. Kahlui increased demand by eleven.",
                "BHC: Craftspirit_MC keeps building power plants while Kahlui keeps discovering new ways to consume them.",
                "BHC: Craftspirit_MC almost caught up with demand, so Kahlui added another processing wing.",
                "BHC: Power generation belongs to Craftspirit_MC. Power consumption belongs almost entirely to Kahlui.",

                -- LifeBeat
                "LifeBeat Spams Skill Issue,Occasionally effective",
                "Skill issue is Issued,repealed with \"Used UEV Super\"",
                "LifeBeat:Deep Dark Black Hole Initiated",
                "It Started! Statement: Cool Beans!",
                "Machine Failed |\"You Killed Me,You Monster\"",
                "Intruder Detected |\"Oh Its You\"",
                "Recipe Failure \"The Stargate is a lie\"",
                "Insuffecient Power \"Shutting Down....\"",
                "LifeBeat Says \"Hello There\" said count exceeds limits"
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

              local function formatDurationWords(seconds)
              seconds = math.max(0, math.floor(tonumber(seconds) or 0))

              local hours = math.floor(seconds / 3600)
              local minutes = math.floor((seconds % 3600) / 60)
              local remainingSeconds = seconds % 60
              local parts = {}

              if hours > 0 then
                parts[#parts + 1] = tostring(hours) .. "h"
                end

                if minutes > 0 or hours > 0 then
                  parts[#parts + 1] = tostring(minutes) .. "m"
                  end

                  parts[#parts + 1] = tostring(remainingSeconds) .. "s"
                  return table.concat(parts, " ")
                  end

                  local function stabilitySourceText(source)
                  if source == "ACT" then
                    return "Actual"
                    end

                    if source == "EST" then
                      return "Estimated"
                      end

                      return tostring(source or "Unknown")
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

                          -- Void protection must always have enough Spacetime to extend the Black
                          -- Hole past the free 100-second window. When a recipe is active, project the
                          -- extra runtime needed to finish it and show that live requirement in the UI.
                          local function getProjectedRuntime(sample)
                          local projectedRuntime = maxRuntime

                          if voidProtection then
                            projectedRuntime = math.max(projectedRuntime, 101)
                            end

                            if voidProtection and sample and sample.recipeActive then
                              local remainingRecipeSeconds = math.max(
                                0,
                                ((sample.maximum or 0) - (sample.progress or 0)) / 20
                              )

                              local availableStability = sample.stability or targetStability
                              local protectionSeconds = math.max(
                                remainingRecipeSeconds - availableStability + 1,
                                0
                              )

                              projectedRuntime = math.max(
                                projectedRuntime,
                                100 + math.ceil(protectionSeconds)
                              )
                              end

                              return math.max(0, math.ceil(projectedRuntime))
                              end

                              local function getSpacetimeRequirement(available, sample)
                              local projectedRuntime = getProjectedRuntime(sample)
                              local remaining, needed = calculateSpacetime(
                                projectedRuntime,
                                available
                              )

                              return remaining, needed, projectedRuntime
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
                                  local amounts = {}

                                  for _, stocker in ipairs(stockers) do
                                    local amount, wasReadable = readStocker(stocker)

                                    amounts[#amounts + 1] = amount
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

                                      return total, details, readable, amounts
                                      end

                                      local function bothStockersOverMinimum(stockerAmounts, readable)
                                      local minimum = tonumber(minimumPerStockerToForceStart) or 1000000000

                                      if (tonumber(readable) or 0) < 2
                                        or type(stockerAmounts) ~= "table"
                                        or #stockerAmounts < 2 then
                                        return false
                                        end

                                        return (tonumber(stockerAmounts[1]) or 0) > minimum
                                        and (tonumber(stockerAmounts[2]) or 0) > minimum
                                        end

                                        local function acceptSpacetimeReserve(remaining, stockerAmounts, readable)
                                        local bypass = (tonumber(remaining) or 0) < 0
                                        and bothStockersOverMinimum(stockerAmounts, readable)

                                        return (tonumber(remaining) or 0) >= 0 or bypass, bypass
                                        end

                                        local function noteLargeStockerBypass(needed, stockerAmounts)
                                        if state.largeStockerBypassLogged then
                                          return
                                          end

                                          state.largeStockerBypassLogged = true
                                          emit(string.format(
                                            "BHC WARNING: Calculated Spacetime requirement is %s L, but both stockers report over %s L (%s L / %s L). Trusting the refill setup and proceeding.",
                                                             numberText(needed),
                                                             numberText(minimumPerStockerToForceStart),
                                                             numberText(stockerAmounts and stockerAmounts[1] or 0),
                                                             numberText(stockerAmounts and stockerAmounts[2] or 0)
                                          ), C.warn)
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
                                              emit(
                                                "BHC WARNING: Could not enable controller: "
                                                .. cleanText(result)
                                              )
                                              end

                                              return ok
                                              end

                                              local function disableController(showError)
                                              local ok, result = pcall(
                                                bhc.setWorkAllowed,
                                                false
                                              )

                                              if not ok and showError then
                                                emit(
                                                  "BHC CRITICAL: Could not disable controller: "
                                                  .. cleanText(result),
                                                     C.bad
                                                )
                                                end

                                                return ok
                                                end

                                                local function resetState()
                                                local previousSleepMessage = state.lastSleepMessage

                                                state.phase = "STANDBY"
                                                state.seedInsertedAt = nil
                                                state.holeStart = nil
                                                state.stability = 100
                                                state.stabilityTime = nil
                                                state.spacetimeOn = false
                                                state.spacetimeOnAt = nil
                                                state.lastTank = nil
                                                state.flowLastTank = nil
                                                state.flowLastAt = nil
                                                state.flowDelta = nil
                                                state.flowDisplay = "OFF"
                                                state.lastActualStability = nil
                                                state.lastActualTime = nil
                                                state.actualSeen = false
                                                state.fallbackLossStart = nil
                                                state.fallbackLossStability = nil
                                                state.expectedClosing = false
                                                state.emergencyClosing = false
                                                state.emergencyFallbackStartedAt = nil
                                                state.emergencyFallbackDeadline = nil
                                                state.emergencyFallbackCycle = 0
                                                state.emergencyReason = nil
                                                state.controllerForcedOff = false
                                                state.externalTakeover = false
                                                state.largeStockerBypassLogged = false
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
                                                                                                              local progressOK, progress = pcall(bhc.getWorkProgress)
                                                                                                              local maximumOK, maximum = pcall(bhc.getWorkMaxProgress)

                                                                                                              progress = progressOK and tonumber(progress) or 0
                                                                                                              maximum = maximumOK and tonumber(maximum) or 0

                                                                                                              local percent = 0

                                                                                                              if maximum > 0 then
                                                                                                                percent = progress / maximum * 100
                                                                                                                end

                                                                                                                return progress, maximum, percent
                                                                                                                end

                                                                                                                local function updateFlowReading(now, tank)
                                                                                                                local interval = math.max(0.1, tonumber(flowRefreshInterval) or 1)

                                                                                                                if not state.spacetimeOn then
                                                                                                                  state.flowLastTank = tank
                                                                                                                  state.flowLastAt = now
                                                                                                                  state.flowDelta = nil
                                                                                                                  state.flowDisplay = "OFF"
                                                                                                                  return nil, state.flowDisplay
                                                                                                                  end

                                                                                                                  if state.flowLastTank == nil or state.flowLastAt == nil then
                                                                                                                    state.flowLastTank = tank
                                                                                                                    state.flowLastAt = now
                                                                                                                    state.flowDelta = nil
                                                                                                                    state.flowDisplay = "ENABLED - WAITING FOR FLOW SAMPLE"
                                                                                                                    return nil, state.flowDisplay
                                                                                                                    end

                                                                                                                    if now - state.flowLastAt >= interval then
                                                                                                                      local elapsed = math.max(now - state.flowLastAt, 0.001)
                                                                                                                      local delta = state.flowLastTank - tank
                                                                                                                      local rate = delta / elapsed

                                                                                                                      state.flowLastTank = tank
                                                                                                                      state.flowLastAt = now
                                                                                                                      state.flowDelta = delta

                                                                                                                      if delta > 0 then
                                                                                                                        state.flowDisplay = "FLOWING "
                                                                                                                        .. numberText(math.max(1, math.floor(rate + 0.5)))
                                                                                                                        .. " L/s"
                                                                                                                        elseif delta < 0 then
                                                                                                                          state.flowDisplay = "REFILLING +"
                                                                                                                          .. numberText(math.max(1, math.floor(-rate + 0.5)))
                                                                                                                          .. " L/s"
                                                                                                                          else
                                                                                                                            state.flowDisplay = "ENABLED - NO TANK CHANGE"
                                                                                                                            end
                                                                                                                            end

                                                                                                                            return state.flowDelta, state.flowDisplay
                                                                                                                            end

                                                                                                                            local function sampleStatus()
                                                                                                                            local now = computer.uptime()
                                                                                                                            local tank = getTankAmount()
                                                                                                                            local tx = getTX()
                                                                                                                            local tankDelta, flowDisplay = updateFlowReading(now, tank)

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
                                                                                                                                  flowDisplay = flowDisplay,
                                                                                                                                  tx = tx,
                                                                                                                                  stability = stability,
                                                                                                                                  stabilityType = stabilityType
                                                                                                                                }
                                                                                                                                end

                                                                                                                                local function flowText(sample)
                                                                                                                                if sample and sample.flowDisplay then
                                                                                                                                  return sample.flowDisplay
                                                                                                                                  end

                                                                                                                                  return state.flowDisplay or "OFF"
                                                                                                                                  end

                                                                                                                                  -- ============================ UI ============================

                                                                                                                                  ui = {
                                                                                                                                    ready = false,
                                                                                                                                    w = 0,
                                                                                                                                    h = 0,
                                                                                                                                    logLines = {},
                                                                                                                                    lastSample = nil,
                                                                                                                                    lastSleepText = "Waiting for request signal.",
                                                                                                                                    quoteNextAt = 0,
                                                                                                                                    lastEventText = "Dashboard initialized.",
                                                                                                                                    drawErrorShown = false,
                                                                                                                                    buffer = nil,
                                                                                                                                    usingBuffer = false,
                                                                                                                                    firstDraw = true,
                                                                                                                                    lastLayout = nil
                                                                                                                                  }

                                                                                                                                  local function quoteIntervalSeconds()
                                                                                                                                  return math.max(1, tonumber(sleepMessageInterval) or 15)
                                                                                                                                  end

                                                                                                                                  local function rotateQuoteIfDue(now, force)
                                                                                                                                  now = now or computer.uptime()

                                                                                                                                  if not force
                                                                                                                                    and ui.lastSleepText
                                                                                                                                    and ui.lastSleepText ~= ""
                                                                                                                                    and now < (ui.quoteNextAt or 0) then

                                                                                                                                    return false
                                                                                                                                    end

                                                                                                                                    local message

                                                                                                                                    if #sleepMessages == 0 then
                                                                                                                                      message = "BHC: No quotes configured."
                                                                                                                                      else
                                                                                                                                        local index = math.random(1, #sleepMessages)

                                                                                                                                        while #sleepMessages > 1
                                                                                                                                          and index == state.lastSleepMessage do
                                                                                                                                          index = math.random(1, #sleepMessages)
                                                                                                                                          end

                                                                                                                                          state.lastSleepMessage = index
                                                                                                                                          message = sleepMessages[index]
                                                                                                                                          end

                                                                                                                                          ui.lastSleepText = tostring(message or "")
                                                                                                                                          ui.quoteNextAt = now + quoteIntervalSeconds()
                                                                                                                                          return true
                                                                                                                                          end

                                                                                                                                          local function clamp(value, minimum, maximum)
                                                                                                                                          if value < minimum then
                                                                                                                                            return minimum
                                                                                                                                            end

                                                                                                                                            if value > maximum then
                                                                                                                                              return maximum
                                                                                                                                              end

                                                                                                                                              return value
                                                                                                                                              end

                                                                                                                                              local function ulen(value)
                                                                                                                                              local ok, length = pcall(unicode.len, tostring(value or ""))
                                                                                                                                              return ok and length or #tostring(value or "")
                                                                                                                                              end

                                                                                                                                              local function usub(value, first, last)
                                                                                                                                              local textValue = tostring(value or "")
                                                                                                                                              local ok, result = pcall(unicode.sub, textValue, first, last)
                                                                                                                                              return ok and result or textValue:sub(first, last)
                                                                                                                                              end

                                                                                                                                              local function clipped(value, width)
                                                                                                                                              width = math.max(0, math.floor(tonumber(width) or 0))
                                                                                                                                              local textValue = tostring(value or "")

                                                                                                                                              if width <= 0 then
                                                                                                                                                return ""
                                                                                                                                                end

                                                                                                                                                if ulen(textValue) <= width then
                                                                                                                                                  return textValue
                                                                                                                                                  end

                                                                                                                                                  if width <= 3 then
                                                                                                                                                    return usub(textValue, 1, width)
                                                                                                                                                    end

                                                                                                                                                    return usub(textValue, 1, width - 3) .. "..."
                                                                                                                                                    end

                                                                                                                                                    local function padRight(value, width)
                                                                                                                                                    local result = clipped(value, width)
                                                                                                                                                    return result .. string.rep(" ", math.max(0, width - ulen(result)))
                                                                                                                                                    end

                                                                                                                                                    local function centerText(value, width)
                                                                                                                                                    local result = clipped(value, width)
                                                                                                                                                    local remaining = math.max(0, width - ulen(result))
                                                                                                                                                    local left = math.floor(remaining / 2)
                                                                                                                                                    return string.rep(" ", left)
                                                                                                                                                    .. result
                                                                                                                                                    .. string.rep(" ", remaining - left)
                                                                                                                                                    end

                                                                                                                                                    local function wrapText(value, width, maxLines)
                                                                                                                                                    width = math.max(1, math.floor(tonumber(width) or 1))
                                                                                                                                                    maxLines = math.max(1, math.floor(tonumber(maxLines) or 1))

                                                                                                                                                    local words = {}
                                                                                                                                                    for word in tostring(value or ""):gmatch("%S+") do
                                                                                                                                                      words[#words + 1] = word
                                                                                                                                                      end

                                                                                                                                                      local lines = {}
                                                                                                                                                      local current = ""

                                                                                                                                                      for _, word in ipairs(words) do
                                                                                                                                                        local candidate = current == "" and word or current .. " " .. word

                                                                                                                                                        if ulen(candidate) <= width then
                                                                                                                                                          current = candidate
                                                                                                                                                          else
                                                                                                                                                            if current ~= "" then
                                                                                                                                                              lines[#lines + 1] = clipped(current, width)
                                                                                                                                                              end

                                                                                                                                                              current = clipped(word, width)

                                                                                                                                                              if #lines >= maxLines then
                                                                                                                                                                break
                                                                                                                                                                end
                                                                                                                                                                end
                                                                                                                                                                end

                                                                                                                                                                if #lines < maxLines and current ~= "" then
                                                                                                                                                                  lines[#lines + 1] = clipped(current, width)
                                                                                                                                                                  end

                                                                                                                                                                  if #lines == 0 then
                                                                                                                                                                    lines[1] = ""
                                                                                                                                                                    end

                                                                                                                                                                    return lines
                                                                                                                                                                    end

                                                                                                                                                                    local function setColors(foreground, background)
                                                                                                                                                                    if foreground then
                                                                                                                                                                      pcall(gpu.setForeground, foreground)
                                                                                                                                                                      end

                                                                                                                                                                      if background then
                                                                                                                                                                        pcall(gpu.setBackground, background)
                                                                                                                                                                        end
                                                                                                                                                                        end

                                                                                                                                                                        local function fill(x, y, width, height, character, foreground, background)
                                                                                                                                                                        width = math.floor(tonumber(width) or 0)
                                                                                                                                                                        height = math.floor(tonumber(height) or 0)

                                                                                                                                                                        if width <= 0 or height <= 0 then
                                                                                                                                                                          return
                                                                                                                                                                          end

                                                                                                                                                                          setColors(foreground, background)
                                                                                                                                                                          gpu.fill(x, y, width, height, character or " ")
                                                                                                                                                                          end

                                                                                                                                                                          local function drawText(x, y, value, foreground, background, maxWidth)
                                                                                                                                                                          if x < 1 or y < 1 or x > ui.w or y > ui.h then
                                                                                                                                                                            return
                                                                                                                                                                            end

                                                                                                                                                                            local width = maxWidth or (ui.w - x + 1)
                                                                                                                                                                            width = math.min(width, ui.w - x + 1)

                                                                                                                                                                            if width <= 0 then
                                                                                                                                                                              return
                                                                                                                                                                              end

                                                                                                                                                                              setColors(foreground, background)
                                                                                                                                                                              gpu.set(x, y, clipped(value, width))
                                                                                                                                                                              end

                                                                                                                                                                              local function box(x, y, width, height, title, background, border)
                                                                                                                                                                              width = math.min(math.floor(width), ui.w - x + 1)
                                                                                                                                                                              height = math.min(math.floor(height), ui.h - y + 1)

                                                                                                                                                                              if width < 4 or height < 3 then
                                                                                                                                                                                return
                                                                                                                                                                                end

                                                                                                                                                                                background = background or C.panel
                                                                                                                                                                                border = border or C.border

                                                                                                                                                                                fill(x, y, width, height, " ", C.text, background)
                                                                                                                                                                                setColors(border, background)

                                                                                                                                                                                gpu.set(x, y, "+" .. string.rep("-", width - 2) .. "+")

                                                                                                                                                                                for yy = y + 1, y + height - 2 do
                                                                                                                                                                                  gpu.set(x, yy, "|")
                                                                                                                                                                                  gpu.set(x + width - 1, yy, "|")
                                                                                                                                                                                  end

                                                                                                                                                                                  gpu.set(x, y + height - 1, "+" .. string.rep("-", width - 2) .. "+")

                                                                                                                                                                                  if title and title ~= "" then
                                                                                                                                                                                    drawText(
                                                                                                                                                                                      x + 2,
                                                                                                                                                                                      y,
                                                                                                                                                                                      " " .. title .. " ",
                                                                                                                                                                                      C.text,
                                                                                                                                                                                      background,
                                                                                                                                                                                      width - 4
                                                                                                                                                                                    )
                                                                                                                                                                                    end
                                                                                                                                                                                    end

                                                                                                                                                                                    local function progressBar(x, y, width, ratio, color, label, background)
                                                                                                                                                                                    width = math.max(4, math.floor(tonumber(width) or 4))
                                                                                                                                                                                    ratio = clamp(tonumber(ratio) or 0, 0, 1)
                                                                                                                                                                                    background = background or C.panel

                                                                                                                                                                                    local inner = width - 2
                                                                                                                                                                                    local filledCount = math.floor(inner * ratio + 0.5)
                                                                                                                                                                                    local emptyCount = inner - filledCount

                                                                                                                                                                                    drawText(
                                                                                                                                                                                      x,
                                                                                                                                                                                      y,
                                                                                                                                                                                      "[" .. string.rep("=", filledCount) .. string.rep("-", emptyCount) .. "]",
                                                                                                                                                                                             color or C.accent,
                                                                                                                                                                                             background,
                                                                                                                                                                                             width
                                                                                                                                                                                    )

                                                                                                                                                                                    if label then
                                                                                                                                                                                      drawText(
                                                                                                                                                                                        x + 1,
                                                                                                                                                                                        y,
                                                                                                                                                                                        centerText(label, inner),
                                                                                                                                                                                               C.white,
                                                                                                                                                                                               background,
                                                                                                                                                                                               inner
                                                                                                                                                                                      )
                                                                                                                                                                                      end
                                                                                                                                                                                      end

                                                                                                                                                                                      local function logTimestamp()
                                                                                                                                                                                      local ok, result = pcall(os.date, "%H:%M:%S")

                                                                                                                                                                                      if ok and result then
                                                                                                                                                                                        return result
                                                                                                                                                                                        end

                                                                                                                                                                                        return formatElapsed(computer.uptime())
                                                                                                                                                                                        end

                                                                                                                                                                                        local function stateColor(sample)
                                                                                                                                                                                        if state.emergencyClosing or state.phase == "EMERGENCY" then
                                                                                                                                                                                          return C.bad
                                                                                                                                                                                          end

                                                                                                                                                                                          if state.expectedClosing or state.phase == "CLOSING" then
                                                                                                                                                                                            return C.warn
                                                                                                                                                                                            end

                                                                                                                                                                                            if not sample or not sample.holeOpen then
                                                                                                                                                                                              return C.dim
                                                                                                                                                                                              end

                                                                                                                                                                                              if sample.stability
                                                                                                                                                                                                and sample.stability <= emergencyCloseStability then
                                                                                                                                                                                                return C.bad
                                                                                                                                                                                                end

                                                                                                                                                                                                if sample.stability
                                                                                                                                                                                                  and sample.stability <= targetStability + 5 then
                                                                                                                                                                                                  return C.warn
                                                                                                                                                                                                  end

                                                                                                                                                                                                  return C.good
                                                                                                                                                                                                  end

                                                                                                                                                                                                  local function stateLabel(sample)
                                                                                                                                                                                                  if state.phase == "EMERGENCY_WAIT" then
                                                                                                                                                                                                    return "EMERGENCY TIMER"
                                                                                                                                                                                                    end

                                                                                                                                                                                                    if state.phase == "EMERGENCY_VERIFY" then
                                                                                                                                                                                                      return "VERIFYING CLOSURE"
                                                                                                                                                                                                      end

                                                                                                                                                                                                      if state.phase == "EXTERNAL_TAKEOVER" then
                                                                                                                                                                                                        return "EXTERNAL TAKEOVER"
                                                                                                                                                                                                        end

                                                                                                                                                                                                        if state.emergencyClosing or state.phase == "EMERGENCY" then
                                                                                                                                                                                                          return "EMERGENCY CLOSE"
                                                                                                                                                                                                          end

                                                                                                                                                                                                          if state.expectedClosing or state.phase == "CLOSING" then
                                                                                                                                                                                                            return "CLOSING"
                                                                                                                                                                                                            end

                                                                                                                                                                                                            if state.phase == "OPENING" then
                                                                                                                                                                                                              return "OPENING"
                                                                                                                                                                                                              end

                                                                                                                                                                                                              if not sample or not sample.holeOpen then
                                                                                                                                                                                                                return "STANDBY"
                                                                                                                                                                                                                end

                                                                                                                                                                                                                if sample.recipeActive then
                                                                                                                                                                                                                  return "RUNNING"
                                                                                                                                                                                                                  end

                                                                                                                                                                                                                  return "OPEN / IDLE"
                                                                                                                                                                                                                  end

                                                                                                                                                                                                                  local function emergencyStatusText(now)
                                                                                                                                                                                                                  now = now or computer.uptime()

                                                                                                                                                                                                                  if state.phase == "EMERGENCY_WAIT"
                                                                                                                                                                                                                    and state.emergencyFallbackDeadline then
                                                                                                                                                                                                                    local remaining = math.max(0, state.emergencyFallbackDeadline - now)
                                                                                                                                                                                                                    return "Emergency fallback: controller disabled. Closure verification in "
                                                                                                                                                                                                                    .. formatDurationWords(math.ceil(remaining))
                                                                                                                                                                                                                    .. "."
                                                                                                                                                                                                                    end

                                                                                                                                                                                                                    if state.phase == "EMERGENCY_VERIFY" then
                                                                                                                                                                                                                      return "Emergency fallback: controller enabled briefly to verify Utility Hatch closure."
                                                                                                                                                                                                                      end

                                                                                                                                                                                                                      return nil
                                                                                                                                                                                                                      end

                                                                                                                                                                                                                      local function quotePanelText(fallbackText)
                                                                                                                                                                                                                      return ui.lastSleepText
                                                                                                                                                                                                                      or fallbackText
                                                                                                                                                                                                                      or "No quote currently available."
                                                                                                                                                                                                                      end

                                                                                                                                                                                                                      local function drawLogs(x, y, width, height)
                                                                                                                                                                                                                      box(x, y, width, height, "EVENT LOG", C.panel, C.border)

                                                                                                                                                                                                                      local capacity = math.max(0, height - 2)
                                                                                                                                                                                                                      local first = math.max(1, #ui.logLines - capacity + 1)
                                                                                                                                                                                                                      local lineY = y + 1

                                                                                                                                                                                                                      for index = first, #ui.logLines do
                                                                                                                                                                                                                        local line = ui.logLines[index]

                                                                                                                                                                                                                        drawText(
                                                                                                                                                                                                                          x + 2,
                                                                                                                                                                                                                          lineY,
                                                                                                                                                                                                                          "[" .. line.time .. "] " .. line.message,
                                                                                                                                                                                                                          line.color,
                                                                                                                                                                                                                          C.panel,
                                                                                                                                                                                                                          width - 4
                                                                                                                                                                                                                        )

                                                                                                                                                                                                                        lineY = lineY + 1

                                                                                                                                                                                                                        if lineY >= y + height - 1 then
                                                                                                                                                                                                                          break
                                                                                                                                                                                                                          end
                                                                                                                                                                                                                          end
                                                                                                                                                                                                                          end

                                                                                                                                                                                                                          local function drawQuotesBox(x, y, width, height, quoteText)
                                                                                                                                                                                                                          box(x, y, width, height, "QUOTES", C.panel, C.border)

                                                                                                                                                                                                                          local lines = wrapText(
                                                                                                                                                                                                                            quoteText or "No quote currently available.",
                                                                                                                                                                                                                            math.max(1, width - 4),
                                                                                                                                                                                                                                                 math.max(1, height - 2)
                                                                                                                                                                                                                          )

                                                                                                                                                                                                                          for index, line in ipairs(lines) do
                                                                                                                                                                                                                            drawText(
                                                                                                                                                                                                                              x + 2,
                                                                                                                                                                                                                              y + index,
                                                                                                                                                                                                                              line,
                                                                                                                                                                                                                              C.dim,
                                                                                                                                                                                                                              C.panel,
                                                                                                                                                                                                                              width - 4
                                                                                                                                                                                                                            )
                                                                                                                                                                                                                            end
                                                                                                                                                                                                                            end

                                                                                                                                                                                                                            local function drawFullLayout(sample, sleepText)
                                                                                                                                                                                                                            local leftWidth = math.floor((ui.w - 3) * 0.58)
                                                                                                                                                                                                                            local rightX = leftWidth + 3
                                                                                                                                                                                                                            local rightWidth = ui.w - rightX + 1

                                                                                                                                                                                                                            local statusColor = stateColor(sample)
                                                                                                                                                                                                                            local stability = sample and sample.stability or nil
                                                                                                                                                                                                                            local stabilityText = stability
                                                                                                                                                                                                                            and string.format(
                                                                                                                                                                                                                              "%.1f%% %s",
                                                                                                                                                                                                                              stability,
                                                                                                                                                                                                                              stabilitySourceText(sample.stabilityType)
                                                                                                                                                                                                                            )
                                                                                                                                                                                                                            or "UNKNOWN"
                                                                                                                                                                                                                            local stabilityColor = C.good

                                                                                                                                                                                                                            if stability and stability <= emergencyCloseStability then
                                                                                                                                                                                                                              stabilityColor = C.bad
                                                                                                                                                                                                                              elseif stability and stability <= targetStability + 5 then
                                                                                                                                                                                                                                stabilityColor = C.warn
                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                -- Header
                                                                                                                                                                                                                                fill(1, 1, ui.w, 3, " ", C.white, C.panel2)
                                                                                                                                                                                                                                drawText(3, 1, "BLACK HOLE COMPRESSOR CONTROL", C.white, C.panel2, ui.w - 28)
                                                                                                                                                                                                                                drawText(ui.w - 22, 1, logTimestamp(), C.dim, C.panel2, 20)
                                                                                                                                                                                                                                drawText(3, 2, "STATE: " .. stateLabel(sample), statusColor, C.panel2, ui.w - 6)

                                                                                                                                                                                                                                -- Stability
                                                                                                                                                                                                                                box(2, 4, leftWidth, 8, "STABILITY", C.panel, C.border)
                                                                                                                                                                                                                                drawText(4, 6, "Current:", C.dim, C.panel, 10)
                                                                                                                                                                                                                                drawText(14, 6, stabilityText, stabilityColor, C.panel, leftWidth - 16)
                                                                                                                                                                                                                                drawText(4, 7, "Inject target:", C.dim, C.panel, 15)
                                                                                                                                                                                                                                drawText(19, 7, string.format("%.1f%%", targetStability), C.accent, C.panel, 10)
                                                                                                                                                                                                                                drawText(4, 8, "Emergency:", C.dim, C.panel, 12)
                                                                                                                                                                                                                                drawText(16, 8, string.format("%.1f%%", emergencyCloseStability), C.bad, C.panel, 10)
                                                                                                                                                                                                                                progressBar(4, 10, leftWidth - 4, (stability or 0) / 100, stabilityColor,
                                                                                                                                                                                                                                            stability and string.format("%.1f%%", stability) or "UNKNOWN", C.panel)

                                                                                                                                                                                                                                -- Recipe
                                                                                                                                                                                                                                box(2, 13, leftWidth, 8, "RECIPE", C.panel, C.border)
                                                                                                                                                                                                                                local recipePercent = sample and (sample.recipePercent or 0) or 0
                                                                                                                                                                                                                                local progress = sample and numberText(sample.progress or 0) or "0"
                                                                                                                                                                                                                                local maximum = sample and numberText(sample.maximum or 0) or "0"
                                                                                                                                                                                                                                drawText(4, 15, "Status:", C.dim, C.panel, 9)
                                                                                                                                                                                                                                drawText(13, 15,
                                                                                                                                                                                                                                         sample and (sample.recipeActive and "ACTIVE" or "IDLE") or "IDLE",
                                                                                                                                                                                                                                         sample and sample.recipeActive and C.good or C.dim,
                                                                                                                                                                                                                                         C.panel,
                                                                                                                                                                                                                                         12)
                                                                                                                                                                                                                                drawText(4, 16, "Progress:", C.dim, C.panel, 10)
                                                                                                                                                                                                                                drawText(14, 16,
                                                                                                                                                                                                                                         string.format("%.1f%% (%s/%s)", recipePercent, progress, maximum),
                                                                                                                                                                                                                                         C.text,
                                                                                                                                                                                                                                         C.panel,
                                                                                                                                                                                                                                         leftWidth - 16)
                                                                                                                                                                                                                                progressBar(4, 18, leftWidth - 4, recipePercent / 100, C.accent,
                                                                                                                                                                                                                                            string.format("%.1f%%", recipePercent), C.panel)

                                                                                                                                                                                                                                -- Runtime
                                                                                                                                                                                                                                box(2, 22, leftWidth, 8, "RUNTIME", C.panel, C.border)
                                                                                                                                                                                                                                drawText(4, 24, "Elapsed:", C.dim, C.panel, 9)
                                                                                                                                                                                                                                drawText(13, 24, sample and formatElapsed(sample.elapsed or 0) or "00:00:00",
                                                                                                                                                                                                                                         C.text, C.panel, 10)
                                                                                                                                                                                                                                drawText(27, 24, "Hole:", C.dim, C.panel, 6)
                                                                                                                                                                                                                                drawText(33, 24,
                                                                                                                                                                                                                                         sample and (sample.holeOpen and "OPEN" or "CLOSED") or "CLOSED",
                                                                                                                                                                                                                                         sample and sample.holeOpen and C.good or C.dim,
                                                                                                                                                                                                                                         C.panel,
                                                                                                                                                                                                                                         8)
                                                                                                                                                                                                                                drawText(44, 24, "Transmitter:", C.dim, C.panel, 13)
                                                                                                                                                                                                                                drawText(57, 24, tostring(sample and sample.tx or 0), C.text, C.panel, 4)

                                                                                                                                                                                                                                if state.idleSince and sample then
                                                                                                                                                                                                                                  drawText(64, 24,
                                                                                                                                                                                                                                           string.format("Idle %.0fs", sample.now - state.idleSince),
                                                                                                                                                                                                                                           C.warn,
                                                                                                                                                                                                                                           C.panel,
                                                                                                                                                                                                                                           leftWidth - 66)
                                                                                                                                                                                                                                  end

                                                                                                                                                                                                                                  local emergencyText = emergencyStatusText(sample and sample.now)
                                                                                                                                                                                                                                  if emergencyText then
                                                                                                                                                                                                                                    drawText(4, 25, emergencyText, C.bad, C.panel, leftWidth - 4)
                                                                                                                                                                                                                                    end

                                                                                                                                                                                                                                    drawText(
                                                                                                                                                                                                                                      4,
                                                                                                                                                                                                                                      26,
                                                                                                                                                                                                                                      "Controller: " .. (state.controllerForcedOff and "DISABLED" or "ENABLED"),
                                                                                                                                                                                                                                             state.controllerForcedOff and C.bad or C.good,
                                                                                                                                                                                                                                             C.panel,
                                                                                                                                                                                                                                             leftWidth - 4
                                                                                                                                                                                                                                    )

                                                                                                                                                                                                                                    -- Spacetime
                                                                                                                                                                                                                                    box(rightX, 4, rightWidth, 11, "SPACETIME", C.panel, C.border)
                                                                                                                                                                                                                                    local available, tankDetails, readable, stockerAmounts = getTankInformation()
                                                                                                                                                                                                                                    local remaining, needed, projectedRuntime = getSpacetimeRequirement(
                                                                                                                                                                                                                                      available,
                                                                                                                                                                                                                                      sample
                                                                                                                                                                                                                                    )
                                                                                                                                                                                                                                    local reserveOK, stockerBypass = acceptSpacetimeReserve(
                                                                                                                                                                                                                                      remaining,
                                                                                                                                                                                                                                      stockerAmounts,
                                                                                                                                                                                                                                      readable
                                                                                                                                                                                                                                    )
                                                                                                                                                                                                                                    local reserveText
                                                                                                                                                                                                                                    local reserveColor

                                                                                                                                                                                                                                    if stockerBypass then
                                                                                                                                                                                                                                      reserveText = "STOCKERS >1G: PROCEEDING"
                                                                                                                                                                                                                                      reserveColor = C.warn
                                                                                                                                                                                                                                      elseif reserveOK then
                                                                                                                                                                                                                                        reserveText = "Reserve: " .. numberText(remaining) .. " L"
                                                                                                                                                                                                                                        reserveColor = C.good
                                                                                                                                                                                                                                        else
                                                                                                                                                                                                                                          reserveText = "MISSING: " .. numberText(-remaining) .. " L"
                                                                                                                                                                                                                                          reserveColor = C.bad
                                                                                                                                                                                                                                          end

                                                                                                                                                                                                                                          drawText(rightX + 2, 6, "Available: " .. numberText(available) .. " L",
                                                                                                                                                                                                                                                   readable > 0 and C.text or C.bad, C.panel, rightWidth - 4)
                                                                                                                                                                                                                                          drawText(rightX + 2, 7, "Required:  " .. numberText(needed) .. " L",
                                                                                                                                                                                                                                                   C.dim, C.panel, rightWidth - 4)
                                                                                                                                                                                                                                          drawText(rightX + 2, 8,
                                                                                                                                                                                                                                                   "Protected runtime: " .. numberText(projectedRuntime) .. "s ("
                                                                                                                                                                                                                                                   .. formatDurationWords(projectedRuntime) .. ")",
                                                                                                                                                                                                                                                   C.dim, C.panel, rightWidth - 4)
                                                                                                                                                                                                                                          drawText(rightX + 2, 9, reserveText, reserveColor, C.panel, rightWidth - 4)
                                                                                                                                                                                                                                          drawText(rightX + 2, 10, "Spacetime flow: " .. (sample and flowText(sample) or "OFF"),
                                                                                                                                                                                                                                                   state.spacetimeOn and C.good or C.dim, C.panel, rightWidth - 4)

                                                                                                                                                                                                                                          local detailY = 12
                                                                                                                                                                                                                                          for index = 1, math.min(#tankDetails, 3) do
                                                                                                                                                                                                                                            drawText(rightX + 2, detailY, tankDetails[index], C.text, C.panel, rightWidth - 4)
                                                                                                                                                                                                                                            detailY = detailY + 1
                                                                                                                                                                                                                                            end

                                                                                                                                                                                                                                            -- Config
                                                                                                                                                                                                                                            box(rightX, 16, rightWidth, 8, "CONFIG", C.panel, C.border)
                                                                                                                                                                                                                                            drawText(rightX + 2, 18, "Max runtime: " .. tostring(maxRuntime) .. "s",
                                                                                                                                                                                                                                                     C.text, C.panel, rightWidth - 4)
                                                                                                                                                                                                                                            drawText(rightX + 2, 19,
                                                                                                                                                                                                                                                     "Idle close: " .. tostring(closeWhenIdle)
                                                                                                                                                                                                                                                     .. " after " .. tostring(idleCloseSeconds) .. "s",
                                                                                                                                                                                                                                                     closeWhenIdle and C.good or C.dim,
                                                                                                                                                                                                                                                     C.panel,
                                                                                                                                                                                                                                                     rightWidth - 4)
                                                                                                                                                                                                                                            drawText(rightX + 2, 20, "Minimum open: " .. tostring(minimumRuntimeBeforeIdleClose) .. "s",
                                                                                                                                                                                                                                                     C.text, C.panel, rightWidth - 4)
                                                                                                                                                                                                                                            drawText(rightX + 2, 21, "Void protection: " .. tostring(voidProtection),
                                                                                                                                                                                                                                                     voidProtection and C.good or C.dim, C.panel, rightWidth - 4)
                                                                                                                                                                                                                                            drawText(rightX + 2, 22, "Use Collapser item: " .. tostring(useCollapser),
                                                                                                                                                                                                                                                     useCollapser and C.good or C.warn, C.panel, rightWidth - 4)

                                                                                                                                                                                                                                            -- Quotes
                                                                                                                                                                                                                                            drawQuotesBox(
                                                                                                                                                                                                                                              rightX,
                                                                                                                                                                                                                                              25,
                                                                                                                                                                                                                                              rightWidth,
                                                                                                                                                                                                                                              5,
                                                                                                                                                                                                                                              quotePanelText(sleepText)
                                                                                                                                                                                                                                            )

                                                                                                                                                                                                                                            -- Logs
                                                                                                                                                                                                                                            local logY = 31
                                                                                                                                                                                                                                            local logHeight = ui.h - logY + 1

                                                                                                                                                                                                                                            if logHeight >= 4 then
                                                                                                                                                                                                                                              drawLogs(2, logY, ui.w - 2, logHeight)
                                                                                                                                                                                                                                              end
                                                                                                                                                                                                                                              end

                                                                                                                                                                                                                                              local function drawCompactLayout(sample, sleepText)
                                                                                                                                                                                                                                              local statusColor = stateColor(sample)
                                                                                                                                                                                                                                              local stability = sample and sample.stability or nil
                                                                                                                                                                                                                                              local stabilityColor = C.good

                                                                                                                                                                                                                                              if stability and stability <= emergencyCloseStability then
                                                                                                                                                                                                                                                stabilityColor = C.bad
                                                                                                                                                                                                                                                elseif stability and stability <= targetStability + 5 then
                                                                                                                                                                                                                                                  stabilityColor = C.warn
                                                                                                                                                                                                                                                  end

                                                                                                                                                                                                                                                  fill(1, 1, ui.w, 2, " ", C.white, C.panel2)
                                                                                                                                                                                                                                                  drawText(2, 1, "BHC DASHBOARD", C.white, C.panel2, ui.w - 18)
                                                                                                                                                                                                                                                  drawText(ui.w - 9, 1, logTimestamp(), C.dim, C.panel2, 8)
                                                                                                                                                                                                                                                  drawText(2, 2, "STATE: " .. stateLabel(sample), statusColor, C.panel2, ui.w - 4)

                                                                                                                                                                                                                                                  box(1, 3, ui.w, 5, "MACHINE", C.panel, C.border)
                                                                                                                                                                                                                                                  local stabilityText = stability
                                                                                                                                                                                                                                                  and string.format(
                                                                                                                                                                                                                                                    "%.1f%% %s",
                                                                                                                                                                                                                                                    stability,
                                                                                                                                                                                                                                                    stabilitySourceText(sample.stabilityType)
                                                                                                                                                                                                                                                  )
                                                                                                                                                                                                                                                  or "UNKNOWN"
                                                                                                                                                                                                                                                  drawText(3, 4,
                                                                                                                                                                                                                                                           "Stability " .. stabilityText
                                                                                                                                                                                                                                                           .. " | Runtime " .. (sample and formatElapsed(sample.elapsed or 0) or "00:00:00")
                                                                                                                                                                                                                                                           .. " | Utility Hatch " .. (sample and (sample.holeOpen and "OPEN" or "CLOSED") or "CLOSED")
                                                                                                                                                                                                                                                           .. " | Transmitter " .. tostring(sample and sample.tx or 0),
                                                                                                                                                                                                                                                           stabilityColor,
                                                                                                                                                                                                                                                           C.panel,
                                                                                                                                                                                                                                                           ui.w - 4)
                                                                                                                                                                                                                                                  progressBar(3, 6, ui.w - 4, (stability or 0) / 100, stabilityColor,
                                                                                                                                                                                                                                                              stability and string.format("%.1f%%", stability) or "UNKNOWN", C.panel)

                                                                                                                                                                                                                                                  box(1, 8, ui.w, 5, "RECIPE", C.panel, C.border)
                                                                                                                                                                                                                                                  local recipePercent = sample and (sample.recipePercent or 0) or 0
                                                                                                                                                                                                                                                  drawText(3, 9,
                                                                                                                                                                                                                                                           (sample and sample.recipeActive and "ACTIVE" or "IDLE")
                                                                                                                                                                                                                                                           .. " | " .. string.format("%.1f%%", recipePercent)
                                                                                                                                                                                                                                                           .. " | " .. numberText(sample and sample.progress or 0)
                                                                                                                                                                                                                                                           .. "/" .. numberText(sample and sample.maximum or 0),
                                                                                                                                                                                                                                                           sample and sample.recipeActive and C.good or C.dim,
                                                                                                                                                                                                                                                           C.panel,
                                                                                                                                                                                                                                                           ui.w - 4)
                                                                                                                                                                                                                                                  progressBar(3, 11, ui.w - 4, recipePercent / 100, C.accent,
                                                                                                                                                                                                                                                              string.format("%.1f%%", recipePercent), C.panel)

                                                                                                                                                                                                                                                  box(1, 13, ui.w, 6, "SPACETIME", C.panel, C.border)
                                                                                                                                                                                                                                                  local available, tankDetails, readable, stockerAmounts = getTankInformation()
                                                                                                                                                                                                                                                  local remaining, needed, projectedRuntime = getSpacetimeRequirement(
                                                                                                                                                                                                                                                    available,
                                                                                                                                                                                                                                                    sample
                                                                                                                                                                                                                                                  )
                                                                                                                                                                                                                                                  local reserveOK, stockerBypass = acceptSpacetimeReserve(
                                                                                                                                                                                                                                                    remaining,
                                                                                                                                                                                                                                                    stockerAmounts,
                                                                                                                                                                                                                                                    readable
                                                                                                                                                                                                                                                  )
                                                                                                                                                                                                                                                  local reserveText = stockerBypass
                                                                                                                                                                                                                                                  and "STOCKERS >1G: PROCEEDING"
                                                                                                                                                                                                                                                  or (reserveOK
                                                                                                                                                                                                                                                  and ("Reserve " .. numberText(remaining) .. " L")
                                                                                                                                                                                                                                                  or ("MISSING " .. numberText(-remaining) .. " L"))
                                                                                                                                                                                                                                                  local reserveColor = stockerBypass and C.warn or (reserveOK and C.good or C.bad)

                                                                                                                                                                                                                                                  drawText(3, 14,
                                                                                                                                                                                                                                                           "Available " .. numberText(available) .. " L | Required " .. numberText(needed)
                                                                                                                                                                                                                                                           .. " L | Protected runtime " .. numberText(projectedRuntime) .. "s ("
                                                                                                                                                                                                                                                           .. formatDurationWords(projectedRuntime) .. ")",
                                                                                                                                                                                                                                                           readable > 0 and C.text or C.bad,
                                                                                                                                                                                                                                                           C.panel,
                                                                                                                                                                                                                                                           ui.w - 4)
                                                                                                                                                                                                                                                  drawText(3, 15,
                                                                                                                                                                                                                                                           reserveText .. " | Spacetime flow " .. (sample and flowText(sample) or "OFF"),
                                                                                                                                                                                                                                                           reserveColor,
                                                                                                                                                                                                                                                           C.panel,
                                                                                                                                                                                                                                                           ui.w - 4)
                                                                                                                                                                                                                                                  drawText(3, 16, table.concat(tankDetails, " | "), C.dim, C.panel, ui.w - 4)
                                                                                                                                                                                                                                                  drawText(3, 17,
                                                                                                                                                                                                                                                           "Runtime " .. maxRuntime .. "s | Idle close " .. tostring(closeWhenIdle)
                                                                                                                                                                                                                                                           .. " | Collapser " .. tostring(useCollapser),
                                                                                                                                                                                                                                                           C.dim,
                                                                                                                                                                                                                                                           C.panel,
                                                                                                                                                                                                                                                           ui.w - 4)

                                                                                                                                                                                                                                                  drawQuotesBox(
                                                                                                                                                                                                                                                    1,
                                                                                                                                                                                                                                                    19,
                                                                                                                                                                                                                                                    ui.w,
                                                                                                                                                                                                                                                    3,
                                                                                                                                                                                                                                                    quotePanelText(sleepText)
                                                                                                                                                                                                                                                  )

                                                                                                                                                                                                                                                  local logY = 22
                                                                                                                                                                                                                                                  local logHeight = ui.h - logY + 1

                                                                                                                                                                                                                                                  if logHeight >= 4 then
                                                                                                                                                                                                                                                    drawLogs(1, logY, ui.w, logHeight)
                                                                                                                                                                                                                                                    end
                                                                                                                                                                                                                                                    end

                                                                                                                                                                                                                                                    local function drawDashboard(sample, sleepText)
                                                                                                                                                                                                                                                    ui.lastSample = sample or ui.lastSample

                                                                                                                                                                                                                                                    if sleepText ~= nil then
                                                                                                                                                                                                                                                      ui.lastSleepText = sleepText
                                                                                                                                                                                                                                                      end

                                                                                                                                                                                                                                                      sample = ui.lastSample

                                                                                                                                                                                                                                                      -- Check the configured quote timer on every dashboard refresh. Active
                                                                                                                                                                                                                                                      -- recipes redraw frequently, but a quote changes only when its interval is due.
                                                                                                                                                                                                                                                      rotateQuoteIfDue(sample and sample.now or computer.uptime(), false)

                                                                                                                                                                                                                                                      ui.w, ui.h = gpu.getResolution()

                                                                                                                                                                                                                                                      local layout = (ui.w >= 100 and ui.h >= 35)
                                                                                                                                                                                                                                                      and "FULL"
                                                                                                                                                                                                                                                      or "COMPACT"

                                                                                                                                                                                                                                                      -- With an off-screen VRAM buffer this clear is invisible. Without a
                                                                                                                                                                                                                                                      -- buffer, only clear on the first frame or after a layout change so the
                                                                                                                                                                                                                                                      -- screen does not flash blank before every configured redraw.
                                                                                                                                                                                                                                                      if ui.usingBuffer
                                                                                                                                                                                                                                                        or ui.firstDraw
                                                                                                                                                                                                                                                        or ui.lastLayout ~= layout then
                                                                                                                                                                                                                                                        fill(1, 1, ui.w, ui.h, " ", C.text, C.bg)
                                                                                                                                                                                                                                                        end

                                                                                                                                                                                                                                                        if layout == "FULL" then
                                                                                                                                                                                                                                                          drawFullLayout(sample, ui.lastSleepText)
                                                                                                                                                                                                                                                          else
                                                                                                                                                                                                                                                            drawCompactLayout(sample, ui.lastSleepText)
                                                                                                                                                                                                                                                            end

                                                                                                                                                                                                                                                            ui.firstDraw = false
                                                                                                                                                                                                                                                            ui.lastLayout = layout
                                                                                                                                                                                                                                                            end

                                                                                                                                                                                                                                                            local function releaseUIBuffer()
                                                                                                                                                                                                                                                            pcall(gpu.setActiveBuffer, 0)

                                                                                                                                                                                                                                                            if ui.buffer then
                                                                                                                                                                                                                                                              pcall(gpu.freeBuffer, ui.buffer)
                                                                                                                                                                                                                                                              end

                                                                                                                                                                                                                                                              ui.buffer = nil
                                                                                                                                                                                                                                                              ui.usingBuffer = false
                                                                                                                                                                                                                                                              ui.firstDraw = true
                                                                                                                                                                                                                                                              end

                                                                                                                                                                                                                                                              local function drawDirect(sample, sleepText)
                                                                                                                                                                                                                                                              pcall(gpu.setActiveBuffer, 0)
                                                                                                                                                                                                                                                              return pcall(drawDashboard, sample, sleepText)
                                                                                                                                                                                                                                                              end

                                                                                                                                                                                                                                                              function ui.draw(sample, sleepText)
                                                                                                                                                                                                                                                              if not ui.ready then
                                                                                                                                                                                                                                                                return false
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                local ok
                                                                                                                                                                                                                                                                local errorMessage

                                                                                                                                                                                                                                                                if ui.usingBuffer and ui.buffer then
                                                                                                                                                                                                                                                                local switched, switchError = pcall(
                                                                                                                                                                                                                                                                gpu.setActiveBuffer,
                                                                                                                                                                                                                                                                ui.buffer
                                                                                                                                                                                                                                                                )

                                                                                                                                                                                                                                                                if switched then
                                                                                                                                                                                                                                                                ok, errorMessage = pcall(
                                                                                                                                                                                                                                                                drawDashboard,
                                                                                                                                                                                                                                                                sample,
                                                                                                                                                                                                                                                                sleepText
                                                                                                                                                                                                                                                                )

                                                                                                                                                                                                                                                                pcall(gpu.setActiveBuffer, 0)

                                                                                                                                                                                                                                                                if ok then
                                                                                                                                                                                                                                                                local copied, copyError = pcall(
                                                                                                                                                                                                                                                                gpu.bitblt,
                                                                                                                                                                                                                                                                0,
                                                                                                                                                                                                                                                                1,
                                                                                                                                                                                                                                                                1,
                                                                                                                                                                                                                                                                ui.w,
                                                                                                                                                                                                                                                                ui.h,
                                                                                                                                                                                                                                                                ui.buffer,
                                                                                                                                                                                                                                                                1,
                                                                                                                                                                                                                                                                1
                                                                                                                                                                                                                                                                )

                                                                                                                                                                                                                                                                if not copied then
                                                                                                                                                                                                                                                                ok = false
                                                                                                                                                                                                                                                                errorMessage = copyError
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                else
                                                                                                                                                                                                                                                                ok = false
                                                                                                                                                                                                                                                                errorMessage = switchError
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                -- If this OpenComputers build exposes buffer methods but cannot use
                                                                                                                                                                                                                                                                -- them reliably, fall back to direct drawing without killing the UI.
                                                                                                                                                                                                                                                                if not ok then
                                                                                                                                                                                                                                                                releaseUIBuffer()
                                                                                                                                                                                                                                                                ok, errorMessage = drawDirect(sample, sleepText)
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                else
                                                                                                                                                                                                                                                                ok, errorMessage = drawDirect(sample, sleepText)
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                if not ok then
                                                                                                                                                                                                                                                                releaseUIBuffer()
                                                                                                                                                                                                                                                                ui.ready = false
                                                                                                                                                                                                                                                                pcall(term.clear)
                                                                                                                                                                                                                                                                pcall(term.setCursor, 1, 1)
                                                                                                                                                                                                                                                                print("BHC UI ERROR: " .. cleanText(errorMessage))
                                                                                                                                                                                                                                                                print("BHC: Continuing in console mode.")
                                                                                                                                                                                                                                                                return false
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                return true
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                function ui.log(message, color)
                                                                                                                                                                                                                                                                message = tostring(message or "")

                                                                                                                                                                                                                                                                if message == "" then
                                                                                                                                                                                                                                                                return
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                ui.logLines[#ui.logLines + 1] = {
                                                                                                                                                                                                                                                                time = logTimestamp(),
                                                                                                                                                                                                                                                                message = message,
                                                                                                                                                                                                                                                                color = color or C.text
                                                                                                                                                                                                                                                                }

                                                                                                                                                                                                                                                                -- Events stay in the event log. They never replace the rotating quote.
                                                                                                                                                                                                                                                                ui.lastEventText = message

                                                                                                                                                                                                                                                                while #ui.logLines > uiMaxStoredLogLines do
                                                                                                                                                                                                                                                                table.remove(ui.logLines, 1)
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                ui.draw(ui.lastSample, ui.lastSleepText)
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                function ui.status(sample)
                                                                                                                                                                                                                                                                return ui.draw(sample, ui.lastSleepText)
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                function ui.setSleepMessage(message, sample)
                                                                                                                                                                                                                                                                ui.lastSleepText = tostring(message or "")
                                                                                                                                                                                                                                                                ui.quoteNextAt = computer.uptime() + quoteIntervalSeconds()
                                                                                                                                                                                                                                                                return ui.draw(sample or ui.lastSample, ui.lastSleepText)
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                function ui.init()
                                                                                                                                                                                                                                                                if not uiEnabled then
                                                                                                                                                                                                                                                                return false
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                if not gpu then
                                                                                                                                                                                                                                                                print("BHC UI WARNING: No GPU component found; using console mode.")
                                                                                                                                                                                                                                                                return false
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                pcall(gpu.setActiveBuffer, 0)

                                                                                                                                                                                                                                                                if uiUseMaximumResolution then
                                                                                                                                                                                                                                                                local ok, maximumWidth, maximumHeight = pcall(gpu.maxResolution)

                                                                                                                                                                                                                                                                if ok and maximumWidth and maximumHeight then
                                                                                                                                                                                                                                                                pcall(gpu.setResolution, maximumWidth, maximumHeight)
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                local ok, width, height = pcall(gpu.getResolution)

                                                                                                                                                                                                                                                                if not ok or not width or not height then
                                                                                                                                                                                                                                                                print("BHC UI WARNING: Could not read screen resolution; using console mode.")
                                                                                                                                                                                                                                                                return false
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                ui.w = width
                                                                                                                                                                                                                                                                ui.h = height
                                                                                                                                                                                                                                                                ui.buffer = nil
                                                                                                                                                                                                                                                                ui.usingBuffer = false
                                                                                                                                                                                                                                                                ui.firstDraw = true
                                                                                                                                                                                                                                                                ui.lastLayout = nil

                                                                                                                                                                                                                                                                -- OpenComputers versions with the VRAM buffer API can render the whole
                                                                                                                                                                                                                                                                -- dashboard off-screen and copy the finished frame to the screen in one
                                                                                                                                                                                                                                                                -- operation. That prevents visible partial redraws and flashing.
                                                                                                                                                                                                                                                                local bufferOK, bufferIndex = pcall(
                                                                                                                                                                                                                                                                gpu.allocateBuffer,
                                                                                                                                                                                                                                                                width,
                                                                                                                                                                                                                                                                height
                                                                                                                                                                                                                                                                )

                                                                                                                                                                                                                                                                if bufferOK and type(bufferIndex) == "number" then
                                                                                                                                                                                                                                                                ui.buffer = bufferIndex
                                                                                                                                                                                                                                                                ui.usingBuffer = true
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                ui.ready = true
                                                                                                                                                                                                                                                                pcall(gpu.setActiveBuffer, 0)
                                                                                                                                                                                                                                                                term.clear()
                                                                                                                                                                                                                                                                term.setCursor(1, 1)

                                                                                                                                                                                                                                                                return ui.draw(nil, "Waiting for request signal.")
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                local function printStatus(sample)
                                                                                                                                                                                                                                                                sample = sample or sampleStatus()

                                                                                                                                                                                                                                                                if ui and ui.ready then
                                                                                                                                                                                                                                                                ui.status(sample)
                                                                                                                                                                                                                                                                return
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                local stabilityText = "UNKNOWN"

                                                                                                                                                                                                                                                                if sample.stability ~= nil then
                                                                                                                                                                                                                                                                stabilityText = string.format(
                                                                                                                                                                                                                                                                "%.1f%% %s",
                                                                                                                                                                                                                                                                sample.stability,
                                                                                                                                                                                                                                                                stabilitySourceText(sample.stabilityType)
                                                                                                                                                                                                                                                                )
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                print(string.format(
                                                                                                                                                                                                                                                                "BHC: Runtime %s | Utility Hatch %s | Stability %s | Recipe %s %.1f%% (%s/%s) | Spacetime %s | Transmitter %d | Tank %s L",
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
                                                                                                                                                                                                                                                                state.flowLastTank = state.lastTank
                                                                                                                                                                                                                                                                state.flowLastAt = now
                                                                                                                                                                                                                                                                state.flowDelta = nil
                                                                                                                                                                                                                                                                state.flowDisplay = "ENABLED - WAITING FOR FLOW SAMPLE"
                                                                                                                                                                                                                                                                state.fallbackLossStart = nil
                                                                                                                                                                                                                                                                state.fallbackLossStability = nil

                                                                                                                                                                                                                                                                local setOK, setError = pcall(
                                                                                                                                                                                                                                                                redstone.setOutput,
                                                                                                                                                                                                                                                                transmitterSide,
                                                                                                                                                                                                                                                                15
                                                                                                                                                                                                                                                                )

                                                                                                                                                                                                                                                                if not setOK then
                                                                                                                                                                                                                                                                state.spacetimeOn = false
                                                                                                                                                                                                                                                                emit(
                                                                                                                                                                                                                                                                "BHC CRITICAL: Could not enable Spacetime redstone output: "
                                                                                                                                                                                                                                                                .. cleanText(setError),
                                                                                                                                                                                                                                                                C.bad
                                                                                                                                                                                                                                                                )
                                                                                                                                                                                                                                                                return false
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                os.sleep(0.1)

                                                                                                                                                                                                                                                                local output = getTX()

                                                                                                                                                                                                                                                                if output < 15 then
                                                                                                                                                                                                                                                                -- Retry once in case the first component write was delayed.
                                                                                                                                                                                                                                                                pcall(redstone.setOutput, transmitterSide, 15)
                                                                                                                                                                                                                                                                os.sleep(0.1)
                                                                                                                                                                                                                                                                output = getTX()
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                if output < 15 then
                                                                                                                                                                                                                                                                state.spacetimeOn = false
                                                                                                                                                                                                                                                                emit(
                                                                                                                                                                                                                                                                "BHC CRITICAL: Spacetime transmitter output did not reach 15; transmitter is "
                                                                                                                                                                                                                                                                .. tostring(output)
                                                                                                                                                                                                                                                                .. ".",
                                                                                                                                                                                                                                                                C.bad
                                                                                                                                                                                                                                                                )
                                                                                                                                                                                                                                                                return false
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                emit("BHC: Spacetime transmitter enabled; output confirmed at 15!", C.good)
                                                                                                                                                                                                                                                                return true
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
                                                                                                                                                                                                                                                                state.flowLastTank = state.lastTank
                                                                                                                                                                                                                                                                state.flowLastAt = now
                                                                                                                                                                                                                                                                state.flowDelta = nil
                                                                                                                                                                                                                                                                state.flowDisplay = "OFF"
                                                                                                                                                                                                                                                                state.fallbackLossStart = nil
                                                                                                                                                                                                                                                                state.fallbackLossStability = nil

                                                                                                                                                                                                                                                                redstone.setOutput(transmitterSide, 0)

                                                                                                                                                                                                                                                                if showMessage then
                                                                                                                                                                                                                                                                emit("BHC: Spacetime transmitter disabled!")
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
                                                                                                                                                                                                                                                                emit(
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

                                                                                                                                                                                                                                                                emit(
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

                                                                                                                                                                                                                                                                local function collapserAvailable()
                                                                                                                                                                                                                                                                if not useCollapser then
                                                                                                                                                                                                                                                                return false
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                local ok, stack = pcall(
                                                                                                                                                                                                                                                                transposer.getStackInSlot,
                                                                                                                                                                                                                                                                interfaceSide,
                                                                                                                                                                                                                                                                2
                                                                                                                                                                                                                                                                )

                                                                                                                                                                                                                                                                return ok and stack ~= nil
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                local function tryInsertCollapser()
                                                                                                                                                                                                                                                                if not useCollapser then
                                                                                                                                                                                                                                                                return false, "Collapser use is disabled in configuration."
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                if not collapserAvailable() then
                                                                                                                                                                                                                                                                return false, "No Collapser is available in interface slot 2."
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                local started = computer.uptime()
                                                                                                                                                                                                                                                                local timeout = math.max(
                                                                                                                                                                                                                                                                0.1,
                                                                                                                                                                                                                                                                tonumber(collapserInsertTimeoutSeconds) or 5
                                                                                                                                                                                                                                                                )
                                                                                                                                                                                                                                                                local nextWarning = 0

                                                                                                                                                                                                                                                                enableController(true)

                                                                                                                                                                                                                                                                while isHoleOpen() and computer.uptime() - started < timeout do
                                                                                                                                                                                                                                                                enableController(false)

                                                                                                                                                                                                                                                                local ok, moved = pcall(
                                                                                                                                                                                                                                                                transposer.transferItem,
                                                                                                                                                                                                                                                                interfaceSide,
                                                                                                                                                                                                                                                                busSide,
                                                                                                                                                                                                                                                                1,
                                                                                                                                                                                                                                                                2
                                                                                                                                                                                                                                                                )

                                                                                                                                                                                                                                                                if ok and moved and moved > 0 then
                                                                                                                                                                                                                                                                emit(
                                                                                                                                                                                                                                                                "BHC: Collapser inserted; controller remains enabled.",
                                                                                                                                                                                                                                                                C.good
                                                                                                                                                                                                                                                                )
                                                                                                                                                                                                                                                                return true
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                if not collapserAvailable() then
                                                                                                                                                                                                                                                                return false, "The Collapser disappeared before it could be inserted."
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                if computer.uptime() >= nextWarning then
                                                                                                                                                                                                                                                                emit(
                                                                                                                                                                                                                                                                "BHC WARNING: Could not insert Collapser yet; retrying.",
                                                                                                                                                                                                                                                                C.warn
                                                                                                                                                                                                                                                                )
                                                                                                                                                                                                                                                                nextWarning = computer.uptime() + 1
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                os.sleep(math.min(0.25, timeout))
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                if not isHoleOpen() then
                                                                                                                                                                                                                                                                return true
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                return false, "Collapser insertion timed out after "
                                                                                                                                                                                                                                                                .. tostring(timeout)
                                                                                                                                                                                                                                                                .. " seconds."
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                local function waitForHoleToClose()
                                                                                                                                                                                                                                                                local interval = math.max(0.05, tonumber(uiRefreshInterval) or 0.25)
                                                                                                                                                                                                                                                                local nextPrint = computer.uptime()

                                                                                                                                                                                                                                                                while isHoleOpen() do
                                                                                                                                                                                                                                                                enableController(false)

                                                                                                                                                                                                                                                                if computer.uptime() >= nextPrint then
                                                                                                                                                                                                                                                                if debugShowStatusEverySecond then
                                                                                                                                                                                                                                                                printStatus(sampleStatus())
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                nextPrint = computer.uptime() + interval
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                os.sleep(math.min(0.1, interval))
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                local function emergencyControllerOffFallback(reason)
                                                                                                                                                                                                                                                                local waitSeconds = math.max(
                                                                                                                                                                                                                                                                1,
                                                                                                                                                                                                                                                                tonumber(emergencyControllerOffSeconds) or 906
                                                                                                                                                                                                                                                                )
                                                                                                                                                                                                                                                                local verifyDelay = math.max(
                                                                                                                                                                                                                                                                0.1,
                                                                                                                                                                                                                                                                tonumber(emergencyControllerVerifyDelaySeconds) or 1
                                                                                                                                                                                                                                                                )
                                                                                                                                                                                                                                                                local interval = math.max(0.05, tonumber(uiRefreshInterval) or 0.25)

                                                                                                                                                                                                                                                                state.emergencyClosing = true
                                                                                                                                                                                                                                                                state.expectedClosing = true
                                                                                                                                                                                                                                                                state.emergencyReason = reason

                                                                                                                                                                                                                                                                disableSpacetime(false)

                                                                                                                                                                                                                                                                while true do
                                                                                                                                                                                                                                                                state.phase = "EMERGENCY_WAIT"
                                                                                                                                                                                                                                                                state.emergencyFallbackCycle = state.emergencyFallbackCycle + 1
                                                                                                                                                                                                                                                                state.emergencyFallbackStartedAt = computer.uptime()
                                                                                                                                                                                                                                                                state.emergencyFallbackDeadline = state.emergencyFallbackStartedAt
                                                                                                                                                                                                                                                                + waitSeconds

                                                                                                                                                                                                                                                                if not disableController(true) then
                                                                                                                                                                                                                                                                state.controllerForcedOff = false
                                                                                                                                                                                                                                                                emit(
                                                                                                                                                                                                                                                                "BHC CRITICAL: Controller could not be disabled. Keeping it enabled and waiting for Utility Hatch closure.",
                                                                                                                                                                                                                                                                C.bad
                                                                                                                                                                                                                                                                )
                                                                                                                                                                                                                                                                enableController(false)
                                                                                                                                                                                                                                                                waitForHoleToClose()
                                                                                                                                                                                                                                                                disableSpacetime(false)
                                                                                                                                                                                                                                                                resetState()
                                                                                                                                                                                                                                                                return false
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                state.controllerForcedOff = true

                                                                                                                                                                                                                                                                emit(string.format(
                                                                                                                                                                                                                                                                "BHC EMERGENCY: Controller disabled for %ss (%s) because no Collapser could close the Black Hole.",
                                                                                                                                                                                                                                                                numberText(waitSeconds),
                                                                                                                                                                                                                                                                formatDurationWords(waitSeconds)
                                                                                                                                                                                                                                                                ), C.bad)

                                                                                                                                                                                                                                                                while computer.uptime() < state.emergencyFallbackDeadline do
                                                                                                                                                                                                                                                                if debugShowStatusEverySecond then
                                                                                                                                                                                                                                                                printStatus(sampleStatus())
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                local remaining = state.emergencyFallbackDeadline - computer.uptime()
                                                                                                                                                                                                                                                                if remaining > 0 then
                                                                                                                                                                                                                                                                os.sleep(math.min(interval, remaining))
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                state.phase = "EMERGENCY_VERIFY"
                                                                                                                                                                                                                                                                emit(
                                                                                                                                                                                                                                                                "BHC EMERGENCY: Timer complete. Re-enabling controller to verify Utility Hatch closure.",
                                                                                                                                                                                                                                                                C.warn
                                                                                                                                                                                                                                                                )

                                                                                                                                                                                                                                                                if not enableController(true) then
                                                                                                                                                                                                                                                                state.controllerForcedOff = true
                                                                                                                                                                                                                                                                emit(
                                                                                                                                                                                                                                                                "BHC CRITICAL: Could not re-enable controller for closure verification; retrying shortly.",
                                                                                                                                                                                                                                                                C.bad
                                                                                                                                                                                                                                                                )
                                                                                                                                                                                                                                                                os.sleep(verifyDelay)
                                                                                                                                                                                                                                                                else
                                                                                                                                                                                                                                                                state.controllerForcedOff = false
                                                                                                                                                                                                                                                                os.sleep(verifyDelay)

                                                                                                                                                                                                                                                                if not isHoleOpen() and confirmHoleClosed() then
                                                                                                                                                                                                                                                                disableSpacetime(false)
                                                                                                                                                                                                                                                                emit(
                                                                                                                                                                                                                                                                "BHC: Timed emergency closure verified; Utility Hatch confirms the Black Hole is closed.",
                                                                                                                                                                                                                                                                C.good
                                                                                                                                                                                                                                                                )
                                                                                                                                                                                                                                                                resetState()
                                                                                                                                                                                                                                                                return false
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                emit(
                                                                                                                                                                                                                                                                "BHC CRITICAL: Utility Hatch still reports the Black Hole open after the timed shutdown. Starting another controller-off timer without resetting state.",
                                                                                                                                                                                                                                                                C.bad
                                                                                                                                                                                                                                                                )
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                disableSpacetime(false)
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                local function normalClose(reason)
                                                                                                                                                                                                                                                                if state.expectedClosing then
                                                                                                                                                                                                                                                                return
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                state.expectedClosing = true
                                                                                                                                                                                                                                                                state.phase = "CLOSING"

                                                                                                                                                                                                                                                                if reason then
                                                                                                                                                                                                                                                                emit("")
                                                                                                                                                                                                                                                                emit("BHC: " .. reason)
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                enableController(true)

                                                                                                                                                                                                                                                                local inserted = false
                                                                                                                                                                                                                                                                local insertReason = "Collapser use is disabled."

                                                                                                                                                                                                                                                                if useCollapser then
                                                                                                                                                                                                                                                                emit("BHC: Closing Black Hole!", C.warn)
                                                                                                                                                                                                                                                                inserted, insertReason = tryInsertCollapser()
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                if not inserted then
                                                                                                                                                                                                                                                                emit(
                                                                                                                                                                                                                                                                "BHC CRITICAL: Normal closure could not use a Collapser: "
                                                                                                                                                                                                                                                                .. tostring(insertReason),
                                                                                                                                                                                                                                                                C.bad
                                                                                                                                                                                                                                                                )
                                                                                                                                                                                                                                                                emergencyControllerOffFallback(insertReason)
                                                                                                                                                                                                                                                                return
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                waitForHoleToClose()
                                                                                                                                                                                                                                                                disableSpacetime(false)
                                                                                                                                                                                                                                                                enableController(false)

                                                                                                                                                                                                                                                                emit(
                                                                                                                                                                                                                                                                "BHC: Utility Hatch confirms Black Hole is closed!",
                                                                                                                                                                                                                                                                C.good
                                                                                                                                                                                                                                                                )

                                                                                                                                                                                                                                                                resetState()
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                local function emergencyClose(sample, reason)
                                                                                                                                                                                                                                                                if state.emergencyClosing then
                                                                                                                                                                                                                                                                return false
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                state.emergencyClosing = true
                                                                                                                                                                                                                                                                state.expectedClosing = true
                                                                                                                                                                                                                                                                state.phase = "EMERGENCY"
                                                                                                                                                                                                                                                                state.emergencyReason = reason

                                                                                                                                                                                                                                                                emit("")
                                                                                                                                                                                                                                                                emit("BHC EMERGENCY: " .. reason, C.bad)

                                                                                                                                                                                                                                                                if sample and sample.stability ~= nil then
                                                                                                                                                                                                                                                                emit(string.format(
                                                                                                                                                                                                                                                                "BHC EMERGENCY: Stability %.1f%% (%s).",
                                                                                                                                                                                                                                                                sample.stability,
                                                                                                                                                                                                                                                                stabilitySourceText(sample.stabilityType)
                                                                                                                                                                                                                                                                ), C.bad)
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                enableController(true)

                                                                                                                                                                                                                                                                local inserted = false
                                                                                                                                                                                                                                                                local insertReason = "Collapser use is disabled."

                                                                                                                                                                                                                                                                if useCollapser then
                                                                                                                                                                                                                                                                emit(
                                                                                                                                                                                                                                                                "BHC EMERGENCY: Attempting Collapser insertion while keeping the controller enabled.",
                                                                                                                                                                                                                                                                C.warn
                                                                                                                                                                                                                                                                )
                                                                                                                                                                                                                                                                inserted, insertReason = tryInsertCollapser()
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                if not inserted then
                                                                                                                                                                                                                                                                emit(
                                                                                                                                                                                                                                                                "BHC CRITICAL: No working Collapser closure is available: "
                                                                                                                                                                                                                                                                .. tostring(insertReason),
                                                                                                                                                                                                                                                                C.bad
                                                                                                                                                                                                                                                                )
                                                                                                                                                                                                                                                                emergencyControllerOffFallback(insertReason)
                                                                                                                                                                                                                                                                return false
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                waitForHoleToClose()
                                                                                                                                                                                                                                                                disableSpacetime(false)
                                                                                                                                                                                                                                                                enableController(false)

                                                                                                                                                                                                                                                                emit(
                                                                                                                                                                                                                                                                "BHC: Emergency closure complete; Black Hole is closed.",
                                                                                                                                                                                                                                                                C.good
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
                                                                                                                                                                                                                                                                "Actual Stability reached the %.1f%% safety threshold.",
                                                                                                                                                                                                                                                                emergencyCloseStability
                                                                                                                                                                                                                                                                )
                                                                                                                                                                                                                                                                else
                                                                                                                                                                                                                                                                reason = string.format(
                                                                                                                                                                                                                                                                "Estimated Stability reached the %.1f%% safety threshold after transmitter loss or empty Spacetime stockers.",
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
                                                                                                                                                                                                                                                                os.sleep(math.min(
                                                                                                                                                                                                                                                                math.max(0.05, tonumber(uiRefreshInterval) or 0.25),
                                                                                                                                                                                                                                                                remaining
                                                                                                                                                                                                                                                                ))
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                return true
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                -- ==================== BLACK HOLE CYCLE ====================

                                                                                                                                                                                                                                                                local function waitForHoleOpen()
                                                                                                                                                                                                                                                                state.phase = "OPENING"
                                                                                                                                                                                                                                                                emit("Waiting for Black Hole Utility Hatch open signal.", C.accent)

                                                                                                                                                                                                                                                                local nextUpdate = computer.uptime()

                                                                                                                                                                                                                                                                while not isHoleOpen() do
                                                                                                                                                                                                                                                                local now = computer.uptime()

                                                                                                                                                                                                                                                                if now >= nextUpdate then
                                                                                                                                                                                                                                                                if debugShowStatusEverySecond then
                                                                                                                                                                                                                                                                printStatus(sampleStatus())
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                nextUpdate = computer.uptime()
                                                                                                                                                                                                                                                                + math.max(0.05, tonumber(uiRefreshInterval) or 0.25)
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                os.sleep(0.1)
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                state.holeStart = computer.uptime()
                                                                                                                                                                                                                                                                state.stability = 100
                                                                                                                                                                                                                                                                state.stabilityTime = state.holeStart
                                                                                                                                                                                                                                                                state.spacetimeOn = false
                                                                                                                                                                                                                                                                state.spacetimeOnAt = nil
                                                                                                                                                                                                                                                                state.lastTank = getTankAmount()
                                                                                                                                                                                                                                                                state.flowLastTank = state.lastTank
                                                                                                                                                                                                                                                                state.flowLastAt = state.holeStart
                                                                                                                                                                                                                                                                state.flowDelta = nil
                                                                                                                                                                                                                                                                state.flowDisplay = "OFF"
                                                                                                                                                                                                                                                                state.lastActualStability = nil
                                                                                                                                                                                                                                                                state.lastActualTime = nil
                                                                                                                                                                                                                                                                state.actualSeen = false
                                                                                                                                                                                                                                                                state.fallbackLossStart = nil
                                                                                                                                                                                                                                                                state.fallbackLossStability = nil
                                                                                                                                                                                                                                                                state.expectedClosing = false
                                                                                                                                                                                                                                                                state.emergencyClosing = false
                                                                                                                                                                                                                                                                state.idleSince = nil
                                                                                                                                                                                                                                                                state.phase = "RUNNING"

                                                                                                                                                                                                                                                                emit("Utility hatch confirms Black Hole is open!", C.good)

                                                                                                                                                                                                                                                                if debugShowStatusEverySecond then
                                                                                                                                                                                                                                                                printStatus(sampleStatus())
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                local function adoptExternalBlackHole()
                                                                                                                                                                                                                                                                if not isHoleOpen() then
                                                                                                                                                                                                                                                                return false
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                local now = computer.uptime()

                                                                                                                                                                                                                                                                state.externalTakeover = true
                                                                                                                                                                                                                                                                state.phase = "EXTERNAL_TAKEOVER"
                                                                                                                                                                                                                                                                state.seedInsertedAt = now
                                                                                                                                                                                                                                                                state.holeStart = now
                                                                                                                                                                                                                                                                state.stability = 100
                                                                                                                                                                                                                                                                state.stabilityTime = now
                                                                                                                                                                                                                                                                state.spacetimeOn = getTX() >= 15
                                                                                                                                                                                                                                                                state.spacetimeOnAt = state.spacetimeOn and now or nil
                                                                                                                                                                                                                                                                state.lastTank = getTankAmount()
                                                                                                                                                                                                                                                                state.flowLastTank = state.lastTank
                                                                                                                                                                                                                                                                state.flowLastAt = now
                                                                                                                                                                                                                                                                state.flowDelta = nil
                                                                                                                                                                                                                                                                state.flowDisplay = state.spacetimeOn
                                                                                                                                                                                                                                                                and "ENABLED - WAITING FOR FLOW SAMPLE"
                                                                                                                                                                                                                                                                or "OFF"
                                                                                                                                                                                                                                                                state.lastActualStability = nil
                                                                                                                                                                                                                                                                state.lastActualTime = nil
                                                                                                                                                                                                                                                                state.actualSeen = false
                                                                                                                                                                                                                                                                state.fallbackLossStart = nil
                                                                                                                                                                                                                                                                state.fallbackLossStability = nil
                                                                                                                                                                                                                                                                state.expectedClosing = false
                                                                                                                                                                                                                                                                state.emergencyClosing = false
                                                                                                                                                                                                                                                                state.idleSince = nil

                                                                                                                                                                                                                                                                emit(
                                                                                                                                                                                                                                                                "BHC WARNING: An externally opened Black Hole was detected. Taking control without inserting a seed.",
                                                                                                                                                                                                                                                                C.warn
                                                                                                                                                                                                                                                                )

                                                                                                                                                                                                                                                                local initialSample = sampleStatus()
                                                                                                                                                                                                                                                                local protectionRequired = maxRuntime > 100 or voidProtection

                                                                                                                                                                                                                                                                if protectionRequired then
                                                                                                                                                                                                                                                                local available, _, readable, stockerAmounts = getTankInformation()
                                                                                                                                                                                                                                                                local remaining, needed, projectedRuntime = getSpacetimeRequirement(
                                                                                                                                                                                                                                                                available,
                                                                                                                                                                                                                                                                initialSample
                                                                                                                                                                                                                                                                )
                                                                                                                                                                                                                                                                local reserveOK, stockerBypass = acceptSpacetimeReserve(
                                                                                                                                                                                                                                                                remaining,
                                                                                                                                                                                                                                                                stockerAmounts,
                                                                                                                                                                                                                                                                readable
                                                                                                                                                                                                                                                                )

                                                                                                                                                                                                                                                                emit(string.format(
                                                                                                                                                                                                                                                                "BHC: External takeover requires %s L Spacetime through %ss (%s); available %s L.",
                                                                                                                                                                                                                                                                numberText(needed),
                                                                                                                                                                                                                                                                numberText(projectedRuntime),
                                                                                                                                                                                                                                                                formatDurationWords(projectedRuntime),
                                                                                                                                                                                                                                                                numberText(available)
                                                                                                                                                                                                                                                                ))

                                                                                                                                                                                                                                                                if readable == 0 then
                                                                                                                                                                                                                                                                emergencyClose(
                                                                                                                                                                                                                                                                initialSample,
                                                                                                                                                                                                                                                                "No Spacetime stocker can be read during external takeover."
                                                                                                                                                                                                                                                                )
                                                                                                                                                                                                                                                                return true
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                if stockerBypass then
                                                                                                                                                                                                                                                                noteLargeStockerBypass(needed, stockerAmounts)
                                                                                                                                                                                                                                                                elseif not reserveOK then
                                                                                                                                                                                                                                                                emergencyClose(
                                                                                                                                                                                                                                                                initialSample,
                                                                                                                                                                                                                                                                "Not enough Spacetime is available during external takeover; missing "
                                                                                                                                                                                                                                                                .. numberText(-remaining)
                                                                                                                                                                                                                                                                .. " L."
                                                                                                                                                                                                                                                                )
                                                                                                                                                                                                                                                                return true
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                if not state.spacetimeOn and not enableSpacetime() then
                                                                                                                                                                                                                                                                emergencyClose(
                                                                                                                                                                                                                                                                initialSample,
                                                                                                                                                                                                                                                                "Spacetime transmitter failed during external takeover."
                                                                                                                                                                                                                                                                )
                                                                                                                                                                                                                                                                return true
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                state.phase = "RUNNING"

                                                                                                                                                                                                                                                                while isHoleOpen()
                                                                                                                                                                                                                                                                and not state.expectedClosing
                                                                                                                                                                                                                                                                and not state.emergencyClosing do
                                                                                                                                                                                                                                                                local sample = sampleStatus()

                                                                                                                                                                                                                                                                if debugShowStatusEverySecond then
                                                                                                                                                                                                                                                                printStatus(sample)
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                if not checkEmergency(sample) then
                                                                                                                                                                                                                                                                return true
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                if protectionRequired and sample.recipeActive then
                                                                                                                                                                                                                                                                local available, _, readable, stockerAmounts = getTankInformation()
                                                                                                                                                                                                                                                                local remaining, needed = getSpacetimeRequirement(available, sample)
                                                                                                                                                                                                                                                                local reserveOK, stockerBypass = acceptSpacetimeReserve(
                                                                                                                                                                                                                                                                remaining,
                                                                                                                                                                                                                                                                stockerAmounts,
                                                                                                                                                                                                                                                                readable
                                                                                                                                                                                                                                                                )

                                                                                                                                                                                                                                                                if readable == 0 then
                                                                                                                                                                                                                                                                emergencyClose(
                                                                                                                                                                                                                                                                sample,
                                                                                                                                                                                                                                                                "Spacetime stockers became unreadable during external takeover."
                                                                                                                                                                                                                                                                )
                                                                                                                                                                                                                                                                return true
                                                                                                                                                                                                                                                                elseif stockerBypass then
                                                                                                                                                                                                                                                                noteLargeStockerBypass(needed, stockerAmounts)
                                                                                                                                                                                                                                                                elseif not reserveOK then
                                                                                                                                                                                                                                                                emergencyClose(
                                                                                                                                                                                                                                                                sample,
                                                                                                                                                                                                                                                                "Spacetime reserve became insufficient during external takeover."
                                                                                                                                                                                                                                                                )
                                                                                                                                                                                                                                                                return true
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                if not state.spacetimeOn and not enableSpacetime() then
                                                                                                                                                                                                                                                                emergencyClose(
                                                                                                                                                                                                                                                                sample,
                                                                                                                                                                                                                                                                "Spacetime transmitter failed during external takeover protection."
                                                                                                                                                                                                                                                                )
                                                                                                                                                                                                                                                                return true
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                if not checkIdleClose(sample) then
                                                                                                                                                                                                                                                                return true
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                if sample.elapsed >= maxRuntime and not sample.recipeActive then
                                                                                                                                                                                                                                                                normalClose(
                                                                                                                                                                                                                                                                "External takeover reached the configured runtime with no active recipe."
                                                                                                                                                                                                                                                                )
                                                                                                                                                                                                                                                                return true
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                os.sleep(math.max(0.05, tonumber(uiRefreshInterval) or 0.25))
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                if not isHoleOpen() and not state.expectedClosing then
                                                                                                                                                                                                                                                                unexpectedClosureReset()
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                return true
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                local function runCycle()
                                                                                                                                                                                                                                                                local available, tankDetails, readableStockers, stockerAmounts =
                                                                                                                                                                                                                                                                getTankInformation()

                                                                                                                                                                                                                                                                local remaining, needed, projectedRuntime = getSpacetimeRequirement(
                                                                                                                                                                                                                                                                available,
                                                                                                                                                                                                                                                                nil
                                                                                                                                                                                                                                                                )
                                                                                                                                                                                                                                                                local reserveOK, stockerBypass = acceptSpacetimeReserve(
                                                                                                                                                                                                                                                                remaining,
                                                                                                                                                                                                                                                                stockerAmounts,
                                                                                                                                                                                                                                                                readableStockers
                                                                                                                                                                                                                                                                )

                                                                                                                                                                                                                                                                emit("")
                                                                                                                                                                                                                                                                emit(
                                                                                                                                                                                                                                                                "BHC: Spacetime stockers: "
                                                                                                                                                                                                                                                                .. table.concat(tankDetails, " | ")
                                                                                                                                                                                                                                                                )

                                                                                                                                                                                                                                                                if readableStockers == 0 then
                                                                                                                                                                                                                                                                emit(
                                                                                                                                                                                                                                                                "BHC ERROR: No configured Spacetime stocker could be read by the transposer."
                                                                                                                                                                                                                                                                )

                                                                                                                                                                                                                                                                return
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                if stockerBypass then
                                                                                                                                                                                                                                                                noteLargeStockerBypass(needed, stockerAmounts)
                                                                                                                                                                                                                                                                elseif not reserveOK then
                                                                                                                                                                                                                                                                emit(
                                                                                                                                                                                                                                                                "BHC: Missing "
                                                                                                                                                                                                                                                                .. numberText(-remaining)
                                                                                                                                                                                                                                                                .. " L Spacetime!"
                                                                                                                                                                                                                                                                )

                                                                                                                                                                                                                                                                emit(
                                                                                                                                                                                                                                                                "BHC: Required "
                                                                                                                                                                                                                                                                .. numberText(needed)
                                                                                                                                                                                                                                                                .. " L | Available "
                                                                                                                                                                                                                                                                .. numberText(available)
                                                                                                                                                                                                                                                                .. " L"
                                                                                                                                                                                                                                                                )

                                                                                                                                                                                                                                                                return
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                emit(
                                                                                                                                                                                                                                                                "BHC: Target "
                                                                                                                                                                                                                                                                .. numberText(maxRuntime)
                                                                                                                                                                                                                                                                .. "s; protecting through at least "
                                                                                                                                                                                                                                                                .. numberText(projectedRuntime)
                                                                                                                                                                                                                                                                .. "s ("
                                                                                                                                                                                                                                                                .. formatDurationWords(projectedRuntime)
                                                                                                                                                                                                                                                                .. ") requires "
                                                                                                                                                                                                                                                                .. numberText(needed)
                                                                                                                                                                                                                                                                .. " L Spacetime."
                                                                                                                                                                                                                                                                )

                                                                                                                                                                                                                                                                emit(
                                                                                                                                                                                                                                                                "BHC: Available Spacetime: "
                                                                                                                                                                                                                                                                .. numberText(available)
                                                                                                                                                                                                                                                                .. " L"
                                                                                                                                                                                                                                                                )

                                                                                                                                                                                                                                                                emit(string.format(
                                                                                                                                                                                                                                                                "BHC: Emergency close threshold: %.1f%% Stability.",
                                                                                                                                                                                                                                                                emergencyCloseStability
                                                                                                                                                                                                                                                                ))

                                                                                                                                                                                                                                                                if closeWhenIdle and useCollapser then
                                                                                                                                                                                                                                                                emit(string.format(
                                                                                                                                                                                                                                                                "BHC: Idle close after %.1fs idle, never before %.1fs after seed insertion.",
                                                                                                                                                                                                                                                                math.max(0, tonumber(idleCloseSeconds) or 0),
                                                                                                                                                                                                                                                                math.max(0, tonumber(minimumRuntimeBeforeIdleClose) or 0)
                                                                                                                                                                                                                                                                ))
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                state.phase = "OPENING"
                                                                                                                                                                                                                                                                emit("BHC: Opening Black Hole!", C.accent)
                                                                                                                                                                                                                                                                enableController(true)

                                                                                                                                                                                                                                                                local moved = transposer.transferItem(
                                                                                                                                                                                                                                                                interfaceSide,
                                                                                                                                                                                                                                                                busSide,
                                                                                                                                                                                                                                                                1,
                                                                                                                                                                                                                                                                1
                                                                                                                                                                                                                                                                )

                                                                                                                                                                                                                                                                if not moved or moved == 0 then
                                                                                                                                                                                                                                                                emit(
                                                                                                                                                                                                                                                                "BHC ERROR: Failed to transfer Black Hole Seed!"
                                                                                                                                                                                                                                                                )

                                                                                                                                                                                                                                                                return
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                state.seedInsertedAt = computer.uptime()
                                                                                                                                                                                                                                                                waitForHoleOpen()

                                                                                                                                                                                                                                                                -- Always reach the configured injection stability first. Even when
                                                                                                                                                                                                                                                                -- maxRuntime is 100 seconds, void protection may need ST to keep a long
                                                                                                                                                                                                                                                                -- recipe alive beyond the free runtime window.
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

                                                                                                                                                                                                                                                                local shouldEnableSpacetime = maxRuntime > 100 or voidProtection

                                                                                                                                                                                                                                                                if shouldEnableSpacetime then
                                                                                                                                                                                                                                                                local currentAvailable, _, currentReadable, currentStockerAmounts =
                                                                                                                                                                                                                                                                getTankInformation()
                                                                                                                                                                                                                                                                local currentRemaining, currentNeeded, currentProjectedRuntime =
                                                                                                                                                                                                                                                                getSpacetimeRequirement(currentAvailable, beforeInjection)
                                                                                                                                                                                                                                                                local currentReserveOK, currentStockerBypass = acceptSpacetimeReserve(
                                                                                                                                                                                                                                                                currentRemaining,
                                                                                                                                                                                                                                                                currentStockerAmounts,
                                                                                                                                                                                                                                                                currentReadable
                                                                                                                                                                                                                                                                )

                                                                                                                                                                                                                                                                emit(string.format(
                                                                                                                                                                                                                                                                "BHC: Spacetime protection requires %s L for projected runtime %s; available %s L.",
                                                                                                                                                                                                                                                                numberText(currentNeeded),
                                                                                                                                                                                                                                                                numberText(currentProjectedRuntime)
                                                                                                                                                                                                                                                                .. " (" .. formatDurationWords(currentProjectedRuntime) .. ")",
                                                                                                                                                                                                                                                                numberText(currentAvailable)
                                                                                                                                                                                                                                                                ))

                                                                                                                                                                                                                                                                if currentStockerBypass then
                                                                                                                                                                                                                                                                noteLargeStockerBypass(currentNeeded, currentStockerAmounts)
                                                                                                                                                                                                                                                                elseif not currentReserveOK then
                                                                                                                                                                                                                                                                emergencyClose(
                                                                                                                                                                                                                                                                beforeInjection,
                                                                                                                                                                                                                                                                "Not enough Spacetime to protect the active recipe; missing "
                                                                                                                                                                                                                                                                .. numberText(-currentRemaining)
                                                                                                                                                                                                                                                                .. " L."
                                                                                                                                                                                                                                                                )
                                                                                                                                                                                                                                                                return
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                emit(string.format(
                                                                                                                                                                                                                                                                "BHC: Enabling Spacetime at approximately %.1f%% Stability!",
                                                                                                                                                                                                                                                                beforeInjection.stability or targetStability
                                                                                                                                                                                                                                                                ))

                                                                                                                                                                                                                                                                if not enableSpacetime() then
                                                                                                                                                                                                                                                                emergencyClose(
                                                                                                                                                                                                                                                                beforeInjection,
                                                                                                                                                                                                                                                                "Spacetime redstone output failed to turn on."
                                                                                                                                                                                                                                                                )
                                                                                                                                                                                                                                                                return
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                end

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
                                                                                                                                                                                                                                                                local timeNeeded = math.max(0, (maxProgress - progress) / 20)
                                                                                                                                                                                                                                                                local stability = shutdownSample.stability or targetStability
                                                                                                                                                                                                                                                                local extra = math.max(timeNeeded - stability + 1, 0)

                                                                                                                                                                                                                                                                if extra > 0 then
                                                                                                                                                                                                                                                                local currentAvailable, _, currentReadable, currentStockerAmounts =
                                                                                                                                                                                                                                                                getTankInformation()
                                                                                                                                                                                                                                                                local projectedSample = {
                                                                                                                                                                                                                                                                recipeActive = true,
                                                                                                                                                                                                                                                                maximum = maxProgress,
                                                                                                                                                                                                                                                                progress = progress,
                                                                                                                                                                                                                                                                stability = stability
                                                                                                                                                                                                                                                                }
                                                                                                                                                                                                                                                                local currentRemaining, currentNeeded, currentProjectedRuntime =
                                                                                                                                                                                                                                                                getSpacetimeRequirement(currentAvailable, projectedSample)
                                                                                                                                                                                                                                                                local currentReserveOK, currentStockerBypass = acceptSpacetimeReserve(
                                                                                                                                                                                                                                                                currentRemaining,
                                                                                                                                                                                                                                                                currentStockerAmounts,
                                                                                                                                                                                                                                                                currentReadable
                                                                                                                                                                                                                                                                )

                                                                                                                                                                                                                                                                emit(string.format(
                                                                                                                                                                                                                                                                "BHC: Void protection needs %.1f more seconds; projected Spacetime requirement is %s L through %s.",
                                                                                                                                                                                                                                                                extra,
                                                                                                                                                                                                                                                                numberText(currentNeeded),
                                                                                                                                                                                                                                                                numberText(currentProjectedRuntime)
                                                                                                                                                                                                                                                                .. " (" .. formatDurationWords(currentProjectedRuntime) .. ")"
                                                                                                                                                                                                                                                                ))

                                                                                                                                                                                                                                                                if currentStockerBypass then
                                                                                                                                                                                                                                                                noteLargeStockerBypass(currentNeeded, currentStockerAmounts)
                                                                                                                                                                                                                                                                elseif not currentReserveOK then
                                                                                                                                                                                                                                                                emergencyClose(
                                                                                                                                                                                                                                                                shutdownSample,
                                                                                                                                                                                                                                                                "Spacetime reserve is too low to finish the active recipe; missing "
                                                                                                                                                                                                                                                                .. numberText(-currentRemaining)
                                                                                                                                                                                                                                                                .. " L."
                                                                                                                                                                                                                                                                )
                                                                                                                                                                                                                                                                return
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                if not state.spacetimeOn then
                                                                                                                                                                                                                                                                if not enableSpacetime() then
                                                                                                                                                                                                                                                                emergencyClose(
                                                                                                                                                                                                                                                                shutdownSample,
                                                                                                                                                                                                                                                                "Spacetime redstone output failed during void protection."
                                                                                                                                                                                                                                                                )
                                                                                                                                                                                                                                                                return
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                if not statusSleep(extra) then
                                                                                                                                                                                                                                                                return
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                else
                                                                                                                                                                                                                                                                emit(
                                                                                                                                                                                                                                                                "BHC: Current recipe can finish inside the remaining stability window."
                                                                                                                                                                                                                                                                )
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                elseif voidProtection then
                                                                                                                                                                                                                                                                emit(
                                                                                                                                                                                                                                                                "BHC: No recipe active at shutdown; no additional protection time needed."
                                                                                                                                                                                                                                                                )
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                if not holeStillOpen() then
                                                                                                                                                                                                                                                                return
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                normalClose()
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                -- ================= QUOTES / SLEEP MODE ===================

                                                                                                                                                                                                                                                                local function printSleepMessage()
                                                                                                                                                                                                                                                                rotateQuoteIfDue(computer.uptime(), false)

                                                                                                                                                                                                                                                                local message = ui.lastSleepText or "BHC: No quote currently available."
                                                                                                                                                                                                                                                                local sample = sampleStatus()

                                                                                                                                                                                                                                                                if ui and ui.ready then
                                                                                                                                                                                                                                                                ui.draw(sample, message)
                                                                                                                                                                                                                                                                return
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                term.clear()
                                                                                                                                                                                                                                                                term.setCursor(1, 1)

                                                                                                                                                                                                                                                                local available, tankDetails, readableStockers = getTankInformation()

                                                                                                                                                                                                                                                                print("BHC: Available Spacetime: " .. numberText(available) .. " L")
                                                                                                                                                                                                                                                                print("BHC: Spacetime stockers: " .. table.concat(tankDetails, " | "))

                                                                                                                                                                                                                                                                if readableStockers == 0 then
                                                                                                                                                                                                                                                                print("BHC WARNING: No configured Spacetime stocker could be read.")
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                print(message)
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                local function sleepUntilRequested()
                                                                                                                                                                                                                                                                state.phase = "STANDBY"
                                                                                                                                                                                                                                                                printSleepMessage()

                                                                                                                                                                                                                                                                local nextMessage = computer.uptime()
                                                                                                                                                                                                                                                                + sleepMessageInterval

                                                                                                                                                                                                                                                                while redstone.getInput(receiverSide) <= 0 do
                                                                                                                                                                                                                                                                if isHoleOpen() then
                                                                                                                                                                                                                                                                return "EXTERNAL_HOLE"
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                if computer.uptime() >= nextMessage then
                                                                                                                                                                                                                                                                printSleepMessage()
                                                                                                                                                                                                                                                                nextMessage = computer.uptime()
                                                                                                                                                                                                                                                                + sleepMessageInterval
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                os.sleep(math.min(
                                                                                                                                                                                                                                                                1,
                                                                                                                                                                                                                                                                math.max(0.05, tonumber(uiRefreshInterval) or 0.25)
                                                                                                                                                                                                                                                                ))
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                return "REQUEST"
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                -- ======================== STARTUP =========================

                                                                                                                                                                                                                                                                math.randomseed(math.floor(computer.uptime() * 1000))
                                                                                                                                                                                                                                                                math.random()
                                                                                                                                                                                                                                                                math.random()
                                                                                                                                                                                                                                                                math.random()

                                                                                                                                                                                                                                                                if not isHoleOpen() then
                                                                                                                                                                                                                                                                redstone.setOutput(transmitterSide, 0)
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                enableController(true)
                                                                                                                                                                                                                                                                resetState()
                                                                                                                                                                                                                                                                ui.init()

                                                                                                                                                                                                                                                                if ui and ui.ready then
                                                                                                                                                                                                                                                                ui.log("Dashboard initialized.", C.accent)
                                                                                                                                                                                                                                                                ui.status(sampleStatus())
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                if closeWhenIdle then
                                                                                                                                                                                                                                                                if useCollapser then
                                                                                                                                                                                                                                                                emit(string.format(
                                                                                                                                                                                                                                                                "BHC: Early idle close enabled after %.1f seconds without a recipe, but never before %.1f seconds after seed insertion.",
                                                                                                                                                                                                                                                                math.max(0, tonumber(idleCloseSeconds) or 0),
                                                                                                                                                                                                                                                                math.max(0, tonumber(minimumRuntimeBeforeIdleClose) or 0)
                                                                                                                                                                                                                                                                ))
                                                                                                                                                                                                                                                                else
                                                                                                                                                                                                                                                                emit(
                                                                                                                                                                                                                                                                "BHC WARNING: Idle close is enabled, but useCollapser is false."
                                                                                                                                                                                                                                                                )
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                while true do
                                                                                                                                                                                                                                                                if isHoleOpen() and state.phase == "STANDBY" then
                                                                                                                                                                                                                                                                adoptExternalBlackHole()
                                                                                                                                                                                                                                                                elseif redstone.getInput(receiverSide) > 0 then
                                                                                                                                                                                                                                                                if transposer.getStackInSlot(interfaceSide, 1) == nil then
                                                                                                                                                                                                                                                                emit("BHC: No Seeds Available!")
                                                                                                                                                                                                                                                                elseif useCollapser
                                                                                                                                                                                                                                                                and transposer.getStackInSlot(interfaceSide, 2) == nil then
                                                                                                                                                                                                                                                                emit("BHC: No Collapsers Available!")
                                                                                                                                                                                                                                                                else
                                                                                                                                                                                                                                                                runCycle()
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                os.sleep(3)
                                                                                                                                                                                                                                                                else
                                                                                                                                                                                                                                                                sleepUntilRequested()
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                end
