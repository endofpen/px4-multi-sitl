# PX4 Multi-Drone SITL Simulation - Projekt-Dokumentation

## Projektübersicht

### Ziel
Entwicklung eines Docker-basierten Multi-Drone Simulationssystems für PX4 SITL (Software In The Loop), das mehrere simulierte Drohnen gleichzeitig in separaten Containern ausführen kann. Diese Drohnen werden über MAVSDK mit einer Kotlin-Anwendung gesteuert.

### Motivation
- Entwicklung und Test einer Multi-Drone Steuerungsanwendung in Kotlin
- Simulation mehrerer Drohnen ohne physische Hardware
- Vorbereitung für späteren Einsatz mit echten Drohnen
- Reproduzierbare Testumgebung für Drohnen-Schwarm-Szenarien

### Anwendungsfall
Eine Kotlin-Anwendung steuert mehrere Drohnen über MAVSDK-Java. Jede Drohne läuft in einem eigenen Docker-Container mit PX4 SITL und Gazebo (headless). Die Kommunikation erfolgt über MAVLink UDP.

---

## Architektur
```
┌──────────────────────────────────────────────────────────────────────────────┐
│                              HOST SYSTEM                                     │
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │                         Docker Environment                             │  │
│  │                                                                        │  │
│  │  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐      │  │
│  │  │  px4-drone-1     │  │  px4-drone-2     │  │  px4-drone-3     │      │  │
│  │  │  MAV_SYS_ID: 1   │  │  MAV_SYS_ID: 2   │  │  MAV_SYS_ID: 3   │      │  │
│  │  │  API: 14540      │  │  API: 14541      │  │  API: 14542      │      │  │
│  │  │  PX4 + Gazebo    │  │  PX4 + Gazebo    │  │  PX4 + Gazebo    │      │  │
│  │  └────────┬─────────┘  └────────┬─────────┘  └────────┬─────────┘      │  │
│  └───────────┼─────────────────────┼─────────────────────┼────────────────┘  │
│              │ UDP MAVLink         │ UDP MAVLink         │ UDP MAVLink       │
│              ▼                     ▼                     ▼                   │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐            │
│  │  MAVSDK-Server   │  │  MAVSDK-Server   │  │  MAVSDK-Server   │            │
│  │  UDP: 14540      │  │  UDP: 14541      │  │  UDP: 14542      │            │
│  │  gRPC: 50051     │  │  gRPC: 50052     │  │  gRPC: 50053     │            │
│  └────────┬─────────┘  └────────┬─────────┘  └────────┬─────────┘            │
│           └─────────────────────┼─────────────────────┘                      │
│                                 ▼                                            │
│                    ┌─────────────────────────┐                               │
│                    │    Kotlin Application   │                               │
│                    │    MAVSDK-Java Client   │                               │
│                    └─────────────────────────┘                               │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Technische Entscheidungen

### Warum eigenes Docker-Image statt Jonas-Image?

| Aspekt | Jonas-Image | Eigenes Image (andrekuros-basiert) |
|--------|-------------|-----------------------------------|
| Multi-Drone Support | Eingeschränkt | Vollständig |
| MAV_SYS_ID | Nicht konfigurierbar | Per Umgebungsvariable |
| API/GCS Ports | Fest (14540/14550) | Frei konfigurierbar |
| Sim-Speed | Nicht änderbar | Einstellbar |
| Custom PX4 Params | Nicht möglich | Zur Laufzeit setzbar |
| MAV_PROTO_VER | Nicht gesetzt | Automatisch auf 2 |

### Kritische Konfigurationen

1. **MAV_PROTO_VER 2** - Erzwingt MAVLink 2 Protokoll, verhindert Paketverluste
2. **MAV_SYS_ID** - Muss für jede Drohne eindeutig sein (1-255)
3. **Separate Ports** - Jede Drohne braucht eigenen API_PORT
4. **host.docker.internal** - Ermöglicht Kommunikation Container → Host

---

## Gelöste Probleme

### 1. CRLF vs. LF Zeilenenden (Windows)
**Problem:** Shell-Scripts mit Windows-Zeilenenden (CRLF) funktionieren nicht in Linux-Containern.
**Lösung:** `.gitattributes` Datei mit `*.sh text eol=lf`

### 2. IPv6 statt IPv4
**Problem:** `getent hosts` gibt IPv6 zurück, PX4 versteht nur IPv4.
**Lösung:** `getent ahostsv4` für explizite IPv4-Auflösung

### 3. empy Version Inkompatibilität
**Problem:** `empy` 4.x entfernte `RAW_OPT` Attribut, PX4 braucht es.
**Lösung:** `pip3 install empy==3.3.4`

### 4. MAVLink Paketverluste
**Problem:** `vehicle_command_ack lost` Fehler, instabile Kommunikation.
**Lösung:** `MAV_PROTO_VER 2` setzen + korrekte MAVLink-Konfiguration wie bei andrekuros

### 5. Commands werden ignoriert
**Problem:** Drohne reagiert langsam oder gar nicht auf Befehle.
**Lösung:** Vollständige MAVLink-Konfiguration mit `-t <IP>` und `-o <PORT>` für beide Links (GCS + API)

---

## Dateien im Projekt
```
px4-multi-sitl/
├── Dockerfile           # Ubuntu 18.04 + PX4 Build
├── docker-compose.yml   # Multi-Container Orchestrierung
├── entrypoint.sh        # Startskript mit Umgebungsvariablen
├── edit_rcS.bash        # MAVLink-Konfiguration
├── .gitattributes       # LF-Zeilenenden für Windows
├── README.md            # Benutzer-Dokumentation
└── sitl_rtsp_proxy/     # Video-Streaming (optional)
    ├── CMakeLists.txt
    └── main.cpp
