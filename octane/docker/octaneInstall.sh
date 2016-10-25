#!/bin/bash

if [[ $# -lt 2 ]] ; then
    echo 'usage:  ./octaneInstall.sh <domain name used for this installation> <default password>'
    exit 1
fi

domain=$1
password=$2

echo "domain $domain"

# create a docker network to let the container communicate
docker network create octane_nw

# create oracle database container
docker run -d  -v /usr/lib/oracle/xe/oradata/XE:/usr/lib/oracle/xe/oradata/XE --shm-size=2g --net octane_nw --restart=always --name octane_oracle alexeiled/docker-oracle-xe-11g

# create Elastic Search container
docker run -d  -e "ES_HEAP_SIZE=4G" -v /var/elasticsearch/data:/usr/share/elasticsearch/data  --net octane_nw --name octane_es --restart=always elasticsearch:2.2

# install NGA
docker run -d -p 8085:8080 -e "SERVER_DOMAIN=$domain" -e "ADMIN_PASSWORD=$password"  -e "DISABLE_VALIDATOR_MEMORY=true" -v /opt/octane/conf:/opt/octane/conf -v /opt/octane/log:/opt/octane/log -v /opt/octane/repo:/opt/octane/repo --net octane_nw --name octane --restart=always hpsoftware/almoctane:12.53.12

# wait for everything to settle down
echo sleeping for 1 minute to let octane start
sleep 65s

# print docker output
#docker logs octane

# print wrapper log
counter=1
while [[ `cat /opt/octane/log/wrapper.log|grep '| Server is ready! (Boot time'|wc -l` -lt 1 ]]
do
   sleep 10
   clear
   echo still starting.."$counter"
   if [[ $counter -le 10 ]]
   then
      (( counter++ ))
   else
      counter=-1
      break;
   fi

done

if [[ $counter -lt 0 ]]
then
   tail -20 /opt/octane/log/wrapper.log
   echo
   echo Check if Octane came up as it looks like there might be an issue
else
   tail -n 2 /opt/octane/log/wrapper.log
fi
