#!/bin/bash

# =============================================================================
# entrypoint.sh - Multi-Drone PX4 SITL (basierend auf andrekuros Ansatz)
# =============================================================================

function show_help {
    echo ""
    echo "Usage: ${0} [-h | -veh VEHICLE | -world WORLD | -sysid SYSID |"
    echo "    -aip IP_API | -aport PORT_API | -gip IP_GCS | -gport PORT_GCS]"
    echo ""
}

# Defaults
vehicle=iris
world=empty
SYS_ID=${MAV_SYS_ID:-1}
IP_API=${API_IP:-127.0.0.1}
PORT_API=${MAVSDK_REMOTE_PORT:-14540}
IP_GCS=${GCS_IP:-127.0.0.1}
PORT_GCS=${GCS_PORT:-14550}

# Parse command line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
         -help  | --help )   show_help; exit 0;;
         -veh   | --veh  )   vehicle=$2; shift;;
         -world | --world)   world=$2; shift;;
         -sysid | --sysid)   SYS_ID=$2; shift;;
         -aip   | --aip  )   IP_API=$2; shift;;
         -aport | --aport)   PORT_API=$2; shift;;
         -gip   | --gip  )   IP_GCS=$2; shift;;
         -gport | --gport)   PORT_GCS=$2; shift;;
         *)
            # Fallback: erstes Argument als IP (wie Jonas)
            if [[ $1 =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || [[ $1 == "host.docker.internal" ]]; then
                IP_API=$1
                IP_GCS=$1
            fi
            ;;
    esac
    shift
done

# Auto-detect host IP if localhost
if [[ "$IP_API" == "127.0.0.1" ]]; then
    HOST_IP=$(getent ahostsv4 host.docker.internal 2>/dev/null | head -1 | awk '{print $1}')
    if [[ -n "$HOST_IP" ]]; then
        IP_API=$HOST_IP
        IP_GCS=$HOST_IP
    fi
fi

echo "==========================================="
echo "PX4 SITL Drone"
echo "==========================================="
echo "  MAV_SYS_ID:    ${SYS_ID}"
echo "  API:           ${IP_API}:${PORT_API}"
echo "  GCS:           ${IP_GCS}:${PORT_GCS}"
echo "  Vehicle:       ${vehicle}"
echo "  World:         ${world}"
echo "==========================================="

# Start Xvfb
Xvfb :99 -screen 0 1600x1200x24+32 &

# Start RTSP Proxy
${SITL_RTSP_PROXY}/build/sitl_rtsp_proxy &

# -----------------------------------------------------------------------------
# MAVLink Konfiguration (wie andrekuros)
# -----------------------------------------------------------------------------

CONFIG_FILE=${FIRMWARE_DIR}/build/px4_sitl_default/etc/init.d-posix/rcS
CONFIG_MAV=${FIRMWARE_DIR}/build/px4_sitl_default/etc/init.d-posix/px4-rc.mavlink
CONFIG_PARAMS=${FIRMWARE_DIR}/build/px4_sitl_default/etc/init.d-posix/px4-rc.params

GCS_PARAM="-t ${IP_GCS}"
API_PARAM="-t ${IP_API}"

# GCS Link konfigurieren
sed -i "s|mavlink start -x -u \$udp_gcs_port_local -r 4000000 -f|mavlink start -x -u \$udp_gcs_port_local -r 4000000 -f ${GCS_PARAM} -o ${PORT_GCS}|" ${CONFIG_MAV}

# API/Offboard Link konfigurieren
sed -i "s|mavlink start -x -u \$udp_offboard_port_local -r 4000000 -f -m onboard -o \$udp_offboard_port_remote|mavlink start -x -u \$udp_offboard_port_local -r 4000000 -f -m onboard -o ${PORT_API} ${API_PARAM}|" ${CONFIG_MAV}

# MAV_SYS_ID ersetzen (nicht hinzufügen!)
sed -i "s|param set MAV_SYS_ID \$((px4_instance+1))|param set MAV_SYS_ID ${SYS_ID}|" ${CONFIG_FILE}

# WICHTIG: MAVLink 2 Protokoll erzwingen!
echo "param set MAV_PROTO_VER 2" >> ${CONFIG_PARAMS}

# Verifikation
echo ""
echo "MAVLink Configuration:"
grep "mavlink start" ${CONFIG_MAV} | head -2
echo ""

# -----------------------------------------------------------------------------
# PX4 SITL starten
# -----------------------------------------------------------------------------

cd ${FIRMWARE_DIR}
HEADLESS=1 make px4_sitl gazebo_${vehicle}__${world}