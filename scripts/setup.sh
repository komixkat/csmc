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

build_series() {
    local manifest="$1"
    python3 - "$manifest" <<'PY'
import json, re, sys
d = json.load(open(sys.argv[1]))
custom = {
    (26, 2): "Chaos Cubed",
    (26, 1): "Tiny Takeover",
    (1, 21, 4): "The Garden Awakens",
}
names = {
    (1, 0): "Adventure Update",
    (1, 1): "Adventure Update",
    (1, 2): "The Update that Changed the World",
    (1, 3): "1.3 Update",
    (1, 4): "Pretty Scary Update",
    (1, 5): "Redstone Update",
    (1, 6): "Horse Update",
    (1, 7): "The Update that Changed the World",
    (1, 8): "Bountiful Update",
    (1, 9): "Combat Update",
    (1, 10): "Frostburn Update",
    (1, 11): "Exploration Update",
    (1, 12): "World of Color Update",
    (1, 13): "Update Aquatic",
    (1, 14): "Village & Pillage",
    (1, 15): "Buzzy Bees",
    (1, 16): "Nether Update",
    (1, 17): "Caves & Cliffs",
    (1, 18): "Caves & Cliffs",
    (1, 19): "The Wild Update",
    (1, 20): "Trails & Tales",
    (1, 21): "Tricky Trials",
    (26, 1): "Tiny Takeover",
    (26, 2): "Chaos Cubed",
}
def parse(vid):
    m = re.match(r"^(\d+)\.(\d+)(?:\.(\d+))?$", vid)
    if not m:
        return None
    return int(m.group(1)), int(m.group(2)), int(m.group(3) or 0)
def label(p):
    if p in custom:
        return custom[p]
    if p[:2] in names:
        return names[p[:2]]
    return ""
series = {}
base_rt = {}
for v in d["versions"]:
    if v["type"] != "release":
        continue
    p = parse(v["id"])
    if not p:
        continue
    ma, mi, pa = p
    if ma == 1 and mi < 14:
        continue
    if ma == 0 or (ma == 1 and mi == 0):
        continue
    base = (ma, mi)
    series.setdefault(base, []).append((p, v["releaseTime"]))
for base, rows in series.items():
    rows.sort(key=lambda r: r[0], reverse=True)
    base_rt[base] = max(r[1] for _, r in rows)
ordered = sorted(series.items(), key=lambda kv: base_rt[kv[0]], reverse=True)
out = []
for base, rows in ordered:
    name = label((base[0], base[1], 0))
    if len(rows) == 1:
        only = rows[0][0]
        if len(only) == 3 and only[2] == 0:
            vid = ".".join(str(x) for x in only[:2])
        else:
            vid = ".".join(str(x) for x in only)
        out.append((vid + (" - " + name if name else ""), vid))
    else:
        vid = ".".join(str(x) for x in base)
        out.append((vid + (" - " + name if name else ""), "series:" + vid))
import sys
for label, sel in out:
    sys.stdout.write("{}\t{}\n".format(label, sel))
PY
}

drop_update_name() {
    local base="$1"
    local cached name
    cached=$(grep -P "^${base}\t" /tmp/csmc-dropnames.txt 2>/dev/null | head -n 1)
    if [ -n "$cached" ]; then
        printf '%s' "${cached#*$'\t'}"
        return 0
    fi
    name=$(curl -fsS --max-time 12 \
        "https://minecraft.wiki/api.php?action=parse&page=Java_Edition_${base}&format=json&prop=wikitext" 2>/dev/null \
        | python3 -c '
import json, re, sys
try:
    wt = json.load(sys.stdin)["parse"]["wikitext"]["*"]
except Exception:
    sys.exit(1)
m = re.search(r"\|\s*name\s*=\s*\[\[([^\]|]+)", wt)
if not m:
    m = re.search(r"\|\s*name\s*=\s*([^|\[\]\n]+)", wt)
sys.stdout.write(m.group(1).strip() if m else "")
')
    if [ -n "$name" ]; then
        printf '%s\t%s\n' "$base" "$name" >> /tmp/csmc-dropnames.txt
    fi
    printf '%s' "$name"
    return 0
}

ordinal_word() {
    case "$1" in
        1) printf 'First' ;;
        2) printf 'Second' ;;
        3) printf 'Third' ;;
        4) printf 'Fourth' ;;
        5) printf 'Fifth' ;;
        6) printf 'Sixth' ;;
        7) printf 'Seventh' ;;
        8) printf 'Eighth' ;;
        9) printf 'Ninth' ;;
        10) printf 'Tenth' ;;
        *) printf '%sth' "$1" ;;
    esac
}

