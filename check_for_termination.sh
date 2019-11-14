#!/bin/bash

# simple script that checks if termination time is issued for this instance
# checks metadata url at http://169.254.169.254/latest/meta-data/spot/termination-time
# if that url/endpoint exists, we need to shutdown gracefully (under 2 min)
# otherwise, the curl request will return a 404 and we are good.

status_code=$(curl -s -o /dev/null -I -w "%{http_code}" http://169.254.169.254/latest/meta-data/spot/termination-time)
if [ $status_code != '404' ]
then
    logger "TERMINATE SIGNAL DETECTED"
    poweroff
fi
