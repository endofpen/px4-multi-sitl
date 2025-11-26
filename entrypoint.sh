#!/bin/bash

# =============================================================================
# entrypoint.sh - Multi-Drone PX4 SITL Startskript
# =============================================================================
#
# Dieses Script startet PX4 SITL mit Gazebo und konfiguriert:
#   - MAV_SYS_ID für Multi-Drone Unterscheidung
#   - MAVLink UDP-Ports für Host-Kommunikation
#   - IPv4-Adresse des Hosts (vermeidet IPv6-Probleme)
#
# Basiert auf dem Original von jonasvautherin/px4-gazebo-headless
# Erweitert für Multi-Drone Szenarien
#
# Umgebungsvariablen:
#   MAV_SYS_ID         - Eindeutige MAVLink System-ID (1-255)
#   MAVSDK_REMOTE_PORT - UDP-Port für ausgehende MAVLink-Pakete
#   PX4_HOME_LAT       - Startposition Breitengrad
#   PX4_HOME_LON       - Startposition Längengrad
#   PX4_HOME_ALT       - Startposition Höhe (m)
#
# Verwendung:
#   ./entrypoint.sh [-v vehicle] [-w world]
#
# Beispiel:
#   MAV_SYS_ID=2 MAVSDK_REMOTE_PORT=14541 ./entrypoint.sh -v iris -w empty
#
# =============================================================================

# -----------------------------------------------------------------------------
# Konfiguration
# -----------------------------------------------------------------------------

# MAVSDK_REMOTE_PORT: Der UDP-Port an den PX4 MAVLink-Pakete sendet.
# Der MAVSDK-Server auf dem Host lauscht auf diesem Port.
# Jede Drohne braucht einen eigenen Port:
#   Drohne 1: 14540
#   Drohne 2: 14541
#   Drohne 3: 14542
#   etc.
MAVSDK_REMOTE_PORT=${MAVSDK_REMOTE_PORT:-14540}

# -----------------------------------------------------------------------------
# Startup-Banner
# -----------------------------------------------------------------------------

echo "==========================================="
echo "PX4 SITL Drone"
echo "==========================================="
echo "  MAV_SYS_ID:       ${MAV_SYS_ID}"
echo "  Home Position:    ${PX4_HOME_LAT}, ${PX4_HOME_LON}, ${PX4_HOME_ALT}m"
echo "  MAVSDK Port:      ${MAVSDK_REMOTE_PORT}"
echo "==========================================="

# -----------------------------------------------------------------------------
# Argumente parsen
# -----------------------------------------------------------------------------
# Unterstützt dieselben Argumente wie das Original-Image:
#   -v VEHICLE  : Fahrzeugtyp (default: iris)
#   -w WORLD    : Gazebo-Welt (default: empty)
#
# Verfügbare Fahrzeuge: iris, typhoon_h480, plane, rover, etc.
# Verfügbare Welten: empty, baylands, mcmillan_airfield, etc.

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

# -----------------------------------------------------------------------------
# Host IPv4-Adresse ermitteln
# -----------------------------------------------------------------------------
# Problem: Auf Mac gibt `getent hosts host.docker.internal` manchmal IPv6 zurück,
# was PX4 nicht versteht: "ERROR [mavlink] invalid partner ip '::ffff:...'"
#
# Lösung: Explizit IPv4 anfordern mit `getent ahostsv4`
#
# Fallback: Default-Gateway aus Routing-Tabelle (für Linux ohne host.docker.internal)

get_host_ipv4() {
    # Versuche zuerst host.docker.internal (Docker Desktop auf Mac/Windows)
    local ipv4=$(getent ahostsv4 host.docker.internal 2>/dev/null | head -1 | awk '{print $1}')

    if [ -n "$ipv4" ]; then
        echo "$ipv4"
    else
        # Fallback: Default-Gateway (funktioniert auf Linux)
        ip route | awk '/default/ { print $3 }'
    fi
}

HOST_IP=$(get_host_ipv4)
echo "  Host IPv4:        ${HOST_IP}"
echo "==========================================="

# Validierung
if [ -z "$HOST_IP" ]; then
    echo "ERROR: Could not determine host IP address!"
    echo "Make sure 'host.docker.internal' is resolvable or a default route exists."
    exit 1
fi

# -----------------------------------------------------------------------------
# MAVLink Konfiguration anpassen
# -----------------------------------------------------------------------------
# PX4 verwendet px4-rc.mavlink um MAVLink-Instanzen zu starten.
# Wir müssen zwei Dinge ändern:
#
# 1. API/Offboard Link (für MAVSDK):
#    - Port ändern von Variable ($udp_offboard_port_remote) zu festem Port
#    - Target-IP hinzufügen (-t <IP>)
#
# 2. GCS Link (für QGroundControl):
#    - Target-IP hinzufügen (-t <IP>) um IPv6-Fehler zu vermeiden
#
# Original-Zeilen:
#   mavlink start -x -u $udp_gcs_port_local -r 4000000 -f
#   mavlink start -x -u $udp_offboard_port_local -r 4000000 -f -m onboard -o $udp_offboard_port_remote
#
# Geänderte Zeilen:
#   mavlink start -x -u $udp_gcs_port_local -r 4000000 -f -t <HOST_IP>
#   mavlink start -x -u $udp_offboard_port_local -r 4000000 -f -m onboard -o <PORT> -t <HOST_IP>

