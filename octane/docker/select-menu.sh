#!/bin/bash
#export TERM=vt100

demofile=$1
if [[ $# -ne 1 ]]
then
   echo Missing the json demo configuration file.
   echo This is the file which determines the arguments needed for the
   echo Docker conatiners
   exit -1
fi

#
# you will need to install dialog to use this script.
# on Ubuntu, use 'sudo apt-get install dialog'

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
     #echo wait_on ">$1<" ">$2<"
     # wait for process to be up by checking the logs
     counter=1
     found=0
     progressStr="Checking.."
     echo -ne $progressStr'\r'
     cmd="$1 | grep "$2" | wc -l"
     echo $cmd
     while [[ $(eval $cmd) -lt 1 ]]
     do
        sleep 10
        progressStr=$progressStr"#"
        echo -ne $progressStr'\r'
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


function create_networks ()
{
   netJson=$1
   networksCnt=`echo $netJson |jq ".|length"`
   for ((i=0; i<$networksCnt; i++))
   do
      networkName=`echo $netJson |jq ".[$i]"`
      networkName=${networkName//\"}
      echo $networkName
      if [[ -z "$networkName" ]] || [[ "$networkName" = "null" ]]
      then
         echo WARNING: Can not create a network of null value
      else
         # if the network doesn't exist already then create it else use the existing one
         cmd="docker network ls | grep $networkName | wc -l"
         if [[ $(eval $cmd) -eq 0 ]]
         then
            docker network create $1 > /dev/null
            # quick check to see if the network was created or exists
            if [[ $(eval $cmd) -ne 1 ]]
            then
               echo WARNING -- network doesn\'t exist
            else
               echo Network $networkName started
            fi
         else
            echo WARNING - Network: \""$networkName"\" was already created so no need to create it again
         fi
      fi   
   done
}

function build_docker_string ()
{
   foundContainerName=false
   foundImage=false
   configs=$1
   items=`echo $configs|jq ".Configs|keys|.[]"`

   str=''
   for item in $items
   do
      #Remove the quotes around the string
      item=${item%\"}
      item=${item#\"}
      value=`echo $configs|jq ".Configs.$item"`
      case "$item" in
         ContainerName)
            foundContainerName=true
            str="--name $value $str"
            ;;
         Image)
            foundImage=true
            str="$str $value"
            ;;
         Ports)
            count=`echo $value|jq ".|length"`
            if [[ "$count" -gt 0 ]]
            then
               s=''
               for ((x=0; x<$count; x++))
               do
                  tmp=`echo $value|jq ".[$x]"`
                  s="$s-p $tmp "
               done
               str="$s$str"
            fi
            ;;
         Networks)
            count=`echo $value|jq ".|length"`
            if [[ "$count" -gt 0 ]]
            then
               s=''
               for ((x=0; x<$count; x++))
               do
                  tmp=`echo $value|jq ".[$x]"`
                  s="$s--net $tmp "
               done
               str="$s$str"
            fi
            ;;
         DataContainers)
            count=`echo $value|jq ".|length"`
            if [[ "$count" -gt 0 ]]
            then
               s=''
               for ((x=0; x<$count; x++))
               do
                  tmp=`echo $value|jq ".[$x]"`
                  s="$s--volumes-from=$tmp "
               done
               str="$s$str"
            fi
            ;;
         EnvironmentVariables)
            count=`echo $value|jq ".|length"`
            if [[ "$count" -gt 0 ]]
            then
               s=''
               for ((x=0; x<$count; x++))
               do
                  tmp=`echo $value|jq ".[$x]"`
                  s="$s-e $tmp "
               done
               str="$s$str"
            fi
            ;;
         Volumes)
            count=`echo $value|jq ".|length"`
            if [[ "$count" -gt 0 ]]
            then
               s=''
               for ((x=0; x<$count; x++))
               do
                  tmp=`echo $value|jq ".[$x]"`
                  s="$s-v $tmp "
               done
               str="$s$str"
            fi
            ;;
      esac
   done
   if [ $foundContainerName = false ] || [ $foundImage = false ]
   then
      str="ERROR -- no container name or docker image specified"
      exit -1
   fi
   
   echo "$str"
}

# args:
#    1 - Json string object containing configurations
function start_Jenkins ()
{
   docker_str=$(build_docker_string "$1")
   cmd="docker run -d --restart=always $docker_str"
   echo "$cmd"
   eval $cmd
}

