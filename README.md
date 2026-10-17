# cc-cannon-test

Test and calibrate a Create Radar turret from ComputerCraft (CMP pack: Create Radar 0.4.9.4, Create Big Cannons, CC:Tweaked 1.120).

## Install

```
wget https://raw.githubusercontent.com/levisnakes/cc-cannon-test/main/cannon_test.lua cannon_test.lua
cannon_test
```

## Build

1. **Cannon mount** with the cannon on it.
2. **Auto Yaw Controller** under the mount. Feed it rotation (shaft from your power).
3. **Auto Pitch Controller** on the side of the mount. Feed it rotation too.
4. **Fire Controller** touching the mount.
5. A **wired modem** on each controller (right-click to connect), cabled to the computer. Optional: the radar bearing on the same cable.

You don't need Data Links or a Network Controller for CC control.

## Commands

| | |
|---|---|
| `status` | what's connected |
| `yaw <deg>` / `pitch <deg>` / `aim <yaw> <pitch>` | point the cannon |
| `sweep` | steps through yaw 0/90/180/270 and pitch 0-45 so you can see which way is which |
| `arm` / `safe` | firing is blocked until `arm` |
| `fire` | one shot |
| `burst <sec>` | hold the trigger (max 10s, any key stops) |
| `stop` | cease fire and release the controllers |
| `pos x y z` / `pos gps` | cannon position, needed for aiming at radar contacts |
| `yawoff` `yawflip` `pitchoff` `pitchflip` | calibration, saved to `cannon.cfg` |
| `tracks` / `aimat <n>` | list radar contacts by distance, point straight at one |

`aimat` assumes Minecraft yaw (0 = south, 90 = west, 180 = north, 270 = east) and aims in a straight line with no shell drop. Use `sweep`, then `yawoff`/`yawflip` until `aimat` points the right way.

The Fire Controller switches itself off 0.5s after the last command, so `burst` repeats `keepFiring()` every 0.25s.