CONFIG_FILE=${FIRMWARE_DIR}/build/px4_sitl_default/etc/init.d-posix/px4-rc.mavlink

echo "Configuring MAVLink..."
echo "  - Offboard port: ${MAVSDK_REMOTE_PORT}"
echo "  - Target IP: ${HOST_IP}"

# Backup erstellen (für Debugging)
cp ${CONFIG_FILE} ${CONFIG_FILE}.bak

# 1. API/Offboard Link konfigurieren
# Dies ist der Link über den MAVSDK kommuniziert.
# -o <PORT>  : Remote-Port (wo der MAVSDK-Server lauscht)
# -t <IP>    : Target-IP (Host-System)
sed -i 's|mavlink start -x -u $udp_offboard_port_local -r 4000000 -f -m onboard -o $udp_offboard_port_remote|mavlink start -x -u $udp_offboard_port_local -r 4000000 -f -m onboard -o '"${MAVSDK_REMOTE_PORT}"' -t '"${HOST_IP}"'|' ${CONFIG_FILE}

# 2. GCS Link konfigurieren
# Dies ist der Link für QGroundControl (optional, aber verhindert IPv6-Fehler).
# Das '$' am Ende ist wichtig um nur Zeilen zu matchen die dort enden!
sed -i 's|mavlink start -x -u $udp_gcs_port_local -r 4000000 -f$|mavlink start -x -u $udp_gcs_port_local -r 4000000 -f -t '"${HOST_IP}"'|' ${CONFIG_FILE}

# -----------------------------------------------------------------------------
# MAV_SYS_ID konfigurieren
# -----------------------------------------------------------------------------
# MAV_SYS_ID ist die eindeutige Kennung jeder Drohne im MAVLink-Netzwerk.
# Jede Drohne MUSS eine andere ID haben (1-255).
#
# Bei echten Drohnen wird dies in QGroundControl unter Parameters → MAV_SYS_ID gesetzt.
# In der Simulation setzen wir es hier dynamisch.
#
# Methode: `param set` Befehl in die rcS Datei einfügen
# Dies wird ausgeführt nachdem der Commander gestartet ist, aber bevor MAVLink startet.

RCS_FILE=${FIRMWARE_DIR}/build/px4_sitl_default/etc/init.d-posix/rcS

echo "Setting MAV_SYS_ID to ${MAV_SYS_ID} in rcS..."

# Füge param set MAV_SYS_ID nach "commander start" ein
# Der sed-Befehl fügt eine neue Zeile NACH dem Match ein
sed -i '/^commander start/a param set MAV_SYS_ID '"${MAV_SYS_ID}"'' ${RCS_FILE}

# Verifikation
echo "Verifying MAV_SYS_ID in rcS:"
grep -n "MAV_SYS_ID" ${RCS_FILE} || echo "  WARNING: MAV_SYS_ID not found in rcS"

echo "Verifying MAVLink configuration:"
grep "mavlink start" ${CONFIG_FILE} | head -2

# -----------------------------------------------------------------------------
# Virtual Framebuffer starten
# -----------------------------------------------------------------------------
# Gazebo benötigt einen Display, auch im headless Modus.
# Xvfb (X Virtual Framebuffer) simuliert einen Bildschirm.
# :99 ist die Display-Nummer, 1600x1200x24+32 die Auflösung und Farbtiefe.

Xvfb :99 -screen 0 1600x1200x24+32 &

# -----------------------------------------------------------------------------
# RTSP Proxy starten
# -----------------------------------------------------------------------------
# Optional: Ermöglicht Video-Streaming von der simulierten Kamera.
# Kann ignoriert werden wenn kein Video benötigt wird.

${SITL_RTSP_PROXY}/build/sitl_rtsp_proxy &

# -----------------------------------------------------------------------------
# PX4 SITL mit Gazebo starten
# -----------------------------------------------------------------------------
# HEADLESS=1    : Kein Gazebo GUI (wichtig für Server/Container)
# make px4_sitl : Baut und startet PX4 in SITL-Modus
# gazebo_X__Y   : X = Fahrzeugtyp, Y = Welt
#
# Dieser Befehl:
# 1. Prüft ob alles gebaut ist (~30-60 Sekunden)
# 2. Startet Gazebo Server (gzserver)
# 3. Spawnt das Fahrzeug-Modell
# 4. Startet PX4 SITL und verbindet es mit Gazebo
# 5. Führt die Startup-Scripts aus (rcS, px4-rc.mavlink, etc.)

cd ${FIRMWARE_DIR}

echo ""
echo "Starting PX4 SITL with vehicle=${vehicle}, world=${world}..."

HEADLESS=1 make px4_sitl gazebo_${vehicle}__${world}

# =============================================================================
# Ende des Scripts
# =============================================================================
# Wenn PX4 beendet wird (Ctrl+C oder Fehler), endet auch der Container.
# Alle Hintergrundprozesse (Xvfb, RTSP Proxy) werden automatisch beendet.
# =============================================================================
