#!/bin/bash

sudo bash -c 'cat <<EOF > /opt/rgbpi/ui/data/update_timings.sh
#!/bin/bash
TIMINGS="320 1 20 32 45 240 1 28 3 42 0 0 0 50.000000 0 6510400 1
512 1 32 50 72 224 1 9 3 24 0 0 0 60.098809 0 10391084 1"
echo "\$TIMINGS" > /opt/rgbpi/ui/data/timings.dat
echo "\$TIMINGS" > /opt/rgbpi/ui/data/backup/timings.15
sync
EOF'
sudo chmod +x /opt/rgbpi/ui/data/update_timings.sh

sudo bash -c 'cat <<EOF > /etc/systemd/system/update_timings.service
[Unit]
Description=Update Timings on Shutdown
DefaultDependencies=no
Before=shutdown.target

[Service]
Type=oneshot
ExecStart=/opt/rgbpi/ui/data/update_timings.sh
RemainAfterExit=true

[Install]
WantedBy=halt.target reboot.target shutdown.target
EOF'

sudo systemctl enable update_timings.service
sudo systemctl start update_timings.service

sudo reboot
