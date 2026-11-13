# Black Hole Compressor automation for GTNH

[`bhc.lua`](bhc.lua) automates a GregTech Black Hole Compressor through OpenComputers/OpenOS. It was written for GTNH 2.9

It inserts a seed on a redstone request, watches the Black Hole Utility Hatch, controls Spacetime supply, and closes the hole with a collapser. It includes a dashboard, event log, rotating quotes, reserve checks, emergency closure, and takeover of an already-open hole.

**Prepare the machine and recipe inputs before requesting a cycle.** The script does not validate recipe inputs or available power before inserting a seed. Use the request lever to hold automation idle while preparing inputs such as MHDCSM superdense plates.

## Hardware

Recommended computer setup:

- Tier 3 computer case, screen, keyboard, and Tier 3 APU.
- Tier 3.5 memory, Tier 3 hard drive, Lua BIOS EEPROM, and an OpenOS installation disk.
- Adapter connected to the BHC controller: sneak-right-click the controller with an MFU, then put the MFU in the adapter.
- Redstone I/O and a transposer, with a regular BHC input bus accessible to the transposer.
- A Black Hole Utility Hatch in **STATIC MODE**, required for open/closed detection even when using collapsers.
- A wireless receiver for cycle requests and a wireless transmitter controlling Spacetime supply.
- A powered fluid subnetwork supplying the BHC's Spacetime input hatch.

The computer must expose `gt_machine`, `redstone`, and `transposer` components. The dashboard uses a GPU. If the GPU is missing or rendering fails, status output falls back to the console.

### Default sides

Edit the configuration near the top of `bhc.lua` to match your build. Redstone sides apply to the Redstone I/O; inventory and stocker sides apply to the transposer.

| Setting | Default | Connection |
| --- | --- | --- |
| `receiverSide` | `sides.north` | Request input; a signal above 0 requests a cycle. |
| `transmitterSide` | `sides.south` | Spacetime output; 15 enables supply, 0 disables it. |
| `hatchSide` | `sides.down` | Utility Hatch input; a signal above 0 means the hole is open. |
| `interfaceSide` | `sides.south` | ME interface holding seeds and collapsers. |
| `busSide` | `sides.down` | BHC input bus receiving seeds and collapsers. |
| `stockers` | One entry at `sides.up` | Super stock replenisher holding the Spacetime reserve. |

**Electrically isolate the hatch signal, request signal, and Spacetime transmitter.** Redstone leaking from the Utility Hatch can power the transmitter independently of the script. If the dashboard shows `Transmitter 0` while Spacetime flows, check for another redstone path or supply source.

### ME interface and Spacetime supply

1. Keep seeds in ME interface **slot 1** and Black Hole Collapsers in **slot 2**. The script transfers one item at a time from these slots.
2. Place one super stock replenisher above the transposer. Install a suitable fluid storage cell and configure its Spacetime reserve.
3. Place a fluid storage bus on the replenisher, set to **EXTRACT ONLY**, connected to the BHC's fluid subnetwork. Power that subnetwork; the original build uses a neutronium energy anchor.
4. Connect the interface and replenisher to the main resource network. Configure the transmitter's receiving circuit to enable Spacetime supply on command.

One replenisher is sufficient. Additional reserves can be listed in `stockers`; the script adds their reported amounts. It reads tank 1 on each configured side. Size the supply for your seed and intended runtime.

## Supported seeds

| Seed in slot 1 | Registry name | Metadata | Starting Spacetime cost |
| --- | --- | --- | --- |
| Black Hole Seed | `gregtech:gt.metaitem.01` | `32418` | 1 L/s |
| Supermassive Black Hole Seed | `gregtech:gt.metaitem.01` | `32421` | 64 L/s |

Detection uses registry name and metadata, so renamed or localized labels do not affect it. Other items, including the Black Hole Stabilizer, are rejected. Rejections log the reported item name, metadata, and label.

Both seeds use the same control sequence. The reserve calculation doubles Spacetime cost every 30 seconds of calculated feeding and applies the selected seed's starting cost.

## Cycle behavior

1. **Standby:** wait for a request signal. With `useCollapser = true`, both a seed and a collapser must be present before starting. A request that remains high can trigger another cycle after closure.
2. **Reserve check:** identify the seed and check Spacetime reserves. Unreadable or insufficient reserves prevent seed insertion, subject to the override below.
3. **Opening:** enable the controller, transfer one seed from slot 1 to the input bus, and wait for the Utility Hatch to report an open hole.
4. **Initial decay:** wait `max(100 - targetStability, 0)` seconds after the hatch reports open. The default target of 18% gives an **82-second wait**. Emergency and idle checks continue during this wait.
5. **Injection:** if `maxRuntime > 100` or void protection is enabled, recheck reserves and command Spacetime output 15. Read back the transmitter output and retry once if needed.
6. **Extension:** wait another `max(maxRuntime - 100, 0)` seconds, then evaluate additional protection time for an active recipe.
7. **Closure:** when the holding stage finishes, insert a collapser from slot 2, wait for the hatch to report closed, turn Spacetime off, and return to standby. Safety or idle checks can close the hole earlier.

The initial injection delay is **timer-based**, not a live “wait until actual stability reaches 18%” condition. Actual stability is used for monitoring and emergency checks when readable; otherwise the script estimates it.

`maxRuntime` controls reserve projections and the extension calculation; it is not an exact elapsed-time shutdown deadline. With the default `maxRuntime = 100`, no timed extension follows injection. If no additional recipe protection is needed, closure can start around 82 seconds after opening. The 100-second minimum idle setting applies only to the separate idle-close check.

