# Basis: Das funktionierende jonasvautherin Image
FROM jonasvautherin/px4-gazebo-headless:1.14.3

# Unser angepasstes Entrypoint-Script
COPY entrypoint.sh /root/entrypoint.sh
RUN chmod +x /root/entrypoint.sh

# Umgebungsvariablen mit Defaults
ENV MAV_SYS_ID=1
ENV PX4_HOME_LAT=51.2330
ENV PX4_HOME_LON=6.7833
ENV PX4_HOME_ALT=38.0

ENTRYPOINT ["/root/entrypoint.sh"]
