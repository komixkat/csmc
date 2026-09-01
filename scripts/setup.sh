#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
SERVER_DIR="${SERVER_DIR:-$BASE_DIR/server}"

log() { printf "\033[1;34m[SETUP]\033[0m %s\n" "$1" >&2; }
warn() { printf "\033[1;33m[WARN]\033[0m %s\n" "$1" >&2; }
die() { printf "\033[1;31m[ERROR]\033[0m %s\n" "$1" >&2; exit 1; }
ok() { printf "\033[1;32m[OK]\033[0m %s\n" "$1" >&2; }

separator() { echo "=============================================="; }
wide_separator() { echo "================================================"; }

local_ip() {
    ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    if [ -z "$ip" ] && command -v ip >/dev/null 2>&1; then
        ip=$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K[0-9.]+' | head -n 1)
    fi
    if [ -z "$ip" ] && command -v ip >/dev/null 2>&1; then
        ip=$(ip -4 addr show scope global 2>/dev/null | grep -oP 'inet \K[0-9.]+' | head -n 1)
    fi
    [ -n "$ip" ] && printf '%s\n' "$ip" || printf '%s\n' "your-ip-here"
}

select_version() {
    local version="${MC_VERSION:-}"
    if [ -n "$version" ]; then
        echo "$version"
        return 0
    fi

    local latest_hint=""
    latest_hint=$(fetch_latest_mc)
    [ -n "$latest_hint" ] || latest_hint="unknown (offline)"

    while true; do
        wide_separator >&2
        echo "  Minecraft Co-op Speedrun - Server Setup" >&2
        wide_separator >&2
        echo "" >&2
        echo "  Select Minecraft version:" >&2
        echo "" >&2
        echo "    1) 1.16.1  (stable, easy)" >&2
        echo "    2) latest  (currently $latest_hint)" >&2
        echo "" >&2
        printf "  Enter choice [1/2]: " >&2
        read -r choice || {
            echo "" >&2
            warn "No input received, aborting setup"
            return 1
        }
        echo "" >&2

        case "$choice" in
            1) echo "1.16.1"; return 0 ;;
            2) echo "latest"; return 0 ;;
            *) warn "Invalid choice: $choice" ;;
        esac
    done
}

fetch_latest_mc() {
    curl -fsSL --max-time 10 \
        "https://launchermeta.mojang.com/mc/game/version_manifest_v2.json" 2>/dev/null \
        | grep -oP '"latest":\s*\{[^}]*"release":\s*"\K[^"]+' | head -n 1 || true
}

resolve_latest_version() {
    log "Fetching latest Minecraft version from Mojang..."
    local latest
    latest=$(fetch_latest_mc)
    [ -n "$latest" ] || die "Failed to fetch the latest Minecraft version"
    log "Latest Minecraft version: $latest"
    echo "$latest"
}

java_version_for_mc() {
    local mc="$1"
    local major
    major=$(echo "$mc" | cut -d. -f1)
    if [ "$major" -ge 2 ] 2>/dev/null; then
        echo 25
    elif [ "$major" -eq 1 ] 2>/dev/null; then
        local minor
        minor=$(echo "$mc" | cut -d. -f2)
        if [ "$minor" -ge 21 ] 2>/dev/null; then
            echo 21
        elif [ "$minor" -ge 17 ] 2>/dev/null; then
            echo 17
        else
            echo 8
        fi
    else
        echo 25
    fi
}

java_major() {
    local out
    out=$("$1" -version 2>&1)
    if echo "$out" | grep -q '"1\.8\.'; then
        echo 8
        return
    fi
    echo "$out" | grep -oP '"\K[0-9]+' | head -n 1
}

find_java() {
    local required_version="$1"
    local java_dir="$SERVER_DIR/java"

    if [ -d "$java_dir" ]; then
        local candidate
        local matched=""
        for candidate in $(find "$java_dir" -maxdepth 3 -name "java" -path "*/bin/java" 2>/dev/null); do
            local actual
            actual=$(java_major "$candidate")
            if [ "$actual" = "$required_version" ]; then
                matched=$(dirname "$(dirname "$candidate")")
                break
            fi
        done
        if [ -n "$matched" ]; then
            echo "$matched"
            return 0
        fi
    fi

    if command -v java >/dev/null 2>&1; then
        local sys_ver
        sys_ver=$(java_major "$(command -v java)")
        if [ "$sys_ver" = "$required_version" ]; then
            echo ""
            return 0
        fi
    fi

    return 1
}

