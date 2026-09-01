# Co-op Minecraft Speedrun

One-command Linux setup for a private Fabric speedrun server with server-side performance mods. Works on any Linux (apt, dnf, pacman, or zypper). All paths are derived from the script location, so you can clone and run this anywhere.

## Setup

```bash
cd scripts
./setup.sh
```

Version selection is two-step: first pick a major version (every major.minor with a Fabric-compatible build, sorted newest first with its release name, e.g. "1.16 - Nether Update"), then pick a specific patch release within it (e.g. 1.16.5 vs 1.16.1), or pick `latest`. Then it generates a random seed and opens it on ChunkBase for approval, downloads the correct local Java (read from Mojang data, with a built-in fallback table), Fabric, and compatible performance mods into `server/`. The first launch generates the world from the approved seed.

The setup needs adventure mode and the world border. Adventure mode arrived in 1.4.2 and the world border in 1.9, but Fabric requires 1.14.4+, so every version offered on the first screen supports all gameplay used here. The enderdragon and blaze rods exist in every version back to 1.0.

Players spawn at the natural world spawn in adventure mode with a small 10-block world border around it, so nobody can wander off before the race begins. Typing `/speedrun start` in the server console lifts the border, enables pvp, and switches everyone to survival.

Optional overrides (pass as env vars):

```bash
MC_VERSION=1.16.1 EVENT_SEED=123 JAVA_MEMORY=14G VIEW_DISTANCE=16 MAX_PLAYERS=30 ./setup.sh
```

## Run the server

```bash
./start.sh
```

The connect address (IP:25565) is printed on each start. Once the server is up, a 10-block world border appears centered on the spawn point. In the server terminal you can run:

```bash
/speedrun start    # begin the speedrun: border to race size, enable pvp, set survival, start the timer scoreboard and achievement log
/speedrun status   # show elapsed time and notable achievements so far
/speedrun end      # stop the timer and close out the race
```

`/speedrun start` opens a `speedrun_time` scoreboard (seconds since start) on the side of the screen, and logs the first notable achievements to `event/results/achievements.txt`. Race totals are written to `event/results/races.txt`.

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
- `server/event/results/` - speedrun logs (races.txt, achievements.txt)
- `start.sh` - shortcut to start the server, created by setup