select_version() {
    local manifest="$1"
    local version="${MC_VERSION:-}"
    if [ -n "$version" ]; then
        echo "$version"
        return 0
    fi

    build_series "$manifest" > /tmp/csmc-series.txt
    : > /tmp/csmc-dropnames.txt
    local line label sel base_id idx e ma mi
    local id base major name
    {
        while IFS=$'\t' read -r label sel; do
            id="${sel#series:}"
            case "$id" in
                *.*.*) base="${id%.*}" ;;
                *) base="$id" ;;
            esac
            major="${base%%.*}"
            if [ "${major:-0}" -ge 2 ] && [[ "$label" != *" - "* ]]; then
                name=$(drop_update_name "$base")
                if [ -n "$name" ]; then
                    label="$base - $name"
                else
                    label="$base - $(ordinal_word "${base#*.}") Drop $(( ${base%%.*} + 2000 ))"
                fi
            fi
            printf '%s\t%s\n' "$label" "$sel"
        done < /tmp/csmc-series.txt
    } > /tmp/csmc-series2.txt
    mv /tmp/csmc-series2.txt /tmp/csmc-series.txt
    mapfile -t SERIES < /tmp/csmc-series.txt

    if [ "${#SERIES[@]}" -gt 0 ]; then
        base_id="${SERIES[0]#*$'\t'}"
    fi

    while true; do
        wide_separator >&2
        echo "  Minecraft Co-op Speedrun - Server Setup" >&2
        wide_separator >&2
        echo "" >&2
        echo "  Which major Minecraft version do you want?" >&2
        printf "    1) latest (currently %s)\n" "${base_id#series:}" >&2
        idx=2
        for line in "${SERIES[@]}"; do
            label="${line%%$'\t'*}"
            printf "  %3d) %s\n" "$idx" "$label" >&2
            idx=$((idx + 1))
        done
        echo "" >&2
        printf "  Enter the number (or q to quit): " >&2
        read -r choice || {
            echo "" >&2
            warn "No input received, aborting setup"
            return 1
        }
        echo "" >&2
        if [ "$choice" = "q" ] || [ "$choice" = "quit" ]; then
            warn "Setup aborted"
            return 1
        fi
        if [ "$choice" = "1" ]; then
            echo "latest"
            return 0
        fi
        if echo "$choice" | grep -qP '^\d+$'; then
            num=$((choice - 2))
            if [ "$num" -ge 0 ] && [ "$num" -lt "${#SERIES[@]}" ]; then
                sel="${SERIES[$num]#*$'\t'}"
                if [ "${sel#series:}" != "$sel" ]; then
                    select_patch "$manifest" "${sel#series:}"
                    return $?
                fi
                echo "$sel"
                return 0
            fi
            warn "Invalid choice: $choice"
            continue
        fi
        warn "Invalid choice: $choice"
    done
}