download_java() {
    local version="$1"
    local target_dir="$SERVER_DIR/java/jdk-${version}"

    log "Java $version required for Minecraft $MC_VERSION"
    log "Downloading Eclipse Temurin JDK $version..."

    rm -rf "$target_dir"
    mkdir -p "$target_dir"

    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64)  arch="x64" ;;
        aarch64) arch="aarch64" ;;
        armv7l)  arch="arm" ;;
        *)       die "Unsupported architecture: $arch" ;;
    esac

    local os="linux"

    local api_url="https://api.adoptium.net/v3/assets/latest/${version}/hotspot?architecture=${arch}&image_type=jdk&os=${os}&vendor=eclipse"

    local release_name download_url
    release_name=$(curl -fsSL "$api_url" \
        | grep -oP '"release_name"\s*:\s*"\K[^"]+' | head -n 1) \
        || die "Failed to query Adoptium API for Java $version ($arch)"

    download_url=$(curl -fsSL "$api_url" \
        | grep -oP '"link"\s*:\s*"\K[^"]+\.tar\.gz(?=")' | head -n 1) \
        || die "Failed to get download URL for Java $version"

    log "Downloading $release_name..."
    local tmp_archive="/tmp/temurin-${version}.tar.gz"
    curl -fsSL "$download_url" -o "$tmp_archive" \
        || die "Download failed for Java $version"

    log "Extracting to $target_dir..."
    tar -xzf "$tmp_archive" -C "$target_dir" --strip-components=1 \
        || die "Failed to extract Java $version"
    rm -f "$tmp_archive"

    local installed_java="$target_dir/bin/java"
    if [ ! -x "$installed_java" ]; then
        die "Java binary not found at $installed_java after extraction"
    fi

    ok "Java $version installed locally at $target_dir"
    echo "$target_dir"
}

java_required_by_jar() {
    local jar="$1"
    [ -f "$jar" ] || return 1
    python3 - "$jar" <<'PY'
import sys, zipfile, struct

zip_path = sys.argv[1]
try:
    with zipfile.ZipFile(zip_path) as z:
        names = z.namelist()
        if "net/minecraft/bundler/Main.class" in names:
            data = z.read("net/minecraft/bundler/Main.class")
        else:
            candidates = sorted(
                n for n in names
                if n.startswith("net/minecraft/") and n.endswith(".class")
            )
            if not candidates:
                sys.exit(1)
            data = z.read(candidates[0])
        class_version = struct.unpack(">H", data[6:8])[0]
        print(class_version - 44)
except Exception:
    sys.exit(1)
PY
}

detect_package_manager() {
    if command -v apt-get >/dev/null 2>&1; then
        echo "apt"
    elif command -v dnf >/dev/null 2>&1; then
        echo "dnf"
    elif command -v pacman >/dev/null 2>&1; then
        echo "pacman"
    elif command -v zypper >/dev/null 2>&1; then
        echo "zypper"
    else
        echo "unknown"
    fi
}

install_system_packages() {
    local pm
    pm=$(detect_package_manager)

    local sudo="sudo"
    if [ "$(id -u)" -eq 0 ] 2>/dev/null; then
        sudo=""
    elif ! command -v sudo >/dev/null 2>&1; then
        sudo=""
    fi

    local missing=()
    for cmd in curl tar python3; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done

    if [ ${#missing[@]} -eq 0 ]; then
        ok "All required utilities present"
        return 0
    fi

    log "Missing utilities: ${missing[*]}"
    log "Attempting to install via $pm..."

    case "$pm" in
        apt)
            $sudo apt-get update -qq
            $sudo apt-get install -y -qq "${missing[@]}"
            ;;
        dnf)
            $sudo dnf install -y -q "${missing[@]}"
            ;;
        pacman)
            $sudo pacman -Sy --noconfirm "${missing[@]}"
            ;;
        zypper)
            $sudo zypper install -n "${missing[@]}"
            ;;
        *)
            warn "Cannot auto-install packages on this system"
            warn "Please install manually: ${missing[*]}"
            warn "Then re-run this script"
            exit 1
            ;;
    esac

    ok "Packages installed"
}