```

---

## Konfigurierbare Umgebungsvariablen

| Variable | Beschreibung | Default | Beispiel |
|----------|--------------|---------|----------|
| `MAV_SYS_ID` | MAVLink System ID (1-255) | `1` | `2` |
| `API_PORT` | UDP Port für MAVSDK | `14540` | `14541` |
| `GCS_PORT` | UDP Port für QGroundControl | `14550` | `14551` |
| `SIM_SPEED` | Simulationsgeschwindigkeit | `1` | `2` |
| `VEHICLE` | Fahrzeugtyp | `iris` | `typhoon_h480` |
| `WORLD` | Gazebo-Welt | `empty` | `baylands` |
| `PX4_HOME_LAT` | Startposition Breitengrad | `51.2330` | - |
| `PX4_HOME_LON` | Startposition Längengrad | `6.7833` | - |
| `PX4_HOME_ALT` | Startposition Höhe (m) | `38.0` | - |
| `PX4_PARAMS` | Zusätzliche PX4-Parameter | `""` | `MPC_XY_CRUISE 20,MIS_DIST_1WP 3000` |

---

## Port-Schema

| Drohne | MAV_SYS_ID | API_PORT | GCS_PORT | MAVSDK gRPC |
|--------|------------|----------|----------|-------------|
| 1 | 1 | 14540 | 14550 | 50051 |
| 2 | 2 | 14541 | 14551 | 50052 |
| 3 | 3 | 14542 | 14552 | 50053 |
| N | N | 14539+N | 14549+N | 50050+N |

---

## Verwendung

### Image bauen (einmalig, ~30-60 Min)
```bash
docker-compose build
```

### Drohnen starten
```bash
# Einzelne Drohne
docker-compose up drone1

# Mehrere Drohnen
docker-compose up drone1 drone2 drone3
```

### MAVSDK-Server starten (auf Host)
```bash
./mavsdk_server -p 50051 udp://:14540  # Drohne 1
./mavsdk_server -p 50052 udp://:14541  # Drohne 2
./mavsdk_server -p 50053 udp://:14542  # Drohne 3
```

### Kotlin-Verbindung
```kotlin
val drone1 = System("localhost", 50051)
val drone2 = System("localhost", 50052)
val drone3 = System("localhost", 50053)
```

---

## Quellen und Referenzen

### Haupt-Repositories

1. **andrekuros/px4-sitl-headless-flex** (Hauptbasis für unser Setup)
    - GitHub: https://github.com/andrekuros/px4-sitl-headless-flex
    - DockerHub: https://hub.docker.com/r/andrekuros/px4-sitl-headless-flex
    - Features: Multi-Drone, konfigurierbare Ports, SIM_SPEED, PX4_PARAMS

2. **JonasVautherin/px4-gazebo-headless** (Original-Inspiration)
    - GitHub: https://github.com/JonasVautherin/px4-gazebo-headless
    - DockerHub: https://hub.docker.com/r/jonasvautherin/px4-gazebo-headless
    - Verwendet für: Grundstruktur, RTSP Proxy, edit_rcS.bash Konzept

3. **PX4/PX4-Autopilot** (Firmware)
    - GitHub: https://github.com/PX4/PX4-Autopilot
    - Version: v1.14.3
    - Dokumentation: https://docs.px4.io/

### Dokumentation

4. **PX4 Gazebo Classic Simulation**
    - https://docs.px4.io/main/en/sim_gazebo_classic/

5. **MAVSDK**
    - https://mavsdk.mavlink.io/
    - MAVSDK-Java für Kotlin-Integration

6. **MAVLink Protokoll**
    - https://mavlink.io/

### Problem-Lösungen

7. **IPv6 Problem in Docker**
    - GitHub Issue: https://github.com/JonasVautherin/px4-gazebo-headless/issues/34
    - Lösung: `getent ahostsv4` statt `getent hosts`

8. **empy Kompatibilität**
    - Problem: `AttributeError: module 'em' has no attribute 'RAW_OPT'`
    - Lösung: `empy==3.3.4` pinnen

9. **Multi-Vehicle Simulation**
    - PX4 Docs: https://docs.px4.io/main/en/simulation/multi-vehicle-simulation.html

---

## Entwicklungsumgebung

- **Host OS:** Windows mit Docker Desktop
- **IDE:** IntelliJ IDEA (für Kotlin)
- **Container OS:** Ubuntu 18.04
- **PX4 Version:** v1.14.3
- **Gazebo Version:** 9
- **MAVSDK Version:** Aktuell (für mavsdk_server)

---

## Bekannte Einschränkungen

1. **Build-Zeit:** Erster Build dauert 30-60 Minuten (PX4 Kompilierung)
2. **Ressourcen:** Jede Drohne benötigt ~2-4 GB RAM, 1-2 CPU Cores
3. **Windows:** Shell-Scripts müssen LF-Zeilenenden haben
4. **Simulation:** Hohe SIM_SPEED Werte können instabil sein

---

## Nächste Schritte / TODO

- [ ] Kotlin-Anwendung mit Multi-Drone Steuerung entwickeln
- [ ] Tests mit 3+ gleichzeitigen Drohnen
- [ ] Performance-Optimierung
- [ ] Übergang zu echten Drohnen vorbereiten
- [ ] CI/CD Pipeline für automatische Tests

---

## Kontakt / Kontext

- **Entwickler:** Flo (Freelancer, Deutschland)
- **Projekt:** Multi-Drone Control System mit Kotlin und MAVSDK
- **Weitere Arbeiten:** Space Weather Analysis, LLM Operations (2x H100)

---

*Erstellt: November 2025*
*Letzte Aktualisierung: Session mit Claude*