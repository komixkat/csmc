# Co-op Minecraft Speedrun

One-command Linux setup for a private Fabric speedrun server with server-side performance mods. Works on any Linux (apt, dnf, pacman, or zypper). All paths are derived from the script location, so you can clone and run this anywhere.

## Setup

```bash
cd scripts
./setup.sh
```

It will ask you to pick a Minecraft version (1.16.1 or latest), generate a random seed and open it on ChunkBase for approval, then download a local Java, Fabric, Fabric API, and compatible performance mods into `server/`. The first launch generates the world from the approved seed.

Players spawn at the natural world spawn in adventure mode with a small world border around it, so nobody can wander off. Expand the border for a race with `/worldborder set <diameter>` in the server console.

Optional overrides (pass as env vars):

```bash
MC_VERSION=1.16.1 EVENT_SEED=123 JAVA_MEMORY=14G VIEW_DISTANCE=16 MAX_PLAYERS=30 ./setup.sh
```

## Run the server

```bash
./start.sh
```

The connect address (IP:25565) is printed on each start. Flags:

```bash
./start.sh --no-whitelist   # force whitelist off
./start.sh --whitelist      # turn whitelist on
./start.sh --offline        # online-mode=false
./start.sh --online         # online-mode=true
./start.sh --help
```

Whitelist and online-mode are off by default.

## Reset the world

```bash
cd scripts
./reset.sh
```

Moves the current world to `backups/` and starts fresh, so the server generates a new world from the same seed on the next start.

## Remove everything

```bash
cd scripts
./reset.sh
rm -rf ../server ../backups ../start.sh
```

Or delete the whole folder. Nothing is installed outside it.

## Layout

- `scripts/setup.sh` - installs the server
- `scripts/reset.sh` - regenerates the world from the seed
- `server/` - the Minecraft server (Java, Fabric, mods, world, config), created by setup
- `start.sh` - shortcut to start the server, created by setup