generate_seed() {
    if [ -n "${EVENT_SEED:-}" ]; then
        echo "$EVENT_SEED"
        return
    fi

    local seed
    if [ -r /dev/urandom ]; then
        seed=$(od -An -N7 -tu8 /dev/urandom | tr -d ' ')
    fi
    if [ -z "$seed" ]; then
        seed=$((RANDOM * 32768 + RANDOM))
    fi
    echo "$seed"
}

chunkbase_platform() {
    local mc="$1"
    echo "java_$(echo "$mc" | cut -d. -f1)_$(echo "$mc" | cut -d. -f2)"
}

open_browser() {
    local url="$1"
    if command -v xdg-open >/dev/null 2>&1; then
        xdg-open "$url" >/dev/null 2>&1 &
    elif command -v wslview >/dev/null 2>&1; then
        wslview "$url" >/dev/null 2>&1 &
    elif command -v sensible-browser >/dev/null 2>&1; then
        sensible-browser "$url" >/dev/null 2>&1 &
    elif command -v firefox >/dev/null 2>&1; then
        firefox "$url" >/dev/null 2>&1 &
    else
        warn "No browser launcher found, open this URL manually:"
        warn "$url"
    fi
}

select_seed() {
    local mc_version="$1"
    if [ -n "${EVENT_SEED:-}" ]; then
        echo "$EVENT_SEED"
        return
    fi

    local platform
    platform="${CHUNKBASE_PLATFORM:-$(chunkbase_platform "$mc_version")}"

    echo "" >&2
    log "Seed selection: a random seed is generated and opened on ChunkBase."
    log "Approve it, or regenerate until you find a world you like."
    echo "" >&2

    while true; do
        local seed url
        seed=$(generate_seed)
        url="https://www.chunkbase.com/apps/seed-map#seed=${seed}&platform=${platform}"

        wide_separator >&2
        echo "  Generated seed: $seed" >&2
        echo "  ChunkBase seed map:" >&2
        echo "  $url" >&2
        wide_separator >&2
        echo "" >&2
        open_browser "$url"

        printf "  Approve this seed? (y)es / (n)o, regenerate: " >&2
        read -r approved || {
            echo "" >&2
            warn "No input received, aborting setup"
            return 1
        }
        echo "" >&2
        case "$approved" in
            y|Y|yes|YES)
                ok "Seed $seed approved"
                echo "$seed"
                return 0
                ;;
            *)
                warn "Regenerating a new seed..."
                echo "" >&2
                ;;
        esac
    done
}

generate_server_properties() {
    local seed="$1"
    local mc_version="$2"
    local view_distance="${VIEW_DISTANCE:-16}"
    local sim_distance=$(( view_distance - 2 ))
    local max_players="${MAX_PLAYERS:-30}"
    local spawn_prot="${SPAWN_PROTECTION:-10}"

    mkdir -p "$SERVER_DIR"

    cat > "$SERVER_DIR/server.properties" <<PROPS
motd=\u00a76\u00a7lCo-op Speedrun
level-name=world
level-seed=${seed}
gamemode=adventure
force-gamemode=true
difficulty=normal
pvp=false
spawn-protection=${spawn_prot}
white-list=true
enforce-whitelist=true
online-mode=false
max-players=${max_players}
view-distance=${view_distance}
simulation-distance=${sim_distance}
server-port=25565
server-ip=
enable-command-block=true
allow-flight=false
spawn-monsters=true
generate-structures=true
level-type=minecraft\:normal
max-tick-time=60000
network-compression-threshold=256
rate-limit=0
hide-online-players=false
PROPS
}

