# =============================================================================
# Dockerfile für PX4 Multi-Drone SITL Simulation
# =============================================================================
# Basierend auf andrekuros/px4-sitl-headless-flex
# Baut PX4 von Grund auf für maximale Flexibilität
# =============================================================================

FROM ubuntu:18.04

# -----------------------------------------------------------------------------
# Umgebungsvariablen
# -----------------------------------------------------------------------------
ENV WORKSPACE_DIR /root
ENV FIRMWARE_DIR ${WORKSPACE_DIR}/Firmware
ENV SITL_RTSP_PROXY ${WORKSPACE_DIR}/sitl_rtsp_proxy

ENV DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true
ENV DISPLAY :99
ENV LANG C.UTF-8

# -----------------------------------------------------------------------------
# System-Abhängigkeiten installieren
# -----------------------------------------------------------------------------
RUN apt-get update && \
    apt-get install -y bc \
                       cmake \
                       curl \
                       gazebo9 \
                       git \
                       gstreamer1.0-plugins-bad \
                       gstreamer1.0-plugins-base \
                       gstreamer1.0-plugins-good \
                       gstreamer1.0-plugins-ugly \
                       iproute2 \
                       libeigen3-dev \
                       libgazebo9-dev \
                       libgstreamer-plugins-base1.0-dev \
                       libgstrtspserver-1.0-dev \
                       libopencv-dev \
                       libroscpp-dev \
                       protobuf-compiler \
                       python3-jsonschema \
                       python3-numpy \
                       python3-pip \
                       unzip \
                       net-tools \
                       xvfb && \
    apt-get -y autoremove && \
    apt-get clean autoclean && \
    rm -rf /var/lib/apt/lists/{apt,dpkg,cache,log} /tmp/* /var/tmp/*

# -----------------------------------------------------------------------------
# Python-Abhängigkeiten
# -----------------------------------------------------------------------------
RUN pip3 install empy==3.3.4 \
                 jinja2 \
                 packaging \
                 pyros-genmsg \
                 toml \
                 pyyaml \
                 kconfiglib \
                 future

# -----------------------------------------------------------------------------
# PX4 Autopilot klonen und bauen
# -----------------------------------------------------------------------------
# Verwendet v1.14.3 für Stabilität (kann auf master geändert werden)
RUN git clone https://github.com/PX4/PX4-Autopilot.git ${FIRMWARE_DIR}
RUN git -C ${FIRMWARE_DIR} checkout v1.14.3
RUN git -C ${FIRMWARE_DIR} submodule update --init --recursive

# -----------------------------------------------------------------------------
# Konfigurationsskripte kopieren
# -----------------------------------------------------------------------------
COPY edit_rcS.bash ${WORKSPACE_DIR}
COPY entrypoint.sh /root/entrypoint.sh
RUN chmod +x /root/entrypoint.sh
RUN chmod +x ${WORKSPACE_DIR}/edit_rcS.bash

# -----------------------------------------------------------------------------
# PX4 SITL vorbauen (beschleunigt Container-Start)
# -----------------------------------------------------------------------------
RUN ["/bin/bash", "-c", " \
    cd ${FIRMWARE_DIR} && \
    DONT_RUN=1 make px4_sitl gazebo && \
    DONT_RUN=1 make px4_sitl gazebo \
"]

# -----------------------------------------------------------------------------
# RTSP Proxy für Video-Streaming
# -----------------------------------------------------------------------------
COPY sitl_rtsp_proxy ${SITL_RTSP_PROXY}
RUN cmake -B${SITL_RTSP_PROXY}/build -H${SITL_RTSP_PROXY}
RUN cmake --build ${SITL_RTSP_PROXY}/build

# -----------------------------------------------------------------------------
# Standard-Umgebungsvariablen (können in docker-compose überschrieben werden)
# -----------------------------------------------------------------------------
ENV MAV_SYS_ID=1
ENV SIM_SPEED=1
ENV VEHICLE=iris
ENV WORLD=empty
ENV API_IP=127.0.0.1
ENV API_PORT=14540
ENV GCS_IP=127.0.0.1
ENV GCS_PORT=14550
ENV PX4_PARAMS=""

ENV PX4_HOME_LAT=51.2330
ENV PX4_HOME_LON=6.7833
ENV PX4_HOME_ALT=38.0

ENTRYPOINT ["/root/entrypoint.sh"]