FROM teriyakigod/steamcmd:arm64

USER root
RUN install -d -o steam -g steam /home/steam/Steam/ProjectZomboid /home/steam/Zomboid
COPY adjust-project-zomboid-json.py /usr/local/bin/adjust-project-zomboid-json.py
RUN chmod 755 /usr/local/bin/adjust-project-zomboid-json.py

USER steam
WORKDIR /home/steam/Steam