generate_start_script() {
    local java_home="$1"
    local java_mem="$2"

    cat > "$SERVER_DIR/start.sh" <<'START'
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

JAVA_BIN="JAVA_HOME_PLACEHOLDER/bin/java"

if [ ! -x "$JAVA_BIN" ]; then
    echo "[ERROR] Java not found at $JAVA_BIN"
    echo "Run setup.sh again to reinstall Java"
    exit 1
fi

SERVER_DIR="$(cd "$(dirname "$0")" && pwd)"
SERVER_JAR="$SERVER_DIR/server.jar"

java_major_of() {
    local out
    out=$("$JAVA_BIN" -version 2>&1)
    if echo "$out" | grep -q '"1\.8\.'; then
        echo 8
    else
        echo "$out" | grep -oP '"\K[0-9]+' | head -n 1
    fi
}

local_ip() {
    local ip
    ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    if [ -z "$ip" ] && command -v ip >/dev/null 2>&1; then
        ip=$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K[0-9.]+' | head -n 1)
    fi
    if [ -z "$ip" ] && command -v ip >/dev/null 2>&1; then
        ip=$(ip -4 addr show scope global 2>/dev/null | grep -oP 'inet \K[0-9.]+' | head -n 1)
    fi
    [ -n "$ip" ] && echo "$ip" || echo "your-ip-here"
}

jar_required_java() {
    [ -f "$SERVER_JAR" ] || return 1
    python3 - "$SERVER_JAR" <<'PY' 2>/dev/null
import sys, zipfile, struct
try:
    with zipfile.ZipFile(sys.argv[1]) as z:
        names = z.namelist()
        if "net/minecraft/bundler/Main.class" in names:
            data = z.read("net/minecraft/bundler/Main.class")
        else:
            candidates = sorted(n for n in names if n.startswith("net/minecraft/") and n.endswith(".class"))
            if not candidates:
                sys.exit(1)
            data = z.read(candidates[0])
        print(struct.unpack(">H", data[6:8])[0] - 44)
except Exception:
    sys.exit(1)
PY
}

REQUIRED_JAVA="$(jar_required_java || true)"
if [ -n "$REQUIRED_JAVA" ]; then
    ACTUAL_JAVA="$(java_major_of)"
    if [ "$ACTUAL_JAVA" -lt "$REQUIRED_JAVA" ] 2>/dev/null; then
        echo "[ERROR] server.jar requires Java $REQUIRED_JAVA or newer, but the configured Java is $ACTUAL_JAVA."
        echo "Run setup.sh again to install the correct Java."
        exit 1
    fi
    echo "[START] Java $ACTUAL_JAVA (server needs $REQUIRED_JAVA+)"
fi

apply_setting() {
    local key="$1"
    local value="$2"
    if grep -q "^${key}=" server.properties 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${value}|" server.properties
    else
        printf '%s=%s\n' "$key" "$value" >> server.properties
    fi
}

WHITELIST_ACTION=""
ONLINE_ACTION=""
for arg in "$@"; do
    case "$arg" in
        --no-whitelist) WHITELIST_ACTION="off" ;;
        --whitelist)    WHITELIST_ACTION="on" ;;
        --offline)      ONLINE_ACTION="false" ;;
        --online)       ONLINE_ACTION="true" ;;
        -h|--help)
            echo "Usage: ./start.sh [options]"
            echo ""
            echo "  --no-whitelist   start with whitelist off"
            echo "  --whitelist      start with whitelist on"
            echo "  --offline        set online-mode=false"
            echo "  --online         set online-mode=true"
            exit 0
            ;;
        *)
            echo "[ERROR] Unknown argument: $arg"
            echo "Run ./start.sh --help"
            exit 1
            ;;
    esac
done

if [ -n "$WHITELIST_ACTION" ]; then
    if [ "$WHITELIST_ACTION" = "on" ]; then
        apply_setting white-list true
        apply_setting enforce-whitelist true
        echo "[START] Whitelist ON"
    else
        apply_setting white-list false
        apply_setting enforce-whitelist false
        echo "[START] Whitelist OFF"
    fi
fi

if [ -n "$ONLINE_ACTION" ]; then
    apply_setting online-mode "$ONLINE_ACTION"
    echo "[START] online-mode=$ONLINE_ACTION"
fi

echo "[START] Server address: $(local_ip):25565"

exec "$JAVA_BIN" \
    -Xms4G \
    -XmxJAVA_MEM_PLACEHOLDER \
    -XX:+UseG1GC \
    -XX:+ParallelRefProcEnabled \
    -XX:MaxGCPauseMillis=200 \
    -XX:+UnlockExperimentalVMOptions \
    -XX:+DisableExplicitGC \
    -XX:+AlwaysPreTouch \
    -XX:G1NewSizePercent=30 \
    -XX:G1MaxNewSizePercent=40 \
    -XX:G1HeapRegionSize=8M \
    -XX:G1ReservePercent=20 \
    -XX:G1HeapWastePercent=5 \
    -XX:G1MixedGCCountTarget=4 \
    -XX:InitiatingHeapOccupancyPercent=15 \
    -XX:G1MixedGCLiveThresholdPercent=90 \
    -XX:G1RSetUpdatingPauseTimePercent=5 \
    -XX:SurvivorRatio=32 \
    -XX:+PerfDisableSharedMem \
    -XX:MaxTenuringThreshold=1 \
    -Dusing.aikars.flags=https://mcflags.emc.gs \
    -Daikars.new.flags=true \
    -jar fabric-server-launch.jar nogui
