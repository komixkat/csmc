# Co-op Minecraft Speedrun

One-command Linux setup for a private Fabric speedrun server with performance mods. Works on any Linux (apt, dnf, pacman, zypper). Clone and run anywhere.

## Install

```bash
cd scripts
./setup.sh
```

Picks a Minecraft version and patch (or `latest`), generates a seed for approval, downloads Java, Fabric, and the mods, then generates the world. Optional overrides:

```bash
MC_VERSION=1.16.1 EVENT_SEED=123 JAVA_MEMORY=14G VIEW_DISTANCE=16 MAX_PLAYERS=30 ./setup.sh
```

## Play

```bash
./start.sh
```

Players are held at spawn in adventure mode by the `csmc_hold` datapack until the race starts.

The commands below run from the server console (the terminal running `start.sh`) or in-game in chat as an operator with `operator` permission. `/function` works from both.

### Race start

```bash
/function csmc_hold:release
```

Everyone switches to survival, the hold is disabled, the time of day resets to day start, and the race timer starts with a message.

### Next race

```bash
/function csmc_hold:arm
```

Back to adventure mode for the next race. The timer stops and resets to zero.

### Timer

A gold, width-fixed `h:m:s.cs` timer shows on the action bar while the race runs. It starts on `release` and resets to zero on `arm`.

## Server flags

| Flag | Effect |
|---|---|
| `--whitelist` / `--no-whitelist` | Whitelist on / off (default off) |
| `--online` / `--offline` | online-mode true / false (default false) |
| `--help` | Show usage |

## Reset

```bash
cd scripts
./reset.sh
```

Moves `server/` to `backups/` and clears the `start.sh` shortcut.

## Remove everything

```bash
cd scripts
./reset.sh
rm -rf ../backups
```

## Layout

- `scripts/setup.sh` - installs the server
- `scripts/reset.sh` - wipes the server into `backups/`
- `server/` - the server (Java, Fabric, mods, world, config), created by setup
- `server/world/datapacks/csmc_hold/` - the spawn-hold datapack and race timer, created by setup
- `server/event/config/event.json` - event settings (seed, memory, view distance)
- `start.sh` - shortcut to start the server, created by setup