# =============================================================================
# Dockerfile für PX4 Multi-Drone SITL Simulation
# =============================================================================
#
# Dieses Dockerfile erweitert das jonasvautherin/px4-gazebo-headless Image
# um Multi-Drone Unterstützung mit konfigurierbaren MAV_SYS_IDs und Ports.
#
# Basis-Image: jonasvautherin/px4-gazebo-headless:1.14.3
#   - Enthält PX4 Autopilot Firmware (SITL Build)
#   - Enthält Gazebo Classic Simulator
#   - Konfiguriert für headless Betrieb (kein GUI)
#
# Änderungen gegenüber dem Basis-Image:
#   - Eigenes entrypoint.sh für Multi-Drone Konfiguration
#   - Unterstützung für MAV_SYS_ID Umgebungsvariable
#   - Unterstützung für MAVSDK_REMOTE_PORT Umgebungsvariable
#   - IPv4-erzwungene Host-Kommunikation (vermeidet IPv6-Probleme auf Mac)
#
# =============================================================================

# -----------------------------------------------------------------------------
# Basis-Image
# -----------------------------------------------------------------------------
# Version 1.14.3 gewählt für Stabilität und Kompatibilität
# Neuere Versionen können andere Verzeichnisstrukturen haben!
FROM jonasvautherin/px4-gazebo-headless:1.14.3

# -----------------------------------------------------------------------------
# Eigenes Entrypoint-Script
# -----------------------------------------------------------------------------
# Ersetzt das Original-Entrypoint um folgende Funktionen hinzuzufügen:
#   - MAV_SYS_ID Konfiguration (für Multi-Drone)
#   - MAVSDK_REMOTE_PORT Konfiguration (für Port-Isolation)
#   - IPv4-erzwungene Host-IP Ermittlung
#   - MAVLink Target-IP Konfiguration
COPY entrypoint.sh /root/entrypoint.sh
RUN chmod +x /root/entrypoint.sh

# -----------------------------------------------------------------------------
# Standard-Umgebungsvariablen
# -----------------------------------------------------------------------------
# Diese können beim Container-Start überschrieben werden via:
#   docker run -e MAV_SYS_ID=2 ...
#   oder in docker-compose.yml unter 'environment:'

# MAV_SYS_ID: Eindeutige MAVLink System-ID (1-255)
# WICHTIG: Muss für jede Drohne unterschiedlich sein!
# Bei echten Drohnen wird dieser Parameter in der Firmware gesetzt.
ENV MAV_SYS_ID=1

# MAVSDK_REMOTE_PORT: UDP-Port an den MAVLink-Pakete gesendet werden
# Jede Drohne braucht einen eigenen Port um Konflikte zu vermeiden.
# Der MAVSDK-Server lauscht dann auf diesem Port.
ENV MAVSDK_REMOTE_PORT=14540

# PX4_HOME_*: Simulierte GPS-Startposition
# Wird von PX4 SITL für die initiale Position verwendet.
# Alle Drohnen sollten leicht unterschiedliche Positionen haben,
# um Kollisionen in der Simulation zu vermeiden.
ENV PX4_HOME_LAT=51.2330
ENV PX4_HOME_LON=6.7833
ENV PX4_HOME_ALT=38.0

# -----------------------------------------------------------------------------
# Entrypoint
# -----------------------------------------------------------------------------
# Startet unser angepasstes Script statt dem Original
ENTRYPOINT ["/root/entrypoint.sh"]

# -----------------------------------------------------------------------------
# Build-Informationen
# -----------------------------------------------------------------------------
# Build mit: docker build -t px4-multi-sitl .
# Oder via: docker-compose build
#
# Das Image ist ca. 3-4 GB groß (PX4 + Gazebo + Dependencies)
# -----------------------------------------------------------------------------
