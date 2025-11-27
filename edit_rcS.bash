#!/bin/bash
# =============================================================================
# edit_rcS.bash - MAVLink Konfiguration für Multi-Drone SITL
# =============================================================================
# Basierend auf andrekuros/px4-sitl-headless-flex
#
# Argumente:
#   $1 - MAV_SYS_ID (System ID)
#   $2 - GCS IP
#   $3 - API IP
#   $4 - GCS Port
#   $5 - API Port
# =============================================================================

function is_ip_valid {
    if [[ $1 =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        return 0
    else
        echo "Invalid IP: $1"
        return 1
    fi
}

function is_docker_vm {
    getent hosts host.docker.internal >/dev/null 2>&1
    return $?
}

function get_vm_host_ip {
    if ! is_docker_vm; then
        echo "ERROR: this is not running from a docker VM!"
        exit 1
    fi

    echo "$(getent hosts host.docker.internal | awk '{ print $1 }')"
}

# Validierung
if ! is_ip_valid $2 || ! is_ip_valid $3; then
    echo "ERROR: Invalid IP addresses provided"
    exit 1
fi

echo "==========================================="
echo "Configuring MAVLink..."
echo "==========================================="
echo "  MAV_SYS_ID:  $1"
echo "  GCS:         $2:$4"
echo "  API:         $3:$5"
echo "==========================================="

GCS_PARAM="-t $2"
API_PARAM="-t $3"

# Broadcast doesn't work with docker from a VM (macOS or Windows)
# Default to the vm host (host.docker.internal)
if is_docker_vm; then
    VM_HOST=$(get_vm_host_ip)
    GCS_PARAM=${GCS_PARAM:-"-t ${VM_HOST}"}
    API_PARAM=${API_PARAM:-"-t ${VM_HOST}"}
fi

# Konfigurationsdateien
CONFIG_FILE=${FIRMWARE_DIR}/build/px4_sitl_default/etc/init.d-posix/rcS
CONFIG_MAV=${FIRMWARE_DIR}/build/px4_sitl_default/etc/init.d-posix/px4-rc.mavlink
CONFIG_PARAMS=${FIRMWARE_DIR}/build/px4_sitl_default/etc/init.d-posix/px4-rc.params

# GCS MAVLink Link konfigurieren
sed -i "s/mavlink start \-x \-u \$udp_gcs_port_local -r 4000000 -f/mavlink start -x -u \$udp_gcs_port_local -r 4000000 -f ${GCS_PARAM} -o ${4}/" ${CONFIG_MAV}

# API/Offboard MAVLink Link konfigurieren
sed -i "s/mavlink start -x -u \$udp_offboard_port_local -r 4000000 -f -m onboard -o \$udp_offboard_port_remote/mavlink start -x -u \$udp_offboard_port_local -r 4000000 -f -m onboard -o ${5} ${API_PARAM}/" ${CONFIG_MAV}

# MAV_SYS_ID setzen (ersetzt dynamische Berechnung)
sed -i "s/param set MAV_SYS_ID \$((px4_instance+1))/param set MAV_SYS_ID ${1}/" ${CONFIG_FILE}

# MAVLink 2 Protokoll erzwingen (wichtig für Stabilität!)
echo 'param set MAV_PROTO_VER 2' >> ${CONFIG_PARAMS}

echo ""
echo "MAVLink configuration applied."