select_patch() {
    local manifest="$1" base="$2"
    local version="${MC_VERSION:-}"
    local list_tmp
    list_tmp=$(mktemp)
    python3 - "$manifest" "$base" "$list_tmp" <<'PY'
import json, re, sys
d = json.load(open(sys.argv[1]))
base = tuple(int(x) for x in sys.argv[2].split("."))
def parse(vid):
    m = re.match(r"^(\d+)\.(\d+)(?:\.(\d+))?$", vid)
    if not m:
        return None
    p = (int(m.group(1)), int(m.group(2)), int(m.group(3) or 0))
    return p if p[:2] == base else None
rows = []
for vid in d["versions"]:
    if vid["type"] != "release":
        continue
    p = parse(vid["id"])
    if p:
        rows.append((vid["releaseTime"], vid["id"]))
rows.sort(reverse=True)
open(sys.argv[3], "w").write("\n".join(v for _, v in rows))
PY

    mapfile -t PATCHES < "$list_tmp"
    rm -f "$list_tmp"
    if [ "${#PATCHES[@]}" -le 1 ]; then
        echo "${PATCHES[0]}"
        return 0
    fi

    while true; do
        wide_separator >&2
        echo "  Minecraft Co-op Speedrun - Server Setup" >&2
        wide_separator >&2
        echo "" >&2
        printf "  Which %s version do you want?\n" "$base" >&2
        idx=1
        local p
        for p in "${PATCHES[@]}"; do
            printf "  %3d) %s\n" "$idx" "$p" >&2
            idx=$((idx + 1))
        done
        echo "" >&2
        printf "  Enter the number (or q to go back): " >&2
        read -r choice || {
            echo "" >&2
            warn "No input received, aborting setup"
            return 1
        }
        echo "" >&2
        if [ "$choice" = "q" ] || [ "$choice" = "quit" ]; then
            return 1
        fi
        if echo "$choice" | grep -qP '^\d+$'; then
            num=$((choice - 1))
            if [ "$num" -ge 0 ] && [ "$num" -lt "${#PATCHES[@]}" ]; then
                echo "${PATCHES[$num]}"
                return 0
            fi
        fi
        warn "Invalid choice: $choice"
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
    local major minor patch
    major=$(echo "$mc" | cut -d. -f1 | grep -oP '^\d+')
    minor=$(echo "$mc" | cut -d. -f2 | grep -oP '^\d+')
    patch=$(echo "$mc" | cut -d. -f3 | grep -oP '^\d+')
    major=${major:-0}
    minor=${minor:-0}
    patch=${patch:-0}

    if [ "$major" -ge 26 ] 2>/dev/null; then
        echo 25
    elif [ "$major" -eq 1 ] 2>/dev/null; then
        if [ "$minor" -le 16 ] 2>/dev/null; then
            echo 8
        elif [ "$minor" -le 19 ] 2>/dev/null; then
            echo 17
        elif [ "$minor" -eq 20 ] 2>/dev/null; then
            if [ "$patch" -le 4 ] 2>/dev/null; then
                echo 17
            else
                echo 21
            fi
        else
            echo 21
        fi
    else
        echo 8
    fi
}

manifest_java_version() {
    local manifest="$1"
    local mc_version="$2"
    local url
    url=$(python3 - "$manifest" "$mc_version" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
for v in d["versions"]:
    if v["id"] == sys.argv[2] and v["type"] == "release":
        print(v["url"])
        break
PY
)
    [ -n "$url" ] || return 1
    curl -fsSL --max-time 15 "$url" 2>/dev/null \
        | grep -oP '"javaVersion":\s*\{[^}]*"majorVersion":\s*\K[0-9]+' | head -n 1
}

warn_old_for_fabric() {
    local mc="$1"
    local major minor
    major=$(echo "$mc" | cut -d. -f1 | grep -oP '^\d+')
    minor=$(echo "$mc" | cut -d. -f2 | grep -oP '^\d+')
    if [ -n "$major" ] && [ "$major" -eq 1 ] 2>/dev/null && [ -n "$minor" ] && [ "$minor" -lt 14 ] 2>/dev/null; then
        warn "MC $mc predates Fabric (1.14.4+); the Fabric install will likely fail"
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
pvp=true
spawn-protection=${spawn_prot}
white-list=false
enforce-whitelist=false
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
set -uo pipefail
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

world_spawn() {
    [ -f "$SERVER_DIR/world/level.dat" ] || { echo "0 0"; return 1; }
    python3 - "$SERVER_DIR/world/level.dat" <<'PY' 2>/dev/null
import gzip, struct, sys
data = gzip.open(sys.argv[1], 'rb').read()
pos = [0]
def u8():
    v = data[pos[0]]
    pos[0] += 1
    return v
def u16():
    v = struct.unpack('>H', data[pos[0]:pos[0]+2])[0]
    pos[0] += 2
    return v
def s16():
    v = struct.unpack('>h', data[pos[0]:pos[0]+2])[0]
    pos[0] += 2
    return v
def s32():
    v = struct.unpack('>i', data[pos[0]:pos[0]+4])[0]
    pos[0] += 4
    return v
def s64():
    v = struct.unpack('>q', data[pos[0]:pos[0]+8])[0]
    pos[0] += 8
    return v
def f32():
    v = struct.unpack('>f', data[pos[0]:pos[0]+4])[0]
    pos[0] += 4
    return v
def f64():
    v = struct.unpack('>d', data[pos[0]:pos[0]+8])[0]
    pos[0] += 8
    return v
def name():
    n = u16()
    v = data[pos[0]:pos[0]+n].decode('utf-8')
    pos[0] += n
    return v
def tag(t):
    if t == 0:
        return None
    if t == 1:
        return u8()
    if t == 2:
        return s16()
    if t == 3:
        return s32()
    if t == 4:
        return s64()
    if t == 5:
        return f32()
    if t == 6:
        return f64()
    if t == 7:
        n = s32()
        v = data[pos[0]:pos[0]+n]
        pos[0] += n
        return v
    if t == 8:
        return name()
    if t == 9:
        et = u8()
        n = s32()
        return [tag(et) for _ in range(n)]
    if t == 10:
        out = {}
        while True:
            tt = u8()
            if tt == 0:
                break
            k = name()
            out[k] = tag(tt)
        return out
    if t == 11:
        n = s32()
        return [s32() for _ in range(n)]
    if t == 12:
        n = s32()
        return [s64() for _ in range(n)]
t = u8()
_ = name()
root = tag(t)
data_tag = root['Data'] if 'Data' in root else root
print('%s %s %s' % (data_tag['SpawnX'], data_tag.get('SpawnY', 64), data_tag['SpawnZ']))
PY
}

SPAWN_COORDS="$(world_spawn || true)"
echo "[START] World spawn: $SPAWN_COORDS"
echo "[START] Players are held at spawn until the race starts (datapack csmc_hold)"
echo "[START] Start the race: /function csmc_hold:release"

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
    python3 - "$1" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
best = None
best_key = None
for v in data:
    url = None
    for f in v.get("files", []):
        if f.get("url", "").endswith(".jar"):
            url = f["url"]
            break
    if not url:
        continue
    release = 0 if v.get("version_type") == "release" else 1
    key = (release, v.get("date_published", ""))
    if best_key is None or key[0] < best_key[0] or (key[0] == best_key[0] and key[1] > best_key[1]):
        best_key = key
        best = (url, v.get("version_number", ""))
if best is None:
    sys.exit(1)
print(f"{best[0]}|{best[1]}")
PY
}