### Reserve checks and the >1G override

The calculation budgets feeding beyond a nominal 100-second natural stability window. With void protection enabled, it budgets at least one second of feeding even when `maxRuntime = 100`, and can project additional time from an active recipe's remaining progress.

- At least one configured stocker must be readable.
- A reserve covering the calculated requirement is accepted.
- A readable total **above 1,000,000,000 L** is also accepted when the calculated requirement is higher.
- **Exactly 1G does not trigger the override.** At or below that amount, the calculated requirement must be covered.

The override applies to startup and protection checks. It trusts the refill setup because reported reserves can be clamped; it does not guarantee unlimited supply or runtime. Reserve acceptance alone does not enable Spacetime—the cycle must reach its injection stage.

### Already-open holes

When the hatch reports an open hole during standby, the script takes control without inserting a seed. The consumed seed cannot be identified from interface slot 1, so it budgets the supermassive starting cost of 64 L/s.

With the default protection settings, takeover can enable Spacetime **immediately** after checking reserves. It does not perform the fresh-seed 82-second wait. Elapsed time starts at takeover; the hole's previous age and feeding history are not recovered.

## Safety behavior and limits

- **Emergency stability:** actual or estimated stability at or below 10% triggers emergency closure during monitoring.
- **Idle closure:** with idle closure and collapsers enabled, an inactive recipe can trigger closure after 10 seconds idle, but not before 100 seconds from seed insertion or takeover.
- **Void protection:** uses recipe progress and remaining stability to calculate additional holding time, rechecks reserves, and enables Spacetime when needed. This is a timing-based protection attempt, not a guarantee against every recipe or supply failure.
- **Lost hatch signal:** an unexpected closed reading must remain closed for 5 seconds before state resets. A returning signal cancels confirmation.
- **Collapser failure:** transfer retries run for up to 5 seconds. If no collapser can close the hole, the script turns Spacetime off and attempts to disable the controller for 15.1 minutes (906 seconds). It then re-enables the controller, waits 1 second, and checks the hatch. If closure is not confirmed, it repeats the fallback cycle.

Press **Ctrl+Alt+C** to interrupt the program. There is no shutdown handler guaranteeing that interruption resets the controller or transmitter. Inspect the machine and redstone state afterward.

## Configuration

Edit these values in the configuration block at the top of `bhc.lua`.

| Setting | Default | Purpose |
| --- | --- | --- |
| `maxRuntime` | `100` | Reserve projection and timed extension parameter; see the timing notes above. |
| `targetStability` | `18` | Sets the initial delay to `100 - targetStability` seconds. |
| `emergencyCloseStability` | `10` | Emergency stability threshold in percent. |
| `useCollapser` | `true` | Require and use slot 2 collapsers. Disabling this uses timed fallback closure. |
| `voidProtection` | `true` | Budget and attempt extra holding time for active recipes. |
| `closeWhenIdle` | `true` | Enable the separate idle-close check. |
| `idleCloseSeconds` | `10` | Required idle time for idle closure. |
| `minimumRuntimeBeforeIdleClose` | `100` | Minimum elapsed time before idle closure. |
| `minimumReserveToForceStart` | `1000000000` | Strictly-above threshold for the reserve override. |
| `manualCloseConfirmSeconds` | `5` | Confirmation period for unexpected hatch closure. |
| `collapserInsertTimeoutSeconds` | `5` | Collapser transfer retry timeout. |
| `emergencyControllerOffSeconds` | `15.1 * 60` | Controller-off period during fallback. |
| `emergencyControllerVerifyDelaySeconds` | `1` | Delay before checking closure after controller re-enable. |
| `uiEnabled` | `true` | Enable the dashboard. |
| `uiUseMaximumResolution` | `true` | Request the GPU's maximum resolution. |
| `uiRefreshInterval` | `0.25` | Dashboard and monitoring interval in seconds. |
| `flowRefreshInterval` | `1` | Interval for calculating flow from reserve changes. |
| `uiMaxStoredLogLines` | `40` | Maximum stored event log entries. |
| `sleepMessageInterval` | `15` | Quote rotation interval during standby and active cycles. |
| `debugShowStatusEverySecond` | `true` | Keep status updates enabled; refresh timing uses `uiRefreshInterval`. |

The dashboard uses a full layout at resolutions of at least 100×35 and a compact layout otherwise. It shows stability, recipe progress, runtime, reserves, flow, transmitter output, quotes, and recent events. Flow is inferred from reserve changes, so replenishment affects the displayed rate.

## Install and run

1. Boot the OpenComputers computer and install OpenOS using `install`, following its prompts.
2. Copy the **raw contents** of [`bhc.lua`](bhc.lua) into `/home/bhc.lua`. With `edit bhc.lua`, save using Ctrl+S and exit using Ctrl+W. Do not include Markdown fences or an HTML download page.
3. Set the sides, stocker list, and other configuration values for your machine.
4. Check the hatch's static signal and isolate the request and transmitter circuits. Prepare inputs, seeds, collapsers, and Spacetime supply.
5. Run `bhc` from `/home`, then apply the request signal when ready.


Original build and script direction: Kahlui/Zach, with GPT assistance. The original README credited GPT 5.6. The author also linked an external [Spacetime calculator](https://www.desmos.com/calculator/yrnt694v3h), which is not part of this repository.


