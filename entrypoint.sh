#!/bin/bash

# ============================================================
# Entrypoint für Multi-Drone SITL
# Basiert auf dem Original von jonasvautherin/px4-gazebo-headless
# ============================================================

MAVSDK_REMOTE_PORT=${MAVSDK_REMOTE_PORT:-14540}

echo "==========================================="
echo "PX4 SITL Drone"
echo "==========================================="
echo "  MAV_SYS_ID:       ${MAV_SYS_ID}"
echo "  Home Position:    ${PX4_HOME_LAT}, ${PX4_HOME_LON}, ${PX4_HOME_ALT}m"
echo "  MAVSDK Port:      ${MAVSDK_REMOTE_PORT}"
echo "==========================================="

# ------------------------------------------------------------
# Argumente parsen
# ------------------------------------------------------------

OPTIND=1
vehicle=iris
world=empty

while getopts "h?v:w:" opt; do
    case "$opt" in
    v)  vehicle=$OPTARG
        ;;
    w)  world=$OPTARG
        ;;
    esac
done
shift $((OPTIND-1))

# ------------------------------------------------------------
# IPv4-Adresse ermitteln
# ------------------------------------------------------------

get_host_ipv4() {
    local ipv4=$(getent ahostsv4 host.docker.internal 2>/dev/null | head -1 | awk '{print $1}')
    if [ -n "$ipv4" ]; then
        echo "$ipv4"
    else
        ip route | awk '/default/ { print $3 }'
    fi
}

HOST_IP=$(get_host_ipv4)
echo "  Host IPv4:        ${HOST_IP}"
echo "==========================================="

if [ -z "$HOST_IP" ]; then
    echo "ERROR: Could not determine host IP address!"
    exit 1
fi

# ------------------------------------------------------------
# MAVLink Konfiguration anpassen (px4-rc.mavlink)
# ------------------------------------------------------------

CONFIG_FILE=${FIRMWARE_DIR}/build/px4_sitl_default/etc/init.d-posix/px4-rc.mavlink

echo "Configuring MAVLink..."
echo "  - Offboard port: ${MAVSDK_REMOTE_PORT}"
echo "  - Target IP: ${HOST_IP}"

# Backup
cp ${CONFIG_FILE} ${CONFIG_FILE}.bak

# API/Offboard Link: Port und IP setzen
sed -i 's|mavlink start -x -u $udp_offboard_port_local -r 4000000 -f -m onboard -o $udp_offboard_port_remote|mavlink start -x -u $udp_offboard_port_local -r 4000000 -f -m onboard -o '"${MAVSDK_REMOTE_PORT}"' -t '"${HOST_IP}"'|' ${CONFIG_FILE}

# GCS Link: IP setzen
sed -i 's|mavlink start -x -u $udp_gcs_port_local -r 4000000 -f$|mavlink start -x -u $udp_gcs_port_local -r 4000000 -f -t '"${HOST_IP}"'|' ${CONFIG_FILE}

# ------------------------------------------------------------
# MAV_SYS_ID in der rcS Datei setzen (VOR mavlink start!)
# ------------------------------------------------------------

RCS_FILE=${FIRMWARE_DIR}/build/px4_sitl_default/etc/init.d-posix/rcS

echo "Setting MAV_SYS_ID to ${MAV_SYS_ID} in rcS..."

# Füge param set MAV_SYS_ID direkt nach "Commander start" ein
# Das ist früh genug, bevor mavlink gestartet wird
sed -i '/^commander start/a param set MAV_SYS_ID '"${MAV_SYS_ID}"'' ${RCS_FILE}

# Verify
echo "Verifying MAV_SYS_ID in rcS:"
grep -n "MAV_SYS_ID" ${RCS_FILE} || echo "  (not found - will add differently)"

# Falls das nicht funktioniert, alternative Methode:
# Füge es am Anfang der rcS Datei ein (nach den ersten Kommentaren)
if ! grep -q "MAV_SYS_ID" ${RCS_FILE}; then
    echo "Using alternative method to set MAV_SYS_ID..."
    sed -i '1a param set MAV_SYS_ID '"${MAV_SYS_ID}"'' ${RCS_FILE}
fi

echo "Verifying MAVLink configuration:"
grep "mavlink start" ${CONFIG_FILE} | head -2

# ------------------------------------------------------------
# Virtual Framebuffer starten
# ------------------------------------------------------------

Xvfb :99 -screen 0 1600x1200x24+32 &

# RTSP Proxy starten
${SITL_RTSP_PROXY}/build/sitl_rtsp_proxy &

# ------------------------------------------------------------
# PX4 SITL starten
# ------------------------------------------------------------

cd ${FIRMWARE_DIR}

echo ""
echo "Starting PX4 SITL with vehicle=${vehicle}, world=${world}..."

HEADLESS=1 make px4_sitl gazebo_${vehicle}__${world}
