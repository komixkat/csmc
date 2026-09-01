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

Run these in the server console (the terminal running `start.sh`), or in-game in chat as an operator with `operator` permission. `/function` works from both.

Race start. Everyone goes to survival and the hold is disabled:

```bash
/function csmc_hold:release
```

Back to adventure for the next race:

```bash
/function csmc_hold:arm
```

PvP is on by default. Flags:

```bash
./start.sh --no-whitelist
```

Whitelist off (default).

```bash
./start.sh --whitelist
```

Whitelist on.

```bash
./start.sh --offline
```

online-mode=false (default).

```bash
./start.sh --online
```

online-mode=true.

```bash
./start.sh --help
```

Show usage.

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
- `server/world/datapacks/csmc_hold/` - the spawn-hold datapack, created by setup
- `server/event/config/event.json` - event settings (seed, memory, view distance)
- `start.sh` - shortcut to start the server, created by setup