# args:
#    1 - Json string object containing configurations
function start_OracleXE ()
{
   docker_str=$(build_docker_string "$1")
   cmd="docker run -d --shm-size=2g --restart=always $docker_str"
   echo "     $cmd"
   eval $cmd

   searchmsg="\"Database ready to use\""
   # Wait for the db to be up and ready
   echo "Waiting on database to be ready"
   echo "   -> sleeping for 20 sec before checking"
   sleep 20
   tmp=`echo $1|jq '.Configs.ContainerName'`
   tmp=${tmp//\"}
  
   cmd="docker logs $tmp"
   wait_on "$cmd" "$searchmsg"
   if [[ $? -eq 0 ]]
   then
      echo Database is ready
   else
      echo WARNING -- the database doesn\'t look like it came up
   fi
}


# args:
#    1 - Json string object containing configurations
function start_ElasticSearch()
{
   docker_str=$(build_docker_string "$1")
   cmd="docker run -d --shm-size=2g --restart=always $docker_str"
   echo $cmd
   eval $cmd

     #docker run -d -e "ES_HEAP_SIZE=4G" -v /opt/elasticsearch/data:/usr/share/elasticsearch/data  --net $1 --restart=always --name $2 $3
}

# args:
#    1 - Json string object containing configurations
function start_Octane ()
{
   docker_str=$(build_docker_string "$1")

   # little hack to have the container start with a FQDN
   tmp=`echo $1|jq ".Configs.ContainerName"`
   tmp=${tmp%\"}
   tmp=${tmp#\"}
   hostname_str="--hostname=\"$tmp"
   tmp=`echo $1|jq ".Configs.EnvironmentVariables[0]"`
   # takes tmp and replaces globally '//' the occurance of "SERVER_DOMAIN= with nothing
   tmp=${tmp//\"SERVER_DOMAIN=/}
   hostname_str="$hostname_str.$tmp"
   cmd="docker run -d --restart=always $hostname_str $docker_str"
   echo $cmd
   eval $cmd
   #Might need to turn off the proxy as set by Israel
   # -e "http_proxy=" -e "https_proxy="
   #docker run -d -p $1:8080 -e "SERVER_DOMAIN=$2" -e "ADMIN_PASSWORD=$3"  -e "DISABLE_VALIDATOR_MEMORY=true" -v /opt/octane/conf:/opt/octane/conf -v /opt/octane/log:/opt/octane/log -v /opt/octane/repo:/opt/octane/repo --net $4 --name $5 --hostname="$5.$2" --restart=always $6

   cmd="tail -50 /opt/octane/log/wrapper.log"
   searchstr="\"Server is ready! (Boot time\""
   echo "Waiting on Octane to be ready"
   echo "   -> sleeping for 30 sec before checking"
   sleep 30
   wait_on "$cmd" "$searchstr"
   if [[ $? -eq 0 ]]
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

# args
#   $1 - demo menu choice
function container_list ()
{
   containers=`echo $demosJson |jq ".[$1].Dependencies.Systems[].Assets[].Configs |select (.ContainerName) |.ContainerName"`
   echo "$containers"
}


# args
#   $1 - demo menu choice
function stop_remove_containers ()
{
   containerList=$1
   echo Stopping containers $containerList
   cmd="docker stop $containers"
   eval $cmd
   echo Removing containers $containerList
   cmd="docker rm $containers"
   eval $cmd
}

function remove_data_folders ()
{
     sudo rm -rf /opt/octane /opt/oradata /opt/elasticsearch
}

# args
#   $1 - demo menu choice
function show_container_warning ()
{
   containers=$(container_list $1)
   dialog --title "WARNING" --defaultno --yesno "One of these containers exist:\n     $containers\nYou must take care of them before performing this operation.\n\n         DO YOU WANT TO STOP AND REMOVE THEM" 20 70

   if [[ $? -eq 0 ]]
   then
      echo removing
      stop_remove_containers "$containers"
      remove_data_folders
   else
      exit -1
   fi
}

# Check to see if the container exists in docker
# args
#   $1 - demo menu choice
function containers_exist ()
{
   containers=$(container_list "$1")

   IFS=$'\n'

   let count=0
   for i in $containers
   do
     i=${i//\"}
     cmd="docker ps -a --format='{{.Names}}' |grep -w "$i" |wc -l"
     let count=($count)+$(eval $cmd)
     echo $i
   done
   return $count
}

function download_files ()
{
       tmpJson="$1"
       restoreLocation=`echo $tmpJson |jq ".Path"`
       restoreLocation=${restoreLocation//\"}
       # the following found @ www.thegeekstuff.com/2010/07/bash-string-manipulation
       rootPath=${restoreLocation%/*}
       targetFolder=${restoreLocation##*/}
       file=`echo $tmpJson |jq ".File"`
       file=${file//\"}

       echo "Processing: $file"
       if [[ -e "/opt/$file" ]]
       then
            echo "$file" exists already locally so no need to download
       else
            cd "$rootPath" && { \
               curl -O http://flynnshome.com/downloads/"$file" ; \
               cd -; }
       fi

       echo "Uncompressing to $rootPath" 
       echo "tar -zxf $file" "$targetFolder" 
       cd "$rootPath" && { \
          tar -zxf "$file" "$targetFolder" ; \
          cd -; }
}

function deploy_octane ()
{
     create_network $network
     start_oracle $ora_port $network $ora_container $ora_image
     start_elasticsearch $network $es_container $es_image
     start_octane $octane_port $octane_domain $octane_admin_password $network $octane_container $octane_image
}

# will return an array (list) based on the json query passed
function get_list ()
{
   IFS=$'\n'
   index=0 #index of the array element
   menuItem=0 #menu item number
   for i in `jq "$1" $demofile`
   do  
      options[index]=$menuItem
      let index++
      options[index]="${i//\"}" #remove all "
      #options[index]="${i%\"}" #remove trailing "
      #options[index]="${options[index]#\"}" #remove leading "
      let index++
      let menuItem++
   done
   let index++
   options[index]=$menuItem
   let index++
   options[index]="Quit/Exit"
}

# using the dialog utility https://linux.die.net/man/1/dialog
# other resource www.linuxjournal.com/article/2807
# other resource www.linuxcommand.org/lc3_adv_dialog.php 
# other http://jrgraphix.net/man/D/dialog
dialog --title "sudo" --yesno "This utility requires 'sudo'\n\nIf you didn't run this as:\n     sudo ./select-menu.sh\n\nPlease exit and restart.\n\nDo you wish to continue?" 20 40
if [[ $? -ne 0 ]]
then
     exit -1
fi

#
# show demos one can select from
#
cmd=(dialog --menu "Select options:" 22 76 16 )
demoCnt=`jq ".Demos|length" $demofile`
demosJson=`jq ".Demos" $demofile`
get_list ".Demos[].Name"

choice=$("${cmd[@]}" "${options[@]}" 2>&1 >/dev/tty)
#if select menu choice > than available demos then exit
if [[ $choice -eq $demoCnt ]]
then
   clear
   echo "Goodbye"
   exit
fi

containers_exist "$choice"
if [[ $? -ne 0 ]]
then
   show_container_warning "$choice"
fi

clear
echo $choice
networkJson=`jq ".Demos[$choice].Dependencies.Network" $demofile`
create_networks "$networkJson"

systemsJson=`jq ".Demos[$choice].Dependencies.Systems" $demofile`
systemsCnt=`echo $systemsJson |jq ".|length"`
echo System Count: "$systemsCnt"
for ((systemsIndex=0; systemsIndex<$systemsCnt; systemsIndex++))
do
   echo "###########################################"
   echo "###########################################"
   echo "######" Deploying System: `echo $systemsJson |jq ".[$systemsIndex].Name"`
   assetsJson=`echo $systemsJson |jq ".[$systemsIndex].Assets"`
   assetsCnt=`echo $assetsJson |jq ".|length"`
   for ((assetsIndex=0; assetsIndex<assetsCnt; assetsIndex++))
   do
      assetName=`echo $assetsJson |jq ".[$assetsIndex].Name"`
      assetName=${assetName//\"}
      dataJson=`echo $assetsJson |jq ".[$assetsIndex].Data"`
      if [[ `echo $dataJson |jq ".|length"` -eq 2 ]]
      then
         download_files "$dataJson"
      fi
      echo
      echo "###########################################"
      echo "Deploying Asset: $assetName"
      assetJson=`echo $assetsJson |jq ".[$assetsIndex]"`
      start_"$assetName" "$assetJson"
      echo "###########################################"
      echo
   done
   echo
   echo
done

exit
case $choice in
     1)
       echo "Creating Octane deployment with data"
       octane_data=octane-data-0.1.tar.gz
       oracle_data=oradata-data-0.1.tar.gz
       have_network_connection
       if [[ $? ]]
       then
            remove_data_folders
            download_files "octane" "$octane_data"
            download_files "oradata" "$oracle_data"
            deploy_octane
       fi
       ;;
     2)
       echo "Creating empty Octane deployment"
       octane_data=octane-mt-0.1.tar.gz
       oracle_data=oradata-mt-0.1.tar.gz
       have_network_connection
       if [[ $? ]]
       then
            remove_data_folders
            download_files "octane" "$octane_data"
            download_files "oradata" "$oracle_data"
            deploy_octane
       fi
       ;;
     3)
       echo "Creating new Octane deployment"
       have_network_connection
       if [[ $? ]]
       then
            remove_data_folders
            deploy_octane
       fi
       ;;
     4)
       echo "Good bye"
       ;;
esac

