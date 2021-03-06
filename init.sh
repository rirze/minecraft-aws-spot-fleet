#!/bin/bash

# set vars
az=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)
AWS_REGION=${az::-1} # AWS_REGION is just az without last character
this_instance_id=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)

# copy region defaults to ec2-user
/usr/bin/aws configure set default.region $AWS_REGION
mkdir /home/ec2-user/.aws
\cp /root/.aws/config /home/ec2-user/.aws/config # use raw `cp` not `cp -i` to overwrite w/o confirmation
chown -R ec2-user:ec2-user /home/ec2-user/.aws

# do attach volume first, so it runs while we install java
# to find ebs volume that holds minecraft, make sure its Name tag = '/minecraft' or adjust following filter appropriately
ebs_volume_id=$(/usr/bin/aws ec2 describe-volumes --filters "Name=tag:Name,Values=/minecraft" --query Volumes[0].VolumeId --output text) # output as text so var='id' rather than var='"id"'
/usr/bin/aws ec2 attach-volume --volume-id $ebs_volume_id --instance-id $this_instance_id --device /dev/sdm


# install java 8 (before we attach elastic IP)
yum install java-1.8.0-openjdk -y


# setup Elastic IP
# we should already have a EIP with name=minecraft-server-ip, otherwise change filter below
alloc_id=$(/usr/bin/aws ec2 describe-addresses --filter "Name=tag:Name,Values=minecraft-server-ip" --query Addresses[0].AllocationId --output text) # output as text so var='ip' rather than var='"ip"'
/usr/bin/aws ec2 associate-address --allocation-id $alloc_id --instance-id $this_instance_id


# come back to setting up ebs mount with our minecraft files
mkdir /minecraft
chown ec2-user:ec2-user /minecraft
until [ -e /dev/sdm ] ; do sleep 1 ; done  # wait for device to be attached
mount /dev/sdm /minecraft


# add mount to fstab if in case of a restart-- so it'll reattach automatically
echo '/dev/sdm /minecraft ext4 defaults,nofail 0 2' >> /etc/fstab


# create systemctl file for minecraft
# uses screen, once launched used `screen -R` to visit minecraft terminal (or use `screen -ls` and `screen -r $num-id`)
# type Control-a Control-d to 'detach' from mineraft terminal to go back to original terminal
cat > /lib/systemd/system/minecraft.service <<-EOF
[Unit]
Description=minecraft-server

[Service]
WorkingDirectory=/minecraft

User=ec2-user
Group=ec2-user

Type=forking
Restart=always
ExecStart=/usr/bin/screen -dmS minecraft /minecraft/LaunchServer.sh

ExecStop=/usr/bin/screen -p 0 -S minecraft -X eval 'stuff "say SERVER SHUTTING DOWN IN 60 SECONDS."\015'
ExecStop=/bin/sleep 60
ExecStop=/usr/bin/screen -p 0 -S minecraft -X eval 'stuff "stop"\015'

[Install]
WantedBy=multi-user.target
EOF

# enable and start minecraft
systemctl enable --now minecraft.service


# install termination checking script/service/timer
cat > /lib/systemd/system/checktermination.service <<-EOF
[Unit]
Description=Check if AWS gives this spot instance the terminatation notice
[Service]
ExecStart=/minecraft/check_for_termination.sh
EOF

cat > /lib/systemd/system/checktermination.timer <<-EOF
[Unit]
Description=Check for termination notice every 5 seconds
[Timer]
OnBootSec=5min
OnUnitActiveSec=5s
AccuracySec=1s
[Install]
WantedBy=timers.target
EOF

# enable and start checktermination timer
systemctl enable --now checktermination.timer
