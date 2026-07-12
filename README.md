Full featured BHC Automation. Pull lever to ensure idle before sending MHDCSM Superdense plates. No checks are made at start of recipe

Automation is verry verry simular to what is on the wiki as of 7/10/26

Inside the BHC, place a screen (Tier 3), computer case (Tier 3), keyboard, adapter, redstone I/O, transposer (any tier), and neutronium energy cell. Sneak right-click the controller with an MFU and insert it into the adapter to wirelessly connect to the machine.
Insert the bare minimum components into the computer case. These could be even lower tier but there is no reason not to use the best components.

APU (Tier 3)
Memory (Tier 3.5)
Hard Disk Drive (Tier 3)
EEPROM (Lua BIOS)
OpenOS Floppy Disk
Place a wireless receiver and wireless transmitter facing into the redstone I/O, and a regular input bus underneath the transposer. The sides are configurable.



Place a super stock replenisher above the transposer. Insert a high-capacity fluid storage cell and filter it to a reasonable amount of spacetime. For example, if the BHC is never going to run longer than 200s, then 500L of Spacetime is enough.
Place a fluid storage bus set to EXTRACT ONLY on the side of the super stock replenisher. Connect the fluid storage bus to the fluid subnetwork (light blue). Power the subnetwork with a neutronium energy anchor.

Place an ME interface next to the transposer with black hole seeds in the first slot and black hole collapsers in the second slot. Connect the ME interface and super stock replenisher to the main network (green).

Required, place a black hole utility hatch set to STATIC MODE underneath the redstone I/O

Place a super stock replenisher above the transposer. Insert a high-capacity fluid storage cell and filter it to a reasonable amount of spacetime. For example, if the BHC is never going to run longer than 200s, then 500L of Spacetime is enough.
Place a fluid storage bus set to EXTRACT ONLY on the side of the super stock replenisher. Connect the fluid storage bus to the fluid subnetwork (light blue). Power the subnetwork with a neutronium energy anchor.

Place an ME interface next to the transposer with black hole seeds in the first slot and black hole collapsers in the second slot. Connect the ME interface and super stock replenisher to the main network (green).

Optionally, place a black hole utility hatch set to STATIC MODE underneath the redstone I/O if NOT using black hole collapsers. This helps track the 15 minute decay.

Place a super stock replenisher above the transposer. Insert a high-capacity fluid storage cell and filter it to a reasonable amount of spacetime. For example, if the BHC is never going to run longer than 200s, then 500L of Spacetime is enough.
Place a fluid storage bus set to EXTRACT ONLY on the side of the super stock replenisher. Connect the fluid storage bus to the fluid subnetwork (light blue). Power the subnetwork with a neutronium energy anchor.

Place an ME interface next to the transposer with black hole seeds in the first slot and black hole collapsers in the second slot. Connect the ME interface and super stock replenisher to the main network (green).

Optionally, place a black hole utility hatch set to STATIC MODE underneath the redstone I/O if NOT using black hole collapsers. This helps track the 15 minute decay.

After booting up the computer, follow the commands on screen to install OpenOS.
install → Y → Y

Create a new script by typing edit bhc.lua. The name is not important. Copy the code below into the script. Use middle-click to paste.

Edit the config as necessary. Press CTRL+S to save and CTRL+W to exit. Use the same edit command to change the code at anytime.

Launch the script by typing bhc. It automatically detects when items enter the bhc subnetwork (blue) and runs through the different phases of the black hole. Press CTRL+ALT+C to stop the script at any time



See Pictures inside repository for refrences to what it should look like. Code prompted by Kahlui/Zach Writen by GPT 5.6
Usefull tool. NOT WRITEN BY ME https://www.desmos.com/calculator/yrnt694v3h


