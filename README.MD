# PX4 Multi-Drone SITL Simulation

Dieses Setup ermöglicht die gleichzeitige Simulation mehrerer PX4-Drohnen in Docker-Containern,
die über MAVSDK-Server mit einer Kotlin-Anwendung kommunizieren.

## Architektur

```
┌──────────────────────────────────────────────────────────────────────────────────────┐
│                              HOST SYSTEM (Mac/Linux/Windows)                         │
│                                                                                      │
│  ┌──────────────────────────────────────────────────────────────────────────────┐    │
│  │                           Docker Environment                                 │    │
│  │                                                                              │    │
│  │  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐            │    │
│  │  │  px4-drone-1     │  │  px4-drone-2     │  │  px4-drone-3     │            │    │
│  │  │  ──────────────  │  │  ──────────────  │  │  ──────────────  │            │    │
│  │  │  MAV_SYS_ID: 1   │  │  MAV_SYS_ID: 2   │  │  MAV_SYS_ID: 3   │            │    │
│  │  │  UDP → 14540     │  │  UDP → 14541     │  │  UDP → 14542     │            │    │
│  │  │  PX4 + Gazebo    │  │  PX4 + Gazebo    │  │  PX4 + Gazebo    │            │    │
│  │  └────────┬─────────┘  └────────┬─────────┘  └────────┬─────────┘            │    │
│  │           │                     │                     │                      │    │
│  └───────────┼─────────────────────┼─────────────────────┼──────────────────────┘    │
│              │ UDP                 │ UDP                 │ UDP                       │
│              │ MAVLink             │ MAVLink             │ MAVLink                   │
│              ▼                     ▼                     ▼                           │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐                    │
│  │  MAVSDK-Server   │  │  MAVSDK-Server   │  │  MAVSDK-Server   │                    │
│  │  ──────────────  │  │  ──────────────  │  │  ──────────────  │                    │
│  │  UDP: 14540      │  │  UDP: 14541      │  │  UDP: 14542      │                    │
│  │  gRPC: 50051     │  │  gRPC: 50052     │  │  gRPC: 50053     │                    │
│  └────────┬─────────┘  └────────┬─────────┘  └────────┬─────────┘                    │
│           │ gRPC                │ gRPC                │ gRPC                         │
│           └─────────────────────┼─────────────────────┘                              │
│                                 ▼                                                    │
│                    ┌─────────────────────────┐                                       │
│                    │    Kotlin Application   │                                       │
│                    │    ─────────────────    │                                       │
│                    │    MAVSDK-Java Client   │                                       │
│                    │    Drone Control Logic  │                                       │
│                    └─────────────────────────┘                                       │
│                                                                                      │
└──────────────────────────────────────────────────────────────────────────────────────┘
```

## Datenfluss

1. **PX4 SITL** (im Docker-Container) simuliert die Drohnen-Firmware und Sensoren
2. **Gazebo** (headless) simuliert die Physik und Umgebung
3. **MAVLink UDP** transportiert Telemetrie und Kommandos vom Container zum Host
4. **MAVSDK-Server** übersetzt MAVLink ↔ gRPC
5. **Kotlin-Anwendung** steuert die Drohnen über MAVSDK-Java

## Dateien

```
px4-multi-sitl/
├── README.md           # Diese Dokumentation
├── Dockerfile          # Docker-Image Definition
├── entrypoint.sh       # Container-Startskript
└── docker-compose.yml  # Multi-Container Orchestrierung
```

## Voraussetzungen

- Docker Desktop (Mac/Windows) oder Docker Engine (Linux)
- docker-compose
- MAVSDK-Server Binary (passend zum Betriebssystem)
- Ca. 4 GB RAM pro Drohne

## Quick Start

### 1. Image bauen

```bash
cd px4-multi-sitl
docker-compose build
```

### 2. Drohnen starten

```bash
# Einzelne Drohne
docker-compose up drone1

# Mehrere Drohnen (separate Terminals)
docker-compose up drone1
docker-compose up drone2
docker-compose up drone3

# Alle Drohnen gleichzeitig
docker-compose up
```

### 3. MAVSDK-Server starten

Für jede Drohne einen separaten MAVSDK-Server in einem eigenen Terminal:

```bash
# Drohne 1
./mavsdk_server -p 50051 udp://:14540

# Drohne 2
./mavsdk_server -p 50052 udp://:14541

# Drohne 3
./mavsdk_server -p 50053 udp://:14542
```

### 4. Verbindung prüfen

Bei erfolgreicher Verbindung zeigt der MAVSDK-Server:

```
[Info ] New system on: 127.0.0.1:xxxxx (with sysid: 1)
[Info ] System discovered
[Info ] Server set to listen on 0.0.0.0:50051
```

**Wichtig:** Die `sysid` muss der `MAV_SYS_ID` der jeweiligen Drohne entsprechen!

## Konfiguration

