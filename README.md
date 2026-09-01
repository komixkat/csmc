# Co-op Minecraft Speedrun

One-command Linux setup for a private Fabric speedrun server with server-side performance mods. Works on any Linux (apt, dnf, pacman, or zypper). All paths are derived from the script location, so you can clone and run this anywhere.

## Setup

```bash
cd scripts
./setup.sh
```

Version selection is two-step: first pick a major version (every major.minor with a Fabric-compatible build, sorted newest first with its release name, e.g. "1.16 - Nether Update"), then pick a specific patch release within it (e.g. 1.16.5 vs 1.16.1), or pick `latest`. Then it generates a random seed and opens it on ChunkBase for approval, downloads the correct local Java (read from Mojang data, with a built-in fallback table), Fabric, and compatible performance mods into `server/`. The first launch generates the world from the approved seed.

The setup needs adventure mode and the world border. Adventure mode arrived in 1.4.2 and the world border in 1.9, but Fabric requires 1.14.4+, so every version offered on the first screen supports all gameplay used here. The enderdragon and blaze rods exist in every version back to 1.0.

Players spawn at the natural world spawn in adventure mode with a small world border around it, so nobody can wander off before the race begins. The border, game mode, timer, and pvp are controlled by the operator from the server console (see below).

Optional overrides (pass as env vars):

```bash
MC_VERSION=1.16.1 EVENT_SEED=123 JAVA_MEMORY=14G VIEW_DISTANCE=16 MAX_PLAYERS=30 ./setup.sh
```

## Run the server

```bash
./start.sh
```

The connect address (IP:25565) and the world spawn coordinates are printed before the server boots. Once the console prints `Done`, type commands directly into the server terminal. Wait about 5 seconds after `Done` before sending border commands; sent too early they can fail with "An unexpected error occurred trying to execute that command" (just retype them).

The warmup border is 10 blocks and the race border is 60000000 (the vanilla race edge), both configurable in `server/event/config/event.json`.

### Before each race (warmup)

```bash
/worldborder center <sx> <sz>     # sx sz are the printed world spawn coordinates
/worldborder set 10               # tiny warmup wall around spawn
/gamemode adventure @a
```

### Race start

```bash
/worldborder set 60000000         # lift the border to the race edge
/gamemode survival @a
/scoreboard objectives add speedrun_time dummy
/scoreboard objectives setdisplay sidebar speedrun_time   # live timer in the sidebar
```

Update the timer as the race goes on with `/scoreboard players set __race__ speedrun_time 123` (player name comes first, then the objective). First notable achievements appear in the console as "has made the advancement [...]" lines; the operator can call them out or write them down.

### Race end

```bash
/scoreboard objectives remove speedrun_time
```

### pvp

`pvp` is a `server.properties` setting read at boot, so enabling it mid-session needs a restart. Either set `pvp=true` in `server.properties` before starting, or type `stop`, then start again with `./start.sh`. PvP is off by default.

Flags:

```bash
./start.sh --no-whitelist   # force whitelist off
./start.sh --whitelist      # turn whitelist on
./start.sh --offline        # online-mode=false
./start.sh --online         # online-mode=true
./start.sh --help
```

Whitelist and online-mode are off by default.

## Reset

```bash
cd scripts
./reset.sh
```

Moves the entire `server/` folder (Java, Fabric, mods, world, config) to `backups/` and removes the `start.sh` shortcut, leaving the repo clean. Then install a fresh server:

```bash
./setup.sh
```

## Remove everything

```bash
cd scripts
./reset.sh
rm -rf ../backups
```

Or delete the whole folder. Nothing is installed outside it.

## Layout

- `scripts/setup.sh` - installs the server
- `scripts/reset.sh` - wipes the server into `backups/` for a clean reinstall
- `server/` - the Minecraft server (Java, Fabric, mods, world, config), created by setup
- `server/event/config/event.json` - event settings (seed, border sizes, memory, view distance)
- `start.sh` - shortcut to start the server, created by setup