download_mod_from_modrinth() {
    local project_id="$1"
    local mod_name="$2"
    local mc_version="$3"
    local loader="$4"
    local mods_dir="$5"

    local versions_json
    versions_json=$(curl -fsSL \
        "https://api.modrinth.com/v2/project/${project_id}/version?loaders=%5B%22${loader}%22%5D&game_versions=%5B%22${mc_version}%22%5D" \
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
    chosen=$(find_compatible_mod_file "$json_tmp" 2>/dev/null) || {
        rm -f "$json_tmp"
        log "Skipping $mod_name (no build for MC $mc_version)"
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

write_hold_datapack() {
    local level_dat="$SERVER_DIR/world/level.dat"
    [ -f "$level_dat" ] || { warn "No world found, skipping hold datapack"; return 1; }
    local spawn sx sy sz
    spawn=$(python3 - "$level_dat" <<'PY'
import gzip, struct, sys
data = gzip.open(sys.argv[1], 'rb').read()
pos = [0]
def u8():
    v = data[pos[0]]
    pos[0] += 1
    return v
def u16():
    v = struct.unpack('>H', data[pos[0]:pos[0]+2])[0]
    pos[0] += 2
    return v
def s16():
    v = struct.unpack('>h', data[pos[0]:pos[0]+2])[0]
    pos[0] += 2
    return v
def s32():
    v = struct.unpack('>i', data[pos[0]:pos[0]+4])[0]
    pos[0] += 4
    return v
def s64():
    v = struct.unpack('>q', data[pos[0]:pos[0]+8])[0]
    pos[0] += 8
    return v
def f32():
    v = struct.unpack('>f', data[pos[0]:pos[0]+4])[0]
    pos[0] += 4
    return v
def f64():
    v = struct.unpack('>d', data[pos[0]:pos[0]+8])[0]
    pos[0] += 8
    return v
def name():
    n = u16()
    v = data[pos[0]:pos[0]+n].decode('utf-8')
    pos[0] += n
    return v
def tag(t):
    if t == 0:
        return None
    if t == 1:
        return u8()
    if t == 2:
        return s16()
    if t == 3:
        return s32()
    if t == 4:
        return s64()
    if t == 5:
        return f32()
    if t == 6:
        return f64()
    if t == 7:
        n = s32()
        v = data[pos[0]:pos[0]+n]
        pos[0] += n
        return v
    if t == 8:
        return name()
    if t == 9:
        et = u8()
        n = s32()
        return [tag(et) for _ in range(n)]
    if t == 10:
        out = {}
        while True:
            tt = u8()
            if tt == 0:
                break
            k = name()
            out[k] = tag(tt)
        return out
    if t == 11:
        n = s32()
        return [s32() for _ in range(n)]
    if t == 12:
        n = s32()
        return [s64() for _ in range(n)]
t = u8()
_ = name()
root = tag(t)
data_tag = root['Data'] if 'Data' in root else root
print('%s %s %s' % (data_tag.get('SpawnX', 0), data_tag.get('SpawnY', 64), data_tag.get('SpawnZ', 0)))
PY
)
    read -r sx sy sz <<< "$spawn" || true
    sy=$((sy + 1))
    local radius="${START_BORDER:-10}"
    local pack_dir="$SERVER_DIR/world/datapacks/csmc_hold"
    mkdir -p "$pack_dir/data/csmc_hold/functions" "$pack_dir/data/minecraft/tags/functions"

    cat > "$pack_dir/pack.mcmeta" <<META
{
  "pack": {
    "pack_format": 4,
    "description": "Hold players at spawn until the race starts"
  }
}
META

    cat > "$pack_dir/data/minecraft/tags/functions/tick.json" <<TICK
{
  "values": [
    "csmc_hold:tick"
  ]
}
TICK

    cat > "$pack_dir/data/csmc_hold/functions/tick.mcfunction" <<TICKFN
execute positioned $(( sx - radius )) 0 $(( sz - radius )) as @a unless entity @s[dx=$(( radius * 2 )),dy=512,dz=$(( radius * 2 ))] run execute if entity @s[gamemode=adventure] run tp @s $sx $sy $sz
execute if entity @a[gamemode=survival] run function csmc_hold:race
TICKFN

    cat > "$pack_dir/data/csmc_hold/functions/step.mcfunction" <<STEP
scoreboard players add c csmc_time 5
execute if score c csmc_time matches 100 run scoreboard players set c csmc_time 0
execute if score c csmc_time matches 0 run scoreboard players add s csmc_time 1
execute if score s csmc_time matches 60 run scoreboard players add m csmc_time 1
execute if score s csmc_time matches 60 run scoreboard players set s csmc_time 0
execute if score m csmc_time matches 60 run scoreboard players add h csmc_time 1
execute if score m csmc_time matches 60 run scoreboard players set m csmc_time 0
STEP
    for hp in 0 1; do
        for mp in 0 1; do
            for sp in 0 1; do
                for cp in 0 1; do
                    local cond=""
                    local hpad=""
                    local mpad=""
                    local spad=""
                    local cpad=""
                    if [ "$hp" = 1 ]; then
                        cond="$cond if score h csmc_time matches 0..9"
                        hpad='{"text":" "},{"score":{"name":"h","objective":"csmc_time"}}'
                    else
                        cond="$cond unless score h csmc_time matches 0..9"
                        hpad='{"score":{"name":"h","objective":"csmc_time"}}'
                    fi
                    if [ "$mp" = 1 ]; then
                        cond="$cond if score m csmc_time matches 0..9"
                        mpad='{"text":" "},{"score":{"name":"m","objective":"csmc_time"}}'
                    else
                        cond="$cond unless score m csmc_time matches 0..9"
                        mpad='{"score":{"name":"m","objective":"csmc_time"}}'
                    fi
                    if [ "$sp" = 1 ]; then
                        cond="$cond if score s csmc_time matches 0..9"
                        spad='{"text":" "},{"score":{"name":"s","objective":"csmc_time"}}'
                    else
                        cond="$cond unless score s csmc_time matches 0..9"
                        spad='{"score":{"name":"s","objective":"csmc_time"}}'
                    fi
                    if [ "$cp" = 1 ]; then
                        cond="$cond if score c csmc_time matches 0..9"
                        cpad='{"text":" "},{"score":{"name":"c","objective":"csmc_time"}}'
                    else
                        cond="$cond unless score c csmc_time matches 0..9"
                        cpad='{"score":{"name":"c","objective":"csmc_time"}}'
                    fi
                    printf -- 'execute %s run title @a actionbar {"text":"Time: ","color":"gold","extra":[%s,{"text":":"},%s,{"text":":"},%s,{"text":"."},%s]}\n' "${cond# }" "$hpad" "$mpad" "$spad" "$cpad" \
                        >> "$pack_dir/data/csmc_hold/functions/step.mcfunction"
                done
            done
        done
    done

    cat > "$pack_dir/data/csmc_hold/functions/race.mcfunction" <<RACE
execute if score done csmc_time matches 0 if entity @e[type=ender_dragon] run scoreboard players set seen csmc_time 1
execute if score done csmc_time matches 0 if score seen csmc_time matches 1 unless entity @e[type=ender_dragon] run function csmc_hold:beat
execute if score done csmc_time matches 0 run function csmc_hold:step
RACE

    cat > "$pack_dir/data/csmc_hold/functions/beat.mcfunction" <<BEAT
scoreboard players set done csmc_time 1
title @a title {"text":"Beat the game.","color":"gold","bold":true}
tellraw @a {"text":"Beat the game in ","color":"gold","bold":true,"extra":[{"score":{"name":"h","objective":"csmc_time"}},{"text":":"},{"score":{"name":"m","objective":"csmc_time"}},{"text":":"},{"score":{"name":"s","objective":"csmc_time"}},{"text":"."},{"score":{"name":"c","objective":"csmc_time"}},{"text":". Good Game.","color":"green"}]}
BEAT

    cat > "$pack_dir/data/csmc_hold/functions/release.mcfunction" <<REL
gamemode survival @a
scoreboard players set c csmc_time 0
scoreboard players set s csmc_time 0
scoreboard players set m csmc_time 0
scoreboard players set h csmc_time 0
scoreboard players set seen csmc_time 0
scoreboard players set done csmc_time 0
time set 0
tellraw @a {"text":"Timer Started, Best of Luck.","color":"green","bold":true}
REL

    cat > "$pack_dir/data/csmc_hold/functions/arm.mcfunction" <<ARM
gamemode adventure @a
scoreboard players set c csmc_time 0
scoreboard players set s csmc_time 0
scoreboard players set m csmc_time 0
scoreboard players set h csmc_time 0
scoreboard players set seen csmc_time 0
scoreboard players set done csmc_time 0
ARM
}

main() {
    log "Fetching Minecraft version list from Mojang..."
    local manifest="/tmp/csmc-manifest.json"
    curl -fsSL --max-time 20 \
        "https://piston-meta.mojang.com/mc/game/version_manifest_v2.json" \
        -o "$manifest" \
        || die "Failed to fetch the Minecraft version manifest"

    MC_VERSION=$(select_version "$manifest")

    if [ "$MC_VERSION" = "latest" ]; then
        MC_VERSION=$(resolve_latest_version)
    fi

    warn_old_for_fabric "$MC_VERSION"

    JAVA_VERSION="${JAVA_VERSION:-$(java_version_for_mc "$MC_VERSION")}"
    local manifest_java
    if manifest_java=$(manifest_java_version "$manifest" "$MC_VERSION" 2>/dev/null); then
        if [ -n "$manifest_java" ] && echo "$manifest_java" | grep -qxE '8|17|21|25'; then
            JAVA_VERSION=$manifest_java
            log "Mojang lists Java $JAVA_VERSION for MC $MC_VERSION"
        fi
    fi
    EVENT_SEED=$(select_seed "$MC_VERSION")
    JAVA_MEMORY="${JAVA_MEMORY:-14G}"
    VIEW_DISTANCE="${VIEW_DISTANCE:-16}"
    MAX_PLAYERS="${MAX_PLAYERS:-30}"
    SERVER_IP=$(local_ip)
    START_BORDER="${START_BORDER:-10}"

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
    mkdir -p "$SERVER_DIR"/{mods,event/config,event/logs,world,logs,java}
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
        "fabric-api:Fabric API"
        "lithium:Lithium"
        "ferrite-core:FerriteCore"
        "krypton:Krypton"
        "lazydfu:LazyDFU"
        "memoryleakfix:MemoryLeakFix"
        "smoothboot-fabric:Smooth Boot"
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
        log "$MODS_FAILED mod(s) skipped (no build for MC $MC_VERSION)"
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
    mkdir -p "$SERVER_DIR/event"/{config,logs}

    cat > "$SERVER_DIR/event/config/event.json" <<CFG
{
  "event_name": "Co-op Speedrun",
  "mc_version": "$MC_VERSION",
  "seed": "$EVENT_SEED",
  "max_players": $MAX_PLAYERS,
  "start_border_diameter": $START_BORDER,
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
        echo "scoreboard objectives add csmc_time dummy" >&3
        sleep 1
        echo "stop" >&3
        wait "$server_pid" || true
    fi

    exec 3>&-
    rm -f /tmp/mc-console.pipe

    echo ""
    ok "Initial launch complete, server shut down cleanly"
    echo ""

    log "Installing hold-at-spawn datapack..."
    if write_hold_datapack; then
        ok "csmc_hold datapack installed into the world"
    fi
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
