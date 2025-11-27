#!/bin/bash
# =============================================================================
# entrypoint.sh - Multi-Drone PX4 SITL Startskript
# =============================================================================
# Basierend auf andrekuros/px4-sitl-headless-flex
# Angepasst für Verwendung mit docker-compose und Umgebungsvariablen
#
# Unterstützte Umgebungsvariablen:
#   MAV_SYS_ID    - MAVLink System ID (1-255)
#   SIM_SPEED     - Simulationsgeschwindigkeit (1 = Echtzeit)
#   VEHICLE       - Fahrzeugtyp (iris, typhoon_h480, plane, etc.)
#   WORLD         - Gazebo-Welt (empty, baylands, etc.)
#   API_IP        - IP für MAVSDK/API Verbindung
#   API_PORT      - Port für MAVSDK/API (14540, 14541, ...)
#   GCS_IP        - IP für QGroundControl
#   GCS_PORT      - Port für QGroundControl (14550, 14551, ...)
#   PX4_PARAMS    - Zusätzliche PX4-Parameter (kommasepariert)
#   PX4_HOME_LAT  - Startposition Breitengrad
#   PX4_HOME_LON  - Startposition Längengrad
#   PX4_HOME_ALT  - Startposition Höhe
# =============================================================================

function show_help {
    echo ""
    echo "PX4 Multi-Drone SITL Container"
    echo ""
    echo "Umgebungsvariablen:"
    echo "  MAV_SYS_ID    MAVLink System ID (default: 1)"
    echo "  SIM_SPEED     Simulationsgeschwindigkeit (default: 1)"
    echo "  VEHICLE       Fahrzeugtyp (default: iris)"
    echo "  WORLD         Gazebo-Welt (default: empty)"
    echo "  API_IP        MAVSDK IP (default: auto-detect)"
    echo "  API_PORT      MAVSDK Port (default: 14540)"
    echo "  GCS_IP        QGroundControl IP (default: auto-detect)"
    echo "  GCS_PORT      QGroundControl Port (default: 14550)"
    echo "  PX4_PARAMS    Zusätzliche Parameter (z.B. 'MPC_XY_CRUISE 20,MIS_DIST_1WP 3000')"
    echo ""
}

# -----------------------------------------------------------------------------
# Konfiguration aus Umgebungsvariablen laden
# -----------------------------------------------------------------------------
MAV_SYS_ID=${MAV_SYS_ID:-1}
SIM_SPEED=${SIM_SPEED:-1}
VEHICLE=${VEHICLE:-iris}
WORLD=${WORLD:-empty}
API_PORT=${API_PORT:-14540}
GCS_PORT=${GCS_PORT:-14550}
PX4_PARAMS=${PX4_PARAMS:-""}

# -----------------------------------------------------------------------------
# Host-IP automatisch erkennen
# -----------------------------------------------------------------------------
function get_host_ip {
    # Versuche zuerst host.docker.internal (Docker Desktop auf Mac/Windows)
    local ipv4=$(getent ahostsv4 host.docker.internal 2>/dev/null | head -1 | awk '{print $1}')

    if [ -n "$ipv4" ]; then
        echo "$ipv4"
    else
        # Fallback: Default-Gateway (Linux)
        ip route | awk '/default/ { print $3 }'
    fi
}

# IP-Adressen setzen (falls nicht explizit angegeben)
if [ -z "$API_IP" ] || [ "$API_IP" == "127.0.0.1" ]; then
    API_IP=$(get_host_ip)
fi

if [ -z "$GCS_IP" ] || [ "$GCS_IP" == "127.0.0.1" ]; then
    GCS_IP=$(get_host_ip)
fi

# Fallback falls keine IP gefunden
API_IP=${API_IP:-127.0.0.1}
GCS_IP=${GCS_IP:-127.0.0.1}

# -----------------------------------------------------------------------------
# Startup-Banner
# -----------------------------------------------------------------------------
echo "==========================================="
echo "PX4 SITL Multi-Drone Container"
echo "==========================================="
echo "  MAV_SYS_ID:     ${MAV_SYS_ID}"
echo "  Vehicle:        ${VEHICLE}"
echo "  World:          ${WORLD}"
echo "  Sim Speed:      ${SIM_SPEED}x"
echo "  API:            ${API_IP}:${API_PORT}"
echo "  GCS:            ${GCS_IP}:${GCS_PORT}"
echo "  Home Position:  ${PX4_HOME_LAT}, ${PX4_HOME_LON}, ${PX4_HOME_ALT}m"
if [ -n "$PX4_PARAMS" ]; then
echo "  Custom Params:  ${PX4_PARAMS}"
fi
echo "==========================================="

# -----------------------------------------------------------------------------
# Xvfb (Virtual Framebuffer) starten
# -----------------------------------------------------------------------------
Xvfb :99 -screen 0 1600x1200x24+32 &

# -----------------------------------------------------------------------------
# RTSP Proxy für Video-Streaming starten
# -----------------------------------------------------------------------------
${SITL_RTSP_PROXY}/build/sitl_rtsp_proxy &

# -----------------------------------------------------------------------------
# MAVLink konfigurieren
# -----------------------------------------------------------------------------
source ${WORKSPACE_DIR}/edit_rcS.bash ${MAV_SYS_ID} ${GCS_IP} ${API_IP} ${GCS_PORT} ${API_PORT}

# -----------------------------------------------------------------------------
# Zusätzliche PX4-Parameter setzen
# -----------------------------------------------------------------------------
CONFIG_PARAMS=${FIRMWARE_DIR}/build/px4_sitl_default/etc/init.d-posix/px4-rc.params

if [ -n "$PX4_PARAMS" ]; then
    echo ""
    echo "Setting custom PX4 parameters..."

    # Parameter sind kommasepariert: "MPC_XY_CRUISE 20,MIS_DIST_1WP 3000"
    IFS=',' read -ra PARAMS_ARRAY <<< "$PX4_PARAMS"
    for param in "${PARAMS_ARRAY[@]}"; do
        # Whitespace trimmen
        param=$(echo "$param" | xargs)
        if [ -n "$param" ]; then
            echo "  param set ${param}"
            echo "param set ${param}" >> ${CONFIG_PARAMS}
        fi
    done
fi

# -----------------------------------------------------------------------------
# Simulationsgeschwindigkeit setzen
# -----------------------------------------------------------------------------
export PX4_SIM_SPEED_FACTOR=${SIM_SPEED}

# -----------------------------------------------------------------------------
# Verifikation der Konfiguration
# -----------------------------------------------------------------------------
echo ""
echo "MAVLink Links:"
grep "mavlink start" ${FIRMWARE_DIR}/build/px4_sitl_default/etc/init.d-posix/px4-rc.mavlink | head -2
echo ""

# -----------------------------------------------------------------------------
# PX4 SITL mit Gazebo starten
# -----------------------------------------------------------------------------
cd ${FIRMWARE_DIR}

echo "Starting PX4 SITL..."
echo "  Command: HEADLESS=1 make px4_sitl gazebo_${VEHICLE}__${WORLD}"
echo ""

HEADLESS=1 make px4_sitl gazebo_${VEHICLE}__${WORLD}