### Drohnen-Parameter (docker-compose.yml)

| Parameter | Beschreibung | Beispiel |
|-----------|--------------|----------|
| `MAV_SYS_ID` | Eindeutige MAVLink System-ID (1-255) | `1`, `2`, `3` |
| `MAVSDK_REMOTE_PORT` | UDP-Port für ausgehende MAVLink-Pakete | `14540`, `14541`, `14542` |
| `PX4_HOME_LAT` | Startposition Breitengrad | `51.2330` |
| `PX4_HOME_LON` | Startposition Längengrad | `6.7833` |
| `PX4_HOME_ALT` | Startposition Höhe (Meter über Meeresspiegel) | `38.0` |

### Port-Schema

| Drohne | MAV_SYS_ID | MAVLink UDP | MAVSDK gRPC |
|--------|------------|-------------|-------------|
| 1 | 1 | 14540 | 50051 |
| 2 | 2 | 14541 | 50052 |
| 3 | 3 | 14542 | 50053 |
| n | n | 14539+n | 50050+n |


## Troubleshooting

### Problem: "MAVLink only on localhost"

**Ursache:** Die MAVLink-Konfiguration sendet nicht an den Host.

**Lösung:** Das `entrypoint.sh` muss die `-t <HOST_IP>` Parameter korrekt setzen.
Prüfe die Logs auf:
```
Verifying MAVLink configuration...
mavlink start ... -t 192.168.65.254
```

### Problem: "Address already in use"

**Ursache:** Mehrere Drohnen versuchen denselben Port zu nutzen.

**Lösung:** Jede Drohne braucht einen eindeutigen `MAVSDK_REMOTE_PORT`.

### Problem: "sysid: 1" bei allen Drohnen

**Ursache:** `MAV_SYS_ID` wird nicht korrekt gesetzt.

**Lösung:** Prüfe die Logs auf:
```
* MAV_SYS_ID: curr: 1 -> new: 2
```

### Problem: IPv6-Fehler

**Symptom:** `ERROR [mavlink] invalid partner ip '::ffff:...'`

**Ursache:** `getent hosts` gibt IPv6 statt IPv4 zurück.

**Lösung:** Das `entrypoint.sh` verwendet `getent ahostsv4` für explizite IPv4-Auflösung.

## Real-World Umstellung

Dieses Setup ist für den späteren Einsatz mit echten Drohnen vorbereitet.

### Was sich ändert

| Aspekt | Simulation | Real-World |
|--------|------------|------------|
| PX4 | Docker-Container | Drohnen-Hardware |
| MAV_SYS_ID | Umgebungsvariable | QGroundControl Parameter |
| Kommunikation | Docker → Host | WiFi / Telemetrie |
| Connection String | `udp://:14540` | `udp://:14540` oder `serial:///dev/ttyUSB0:57600` |

### Was gleich bleibt

- ✅ MAVSDK-Server Architektur
- ✅ gRPC API
- ✅ Kotlin-Anwendungscode
- ✅ MAV_SYS_ID Konzept

### Typische Real-World Connection Strings

```bash
# WiFi (Drohne sendet aktiv)
./mavsdk_server -p 50051 udp://:14540

# WiFi (GCS verbindet aktiv)
./mavsdk_server -p 50051 udp://192.168.1.100:14540

# Telemetrie-Modul (SiK Radio, 3DR)
./mavsdk_server -p 50051 serial:///dev/ttyUSB0:57600

# USB-Direktverbindung
./mavsdk_server -p 50051 serial:///dev/tty.usbmodem1:115200
```

### Checkliste für Real-World

1. [ ] MAV_SYS_ID auf jeder Drohne konfigurieren (QGroundControl → Parameters)
2. [ ] Netzwerk-Topologie planen (WiFi AP vs. gemeinsames Netzwerk)
3. [ ] Connection Strings in Kotlin-Config anpassen
4. [ ] Firewall-Regeln prüfen (UDP-Ports öffnen)
5. [ ] Latenz und Zuverlässigkeit testen

## Logs und Debugging

### Container-Logs anzeigen

```bash
docker-compose logs drone1
docker-compose logs -f drone1  # Live-Follow
```

### In Container einsteigen

```bash
docker exec -it px4-drone-1 /bin/bash
```

### MAVLink-Traffic analysieren

```bash
# Auf dem Host
sudo tcpdump -i any udp port 14540

# Oder mit Wireshark
# Filter: udp.port == 14540
```

## Referenzen

- [PX4 Autopilot](https://px4.io/)
- [MAVSDK](https://mavsdk.mavlink.io/)
- [jonasvautherin/px4-gazebo-headless](https://github.com/JonasVautherin/px4-gazebo-headless)
- [MAVLink Protocol](https://mavlink.io/)

---

*Erstellt: November 2025*
*Setup getestet mit: PX4 v1.14.3, MAVSDK v1.4.11, Docker Desktop 4.x*
