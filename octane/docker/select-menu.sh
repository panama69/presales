#!/bin/bash
#export TERM=vt100

#
# you will need to install dialog to use this script.
# on Ubuntu, use 'sudo apt-get install dialog'

network="octane_nw"

#
#oracle values
#
ora_port=9080
ora_container="octane_oracle"
ora_image="sath89/oracle-xe-11g"

#
#elasticsearch values
#
es_container="octane_es"
es_image="elasticsearch:2.2"

#
#octane values
#
octane_port=8085
octane_domain="flynn.net"
octane_admin_password="HPALMdem0s"
octane_container="octane"
octane_image="hpsoftware/almoctane:12.53.12"

function have_network_connection ()
{
     if [[ `ping www.flynnshome.com -c 1|grep -w "0% packet loss"|wc -l` -lt 1 ]]
     then
          dialog --title "WARNING" --msgbox "Unable to successfully ping www.flynnshome.com.  Check your network connection" 10 70
          exit -1
     else
          return 1
     fi
}
# args:
#    1 - container_name
#    2 - search_string
function wait_on ()
{
     #echo wait_on "$1" "$2"
     # wait for process to be up by checking the logs
     counter=1
     found=0
     while [[ `$1 | grep "$2" | wc -l` -lt 1 ]]
     do
        sleep 10
        echo Checking.."$counter"
        if [[ $counter -le 10 ]]
        then
           (( counter++ ))
        else
           counter=-1
           break;
        fi
     done

     if [[ $counter -lt 1 ]]
     then
          return -1
     else
          return 0
     fi
}


function create_network ()
{
     docker network create $1 > /dev/null
     # quick check to see if the network was created or exists
     if [[ `docker network ls | grep $1 | wc -l` -ne 1 ]]
     then
          echo WARNING -- network doesn\'t exist
     else
          echo Network $1 started
     fi
}

# args:
#    1 - port
#    2 - network_name
#    3 - container_name
#    4 - docker_image_to_use
function start_oracle ()
{

     docker run -d -p $1:8080 -v /opt/oracle:/u01/app/oracle --shm-size=2g --net $2 --restart=always --name $3 $4

     searchmsg="Database ready to use"
     # Wait for the db to be up and ready
     echo "Waiting on database to be ready"
     echo "   -> sleeping for 20 sec before checking"
     sleep 20
     cmd="docker logs $3"
     if [[ `wait_on "$cmd" "$searchmsg"` ]]
     then
          echo Database is ready
     else
          echo WARNING -- the database doesn\'t look like it came up
     fi
}


# args:
#    1 - network_name
#    2 - container_name
#    3 - docker_image_to_use
function start_elasticsearch()
{
     docker run -d -e "ES_HEAP_SIZE=4G" -v /opt/elasticsearch/data:/usr/share/elasticsearch/data  --net $1 --name $2 --restart=always $3
}

# args:
#    1 - port
#    2 - domain
#    3 - admin_pwd
#    4 - network
#    5 - container_name
#    6 - docker_image_to_use
function start_octane ()
{
     #echo $1 $2 $3 $4 $5 $6
     docker run -d -p $1:8080 -e "SERVER_DOMAIN=$2" -e "ADMIN_PASSWORD=$3"  -e "DISABLE_VALIDATOR_MEMORY=true" -v /opt/octane/conf:/opt/octane/conf -v /opt/octane/log:/opt/octane/log -v /opt/octane/repo:/opt/octane/repo --net $4 --name $5 --restart=always $6

     cmd="cat /opt/octane/log/wrapper.log"
     searchstr="Server is ready! (Boot time"
     echo "Waiting on Octane to be ready"
     echo "   -> sleeping for 1 min before checking"
     sleep 65
     if [[ `wait_on "$cmd" "$searchmsg"` ]]
     then
          tail -2 /opt/octane/log/wrapper.log
     else
          echo WARNING -- Octane doesn\'t look like it came up
          echo
          tail -10 /opt/octane/log/wrapper.log
          echo
          echo Things could be just going slow or there could be an issue.
          echo Look in the /opt/octane/log/wrapper.log file for
          echo     'Server is ready! (Boot time XX seconds)'
     fi
}

# Check to see if the container exists in docker
function containers_exist ()
{
    let "count= \
     `docker ps -a --format="{{.Names}}" |grep -w "$octane_container" |wc -l`+\
     `docker ps -a --format="{{.Names}}" |grep -w "$es_container" |wc -l`+\
     `docker ps -a --format="{{.Names}}" |grep -w "$ora_container" |wc -l`"
    return $count
}

function download_files ()
{
       processing="$1"
       file="$2"
       echo "Processing $processing data"
       if [[ -e "/opt/$file" ]]
       then
            echo "$file" exists already locally
       else
            cd /opt && { \
               curl -O http://flynnshome.com/downloads/"$file" ; \
               echo "Uncompressing $processing data" ; \
               tar -zxf /opt/"$file" ; \
               cd -; }
       fi
}

function deploy_octane ()
{
     create_network $network
     start_oracle $ora_port $network $ora_container $ora_image
     start_elasticsearch $network $es_container $es_image
     start_octane $octane_port $octane_domain $octane_admin_password $network $octane_container $octane_image
}

containers_exist
if [[ $? -ne 0 ]]
then
     dialog --title "WARNING" --msgbox "One of these containers exist: $octane_container, $es_container, $ora_container You must take care of them before performing this operation" 10 70
     echo "One of these containers exist: $octane_container $es_container $ora_container"
     echo You must take care of them before you perform this operation
     exit -1
fi

# using the dialog utility https://linux.die.net/man/1/dialog
# other resource www.linuxjournal.com/article/2807
# other resource www.linuxcommand.org/lc3_adv_dialog.php 
cmd=(dialog --menu "Select options:" 22 76 16 )
options=(1 "Octane w/data" 2 "MT Octane" 3 "New Octane" 4 "Quit/Exit")
choice=$("${cmd[@]}" "${options[@]}" 2>&1 >/dev/tty)
clear
case $choice in
     1)
       echo "Creating Octane deployment with data"
       octane_data=octane-data-0.1.tar.gz
       oracle_data=oracle-data-0.1.tar.gz
       have_network_connection
       if [[ $? ]]
       then
            rm -rf /opt/octane /opt/oracle /opt/elasticsearch
            download_files "Octane" "$octane_data"
            download_files "Oracle" "$oracle_data"
            deploy_octane
       fi
       ;;
     2)
       echo "Creating empty Octane deployment"
       octane_data=octane-mt-0.1.tar.gz
       oracle_data=oracle-mt-0.1.tar.gz
       have_network_connection
       if [[ $? ]]
       then
            rm -rf /opt/octane /opt/oracle /opt/elasticsearch
            download_files "Octane" "$octane_data"
            download_files "Oracle" "$oracle_data"
            deploy_octane
       fi
       ;;
     3)
       echo "Creating new Octane deployment"
       have_network_connection
       if [[ $? ]]
       then
            rm -rf /opt/octane /opt/oracle /opt/elasticsearch
            deploy_octane
       fi
       ;;
     4)
       echo "Good bye"
       ;;
esac