START

    sed -i "s|JAVA_HOME_PLACEHOLDER|${java_home}|g" "$SERVER_DIR/start.sh"
    sed -i "s|JAVA_MEM_PLACEHOLDER|${java_mem}|g" "$SERVER_DIR/start.sh"
    chmod +x "$SERVER_DIR/start.sh"
}

find_compatible_mod_file() {
    python3 - "$1" "$2" <<'PY'
import json, sys, re

def parse_mc(s):
    m = re.match(r"^(\d+)\.(\d+)(?:\.(\d+))?$", s)
    if not m:
        return None
    return int(m.group(1)), int(m.group(2)), int(m.group(3) or 0)

data = json.load(open(sys.argv[1]))
major, minor, target_patch = parse_mc(sys.argv[2])

def series_patch(gv_list):
    best = None
    for gv in gv_list:
        p = parse_mc(gv)
        if p and p[0] == major and p[1] == minor:
            if best is None or p[2] > best:
                best = p[2]
    return best

exact_hit = None
lower_hit = None
upper_hit = None
for v in data:
    patch = series_patch(v.get("game_versions", []))
    if patch is None:
        continue
    url = None
    for f in v.get("files", []):
        if f["url"].endswith(".jar"):
            url = f["url"]
            break
    if not url:
        continue
    entry = (url, v.get("version_number", ""), patch)
    if patch == target_patch:
        if exact_hit is None or entry[1] > exact_hit[1]:
            exact_hit = entry
    elif patch < target_patch:
        if lower_hit is None or patch > lower_hit[2]:
            lower_hit = entry
    else:
        if upper_hit is None or patch < upper_hit[2]:
            upper_hit = entry

found = exact_hit or lower_hit or upper_hit
if found is None:
    sys.exit(1)
print(f"{found[0]}|{found[1]}")
PY
}

download_mod_from_modrinth() {
    local project_id="$1"
    local mod_name="$2"
    local mc_version="$3"
    local loader="$4"
    local mods_dir="$5"

    local series
    series=$(echo "$mc_version" | grep -oP '^\d+\.\d+') || {
        warn "Unparseable MC version for $mod_name"
        return 1
    }

    local versions_json
    versions_json=$(curl -fsSL \
        "https://api.modrinth.com/v2/project/${project_id}/version?loaders=%5B%22${loader}%22%5D" \
        2>/dev/null) || {
        warn "Modrinth API request failed for $mod_name"
        return 1
    }

    if [ -z "$versions_json" ] || printf '%s' "$versions_json" | grep -q '"error"'; then
        warn "Modrinth API error for $mod_name"
        return 1
    fi

    local json_tmp
    json_tmp=$(mktemp)
    printf '%s' "$versions_json" > "$json_tmp"

    local chosen
    chosen=$(find_compatible_mod_file "$json_tmp" "$series" 2>/dev/null) || {
        rm -f "$json_tmp"
        warn "No compatible version found for $mod_name (MC $mc_version, $loader)"
        return 1
    }
    rm -f "$json_tmp"

    local download_url="${chosen%%|*}"
    local version_number="${chosen#*|}"

    local filename
    filename=$(basename "$download_url")

    log "Downloading ${mod_name} v${version_number} (MC ${mc_version})..."
    curl -fL "$download_url" -o "$mods_dir/$filename" 2>/dev/null \
        || { warn "Failed to download $mod_name"; return 1; }

    ok "$mod_name v$version_number"
    return 0
}

main() {
    MC_VERSION=$(select_version)

    if [ "$MC_VERSION" = "latest" ]; then
        MC_VERSION=$(resolve_latest_version)
    fi

    JAVA_VERSION="${JAVA_VERSION:-$(java_version_for_mc "$MC_VERSION")}"
    EVENT_SEED=$(select_seed "$MC_VERSION")
    JAVA_MEMORY="${JAVA_MEMORY:-14G}"
    VIEW_DISTANCE="${VIEW_DISTANCE:-16}"
    MAX_PLAYERS="${MAX_PLAYERS:-30}"
    SERVER_IP=$(local_ip)
    RACE_BORDER="${RACE_BORDER:-59999968}"
    LOBBY_X="${LOBBY_X:-0}"
    LOBBY_Y="${LOBBY_Y:-100}"
    LOBBY_Z="${LOBBY_Z:-0}"

    separator
    echo "  Minecraft Co-op Speedrun - Server Setup"
    separator
    echo ""
    echo "  Minecraft Version:  $MC_VERSION"
    echo "  Java Version:       $JAVA_VERSION"
    echo "  Event Seed:         $EVENT_SEED"
    echo "  Server Directory:   $SERVER_DIR"
    echo "  Java Memory:        $JAVA_MEMORY"
    echo "  View Distance:      $VIEW_DISTANCE"
    echo "  Max Players:        $MAX_PLAYERS"
    echo ""
    separator
    echo ""

    log "Checking system requirements..."
    install_system_packages
    echo ""

    log "Setting up Java $JAVA_VERSION..."
    JAVA_HOME_DIR=""
    if JAVA_HOME_DIR=$(find_java "$JAVA_VERSION"); then
        if [ -n "$JAVA_HOME_DIR" ]; then
            ok "Using local Java: $JAVA_HOME_DIR"
        else
            ok "Using system Java (version $JAVA_VERSION)"
        fi
    else
        JAVA_HOME_DIR=$(download_java "$JAVA_VERSION")
    fi
    echo ""

    if [ -n "$JAVA_HOME_DIR" ]; then
        export PATH="$JAVA_HOME_DIR/bin:$PATH"
    fi

    log "Creating directory structure..."
    mkdir -p "$SERVER_DIR"/{mods,event/config,event/results,event/logs,world,logs,java}
    ok "Directories created"
    echo ""

    log "Downloading Fabric installer..."
    mkdir -p /tmp/fabric-setup

    local fabric_version
    fabric_version=$(curl -fsSL "https://maven.fabricmc.net/net/fabricmc/fabric-installer/maven-metadata.xml" \
        | grep -oP '<latest>\K[^<]+') || fabric_version="1.1.2"

    curl -fsSL "https://maven.fabricmc.net/net/fabricmc/fabric-installer/${fabric_version}/fabric-installer-${fabric_version}.jar" \
        -o /tmp/fabric-setup/fabric-installer.jar \
        || die "Failed to download Fabric installer"
    ok "Fabric installer v$fabric_version downloaded"
    echo ""

    log "Installing Fabric server (MC $MC_VERSION)..."
    cd "$SERVER_DIR"
    java -jar /tmp/fabric-setup/fabric-installer.jar server \
        -mcversion "$MC_VERSION" \
        -downloadMinecraft \
        || die "Fabric installation failed"
    rm -rf /tmp/fabric-setup
    ok "Fabric server installed"
    echo ""

    log "Verifying Java compatibility with the server jar..."
    local required_java
    if required_java=$(java_required_by_jar "$SERVER_DIR/server.jar" 2>/dev/null); then
        if [ -n "$required_java" ] && [ "$required_java" -gt "$JAVA_VERSION" ] 2>/dev/null; then
            warn "Server jar requires Java $required_java or newer, upgrading from Java $JAVA_VERSION..."
            JAVA_HOME_DIR=$(download_java "$required_java")
            export PATH="$JAVA_HOME_DIR/bin:$PATH"
            JAVA_VERSION=$required_java
        else
            ok "Java $JAVA_VERSION satisfies the server jar (requires $required_java)"
        fi
    else
        warn "Could not inspect $SERVER_DIR/server.jar, trusting mapped Java $JAVA_VERSION"
    fi
    echo ""

    log "Downloading compatible performance mods..."
    MODS_DOWNLOADED=0
    MODS_FAILED=0

    MODRINTH_MODS=(
        "lithium:Lithium"
        "ferrite-core:FerriteCore"
        "krypton:Krypton"
        "servercore:ServerCore"
        "noisium:Noisium"
    )

    for entry in "${MODRINTH_MODS[@]}"; do
        project_id="${entry%%:*}"
        mod_name="${entry#*:}"
        if download_mod_from_modrinth "$project_id" "$mod_name" "$MC_VERSION" "fabric" "$SERVER_DIR/mods"; then
            MODS_DOWNLOADED=$((MODS_DOWNLOADED + 1))
        else
            MODS_FAILED=$((MODS_FAILED + 1))
        fi
    done

    echo ""
    if [ "$MODS_DOWNLOADED" -gt 0 ]; then
        ok "$MODS_DOWNLOADED performance mod(s) installed"
    fi
    if [ "$MODS_FAILED" -gt 0 ]; then
        warn "$MODS_FAILED mod(s) could not be downloaded (may not support MC $MC_VERSION)"
    fi
    echo ""

    log "Generating server configuration..."
    generate_server_properties "$EVENT_SEED" "$MC_VERSION"
    ok "server.properties created"

    cat > "$SERVER_DIR/eula.txt" <<'EULA'
eula=true
EULA
    ok "eula.txt created"

    generate_start_script "${JAVA_HOME_DIR:-/usr}" "$JAVA_MEMORY"
    ok "start.sh created"
    echo ""

    log "Creating event directories..."
    mkdir -p "$SERVER_DIR/event"/{config,results,logs}

    cat > "$SERVER_DIR/event/config/event.json" <<CFG
{
  "event_name": "Co-op Speedrun",
  "mc_version": "$MC_VERSION",
  "seed": "$EVENT_SEED",
  "max_players": $MAX_PLAYERS,
  "lobby": {
    "x": $LOBBY_X,
    "y": $LOBBY_Y,
    "z": $LOBBY_Z,
    "border_diameter": 20
  },
  "race": {
    "border_diameter": $RACE_BORDER
  },
  "spawn_protection": 10,
  "java_memory": "$JAVA_MEMORY",
  "view_distance": $VIEW_DISTANCE
}
CFG
    ok "Event config created"
    echo ""

    log "Performing initial server launch..."
    log "This will generate the world from the seed..."
    echo ""

    cd "$SERVER_DIR"
    rm -f /tmp/mc-console.log /tmp/mc-console.pipe
    mkfifo /tmp/mc-console.pipe

    java -Xms1G -Xmx2G -jar fabric-server-launch.jar nogui \
        < /tmp/mc-console.pipe > "$SERVER_DIR/event/logs/setup-launch.log" 2>&1 &
    local server_pid=$!

    exec 3<>/tmp/mc-console.pipe
    log "Waiting for world generation to complete..."
    local wait_seconds=0
    while kill -0 "$server_pid" 2>/dev/null && ! grep -q "Done" "$SERVER_DIR/event/logs/setup-launch.log" 2>/dev/null; do
        sleep 3
        wait_seconds=$((wait_seconds + 3))
        if [ "$wait_seconds" -ge 480 ]; then
            warn "World generation exceeded 8 minutes, stopping server..."
            echo "stop" >&3
            wait "$server_pid" || true
            break
        fi
    done

    if ! kill -0 "$server_pid" 2>/dev/null; then
        if grep -q "Done" "$SERVER_DIR/event/logs/setup-launch.log" 2>/dev/null; then
            ok "Server shut down cleanly"
        else
            warn "Server exited during initial launch, check event/logs/setup-launch.log"
        fi
    else
        ok "World generated, sending shutdown command..."
        echo "stop" >&3
        wait "$server_pid" || true
    fi

    exec 3>&-
    rm -f /tmp/mc-console.pipe

    echo ""
    ok "Initial launch complete, server shut down cleanly"
    echo ""

    log "Creating convenience symlink..."
    ln -sf "$SERVER_DIR/start.sh" "$BASE_DIR/start.sh"
    ok "Symlink: $BASE_DIR/start.sh -> $SERVER_DIR/start.sh"
    echo ""

    wide_separator
    echo ""
    echo "  SETUP COMPLETE"
    echo ""
    echo "  Minecraft Version:  $MC_VERSION"
    echo "  Java Version:       $JAVA_VERSION"
    echo "  Event Seed:         $EVENT_SEED"
    echo "  Server Directory:   $SERVER_DIR"
    echo "  Java Memory:        $JAVA_MEMORY"
    echo "  View Distance:      $VIEW_DISTANCE"
    echo "  Performance Mods:   $MODS_DOWNLOADED installed"
    echo ""
    echo "  To start the server:"
    echo "    cd $SERVER_DIR && ./start.sh"
    echo ""
    echo "  Or use the shortcut:"
    echo "    $BASE_DIR/start.sh"
    echo ""
    echo "  Server address: $SERVER_IP:25565"
    echo ""
    wide_separator
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
