#!/bin/bash
#export TERM=vt100
#
# Author: Dave Flynn <flynn@hpe.com>
#
# #####################
# Pre-requisits
# #####################
#    dialog - this script makes use of the 'dialog' utility.  You will need to
#             install dialog to use this script.  On Ubuntu, use 
#             'sudo apt-get install dialog' to install.  It is available for
#             other linux/unix platforms as well.
#
#    jq - json query utility to parse Json.  Installation can be found on
#         stedolan.github.io/jq/download
#
# ##################### 
# Resource references
# #####################
# dialog
#    - https://linux.die.net/man/1/dialog
#    - www.linuxjournal.com/article/2807
#    - www.linuxcommand.org/lc3_adv_dialog.php 
#    - http://jrgraphix.net/man/D/dialog
#
# command string parsing (ex: ${str// *} or ${str#\"} or ${str//\"}
#    - www.thegeekstuff.com/2010/07/bash-string-manipulation
#    - www.thegeekstuff.com/2010/06/bash-array-tutorial
#
# IFS (Internal Field Separator)
#   www.tldp.org/LDP/abs/html/internalvariables.html

#
# Global variables
#-----------------
# for menus
bt="HPE Demo Menu"

# general
localDemoDataRepo="/opt"
remoteDemoDataRepo="http://flynnshome.com/downloads"
#demofile=$1

debug ()
{
  `dialog --msgbox "$1" 0 0 2>&1>/dev/tty`
}

###############################################################################
#
# Checks to see if a demo configuration file is passed to the script.
# This file has the definitions of what docker images to use to start various
# systems to use for demos along with the ports and mounts that are required
#
# NOTE: The script exits immediately if a file is not provided
#
###############################################################################
have_demofile ()
{
   if [ $1 -ne 1 ]
   then
      dialog --backtitle "$bt" --title "Missing json file" \
      --msgbox "Missing the json demo configuration file.\n\nThis is the file that determines the arguments needed for the images and containers used for the demos.\n\nTo start the menu system use the following format:\n\n     sudo ./select-menu.sh democonfig.json" 19 76
      exit -1
   fi
}

############################################################################### 
# Check if you are running the script as root or sudo as there are some things
# that require root permissions to move/delete some files in the /opt direcory
#
# NOTE: The script exits immediately if a file is not provided
#
###############################################################################
is_sudo ()
{
   if [ $(id -u) -ne 0 ]
   then
      dialog --backtitle "$bt" --title "sudo Required" --msgbox "This utility requires 'sudo'.  Please exit and restart this using:\n     sudo ./select-menu.sh <democonfig.json>" 6 70
      exit -1
   fi
}

############################################################################### 
# Attempts to ping a site to ensure there is internet connectivity.  Intended 
# use is to warn users before they remove any Docker images in case they plan
# on re-pulling the images.  This is mostly used as a warning rather than to
# prevent individuals from removing images when not connected to the internet
#
############################################################################### 
have_network_connection ()
{
     if [ `ping $remoteDemoDataRepo -c 1|grep -w "0% packet loss"|wc -l` -lt 1 ]
     then
          dialog --backtitle "$bt" --title "WARNING" --msgbox "Unable to successfully ping $remoteDemoDataRepo.  Check your network connection" 10 70
          return 0
     else
          return 1
     fi
}

############################################################################### 
# Generic function to accept a command to execute and a string it should find
# to indicate things are up and running or completed before continuing.
# The 'command' here could be 'docker logs' 'tail' or other passed to it.
# As you see it will run the command and then grep for the string and do a
# word count (wc) to see if there was at least one match.
#
# args:
#    1 - command
#    2 - search_string
# return
#     0 - success
#    -1 - failure - string was not found after 100 seconds
############################################################################### 
wait_on ()
{
     #echo wait_on ">$1<" ">$2<"
     # wait for process to be up by checking the logs
     local counter=1
     local found=0
     local progressStr="Checking.."
     # hack to over write the same position with a growing progress bar
     echo -ne $progressStr'\r'
     local cmd="$1 | grep "$2" | wc -l"
     echo $cmd
     while [ $(eval $cmd) -lt 1 ]
     do
        sleep 10
        progressStr=$progressStr"#"
        echo -ne $progressStr'\r'
        if [ $counter -le 10 ]
        then
           (( counter++ ))
        else
           counter=-1
           break;
        fi
     done

     if [ $counter -lt 1 ]
     then
          return -1
     else
          return 0
     fi
}


############################################################################### 
#
# Creates the docker networks that were defined in the demo file for the system
# This will process a Json array of network names to be created
#
# args:
#    1 - Json array containing the network names (ex: ["net1","net2","net3"])
############################################################################### 
create_networks ()
{
   local i=0
   local netJson=$1
   local networksCnt=`echo $netJson |jq ".|length"`
   for ((i=0; i<$networksCnt; i++))
   do
      local networkName=`echo $netJson |jq ".[$i]"`
      local networkName=${networkName//\"}
      echo $networkName
      if [ -z "$networkName" ] || [ "$networkName" = "null" ]
      then
         echo WARNING: Can not create a network of null value
      else
         # if the network doesn't exist already then create it 
         # else use the existing one
         local cmd="docker network ls | grep $networkName | wc -l"
         if [ $(eval $cmd) -eq 0 ]
         then
            docker network create "$networkName" > /dev/null
            # quick check to see if the network was created or exists
            if [ $(eval $cmd) -ne 1 ]
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


############################################################################### 
# 
# CORE function on how the docker command is built before execution of the
# command.  This builds based on the informtion defined in the Json file.  Each
# element in the case statement below are what COULD be in the Json "Configs"
# section of an asset (container) used as part of sysetem (application with 1
# or more asset) used as part of a demo environment.
#
# args:
#    1 - This would receive the Assets element (single element) and then
#        would parse it to build the docker run command.
# return:
#    string - echos the string built so on the calling side you must use
#             myDockerCmd=$(build_docker_string $json)
############################################################################### 
build_docker_string ()
{
   local count=0
   local foundContainerName=false
   local foundImage=false
   local configs=$1
   local items=`echo $configs|jq ".Configs|keys|.[]"`

   local str=''
   local item=''
   for item in $items
   do
      #Remove the quotes around the string
      item=${item%\"}
      item=${item#\"}
      local value=`echo $configs|jq ".Configs.$item"`
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
            if [ "$count" -gt 0 ]
            then
               local s=''
               local x=0
               for ((x=0; x<$count; x++))
               do
                  local tmp=`echo $value|jq ".[$x]"`
                  s="$s-p $tmp "
               done
               str="$s$str"
            fi
            ;;
         Networks)
            count=`echo $value|jq ".|length"`
            if [ "$count" -gt 0 ]
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
            if [ "$count" -gt 0 ]
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
            if [ "$count" -gt 0 ]
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
            if [ "$count" -gt 0 ]
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

############################################################################### 
# 
# args:
#    1 - Json string object containing configurations
############################################################################### 
start_Postgres ()
{
   echo "###"
   echo "### Example of command need to validate before operational"
   echo "###"
   local docker_str=$(build_docker_string "$1")
   local cmd="docker run -d --restart=always $docker_str"
   echo "$cmd"
   #eval $cmd
}

############################################################################### 
# 
# args:
#    1 - Json string object containing configurations
############################################################################### 
start_MobileCenter ()
{
   echo "###"
   echo "### Example of command need to validate before operational"
   echo "###"
   local docker_str=$(build_docker_string "$1")
   local cmd="docker run -d --restart=always $docker_str"
   echo "$cmd"
   #eval $cmd
}


############################################################################### 
# 
# This is the function to invoke the Jenkins container.
#
# NOTE - Log checking to ensure proper invocation will be added later
# args:
#    1 - Json string object containing configurations
############################################################################### 
start_Jenkins ()
{
   local docker_str=$(build_docker_string "$1")
   local cmd="docker run -d --restart=always $docker_str"
   echo "$cmd"
   eval $cmd
}

############################################################################### 
# 
# This is the function to invoke the Oracle Express container.  It is
# intentional here that if we don't find the message to allow things to continue
# It could be just that things were super slow but will be up by the time
# everything is ready.  This is why there is only a warning to indicate there
# MAY be an issue not that there is an issue.
#
# args:
#    1 - Json string object containing configurations
############################################################################### 
start_OracleXE ()
{
   local docker_str=$(build_docker_string "$1")
   local cmd="docker run -d --shm-size=2g --restart=always $docker_str"
   echo "$cmd"
   eval $cmd

   local searchmsg="\"Database ready to use\""
   # Wait for the db to be up and ready
   echo "Waiting on database to be ready"
   echo "   -> sleeping for 20 sec before checking"
   sleep 20
   local tmp=`echo $1|jq '.Configs.ContainerName'`
   tmp=${tmp//\"}
  
   local cmd="docker logs $tmp"
   wait_on "$cmd" "$searchmsg"
   if [ $? -eq 0 ]
   then
      echo Database is ready
   else
      echo WARNING -- the database doesn\'t look like it came up
   fi
}

############################################################################### 
# 
# This is the function to invoke the ElasticSearch container.
# We should look into what log might indicate if there is an issue when it
# starts.  Up to now, there has never been an issue with it starting and is 
# available almost instantly
#
# args:
#    1 - Json string object containing configurations
############################################################################### 
start_ElasticSearch()
{
   local docker_str=$(build_docker_string "$1")
   local cmd="docker run -d --restart=always $docker_str"
   echo $cmd
   eval $cmd
}

############################################################################### 
# 
# Starting the Octane container requires a FQDN name for the hostname for the
# Jenkins plugin to connect successfully with it.  This is the reason for the 
# slight deviation whe additional commands are added when compared to other
# containers.
#
# It was intentional here that if we don't find the message to allow things to
# continue.  It could be just that things were super slow but will be up by
# the time everything is ready.  This is why there is only a warning to
# indicate there MAY be an issue not that there is an issue.
#
# args:
#    1 - Json string object containing configurations
############################################################################### 
start_Octane ()
{
   local docker_str=$(build_docker_string "$1")

   # little hack to have the container start with a FQDN
   local tmp=`echo $1|jq ".Configs.ContainerName"`
   # string manipulation.  refer to the "Resource references" section at top
   tmp=${tmp%\"}
   tmp=${tmp#\"}
   local hostname_str="--hostname=\"$tmp"
   tmp=`echo $1|jq ".Configs.EnvironmentVariables[0]"`
   # takes tmp and replaces globally '//' the occurance of "SERVER_DOMAIN= with nothing
   tmp=${tmp//\"SERVER_DOMAIN=/}
   hostname_str="$hostname_str.$tmp"
   local cmd="docker run -d --restart=always $hostname_str $docker_str"
   echo $cmd
   eval $cmd
   #Might need to turn off the proxy as set by Israel
   # -e "http_proxy=" -e "https_proxy="
   #docker run -d -p $1:8080 -e "SERVER_DOMAIN=$2" -e "ADMIN_PASSWORD=$3"  -e "DISABLE_VALIDATOR_MEMORY=true" -v /opt/octane/conf:/opt/octane/conf -v /opt/octane/log:/opt/octane/log -v /opt/octane/repo:/opt/octane/repo --net $4 --name $5 --hostname="$5.$2" --restart=always $6

   #brute search for log folder
   local i=''
   local logPath=''
   local volumeList=`echo $1 |jq ".Configs.Volumes[]"`
   for i in $volumeList
   do
      # refer to "Reference resources" above for string parsing
      i=${i//\"} # remove all quotes.  assumpiton is a quoted string
      # assumption is wrapper.log is found in the octane log folder
      if [ ${i##*/} = "log" ]
      then
         local logPath=${i%:*}
      fi
   done
   cmd="tail -50 $logPath/wrapper.log"
   local searchstr="\"Server is ready! (Boot time\""
   echo "Waiting on Octane to be ready"
   echo "   -> sleeping for 30 sec before checking"
   sleep 30
   wait_on "$cmd" "$searchstr"
   if [ $? -eq 0 ]
   then
      tail -2 $logPath/wrapper.log
   else
      echo WARNING -- Octane doesn\'t look like it came up
      echo
      tail -10 $logPath/wrapper.log
      echo
      echo Things could be just going slow or there could be an issue.
      echo Look in the $logPath/wrapper.log file for
      echo     'Server is ready! (Boot time XX seconds)'
   fi
}

############################################################################### 
#
# Queries the Json string to select container names of all the assets for the
# demo selected.
#
# usage example: myContainerList=$(container_list $demoSelected $jsonStr)
# args:
#   1 - demo sysem selected
#   2 - Json string of dependencies for the demo
# return:
#   Json list of containers.
############################################################################### 
container_list ()
{
   local containers=`echo $2 |jq ".[$1].Dependencies.Systems[].Assets[].Configs |select (.ContainerName) |.ContainerName"`
   echo "$containers"
}

############################################################################### 
#
# List of container names to be stopped by Docker
#
# args:
#   1 - list of container names
############################################################################### 
stop_containers ()
{
   local containerList=$1
debug $1
   echo Stopping containers $containerList
   local cmd="docker stop $containers"
   eval $cmd
}

############################################################################### 
#
# List of container names to be started by Docker
#
# args
#   1 - list of container names
############################################################################### 
start_containers ()
{
   echo Need to add a check to see if the the container exists in the stopped state
   local containerList=$1
   echo Starting containers $containerList
   local cmd="docker start $containers"
   eval $cmd
}

############################################################################### 
#
# List of container names to be removed by Docker
#
# args
#   1 - list of container names
############################################################################### 
remove_containers ()
{
   local containerList=$1
   local i=0
   #create a list of folder mounts to be removed after container removed
   for i in $containerList
   do 
      i=${i//\"}
      if [ $i != "jenkins" ] && [ $i != "jenkins-dc" ]
      then
         local folderList=("${folderList[@]}" "`docker inspect $i |jq '.[].Mounts[].Source'`")
      fi
   done

   echo Removing containers $containerList
   # using the -v to remove any volume mounts with the container
   local cmd="docker rm -v $containers"
   eval $cmd

   # remove folders used for mounts
   for i in "${folderList[@]}"
   do
      cmd="rm -rf $i"
      eval $cmd
   done
}

############################################################################## 
#
#
#
############################################################################## 
remove_images ()
{
   local images=`docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}"`
   unset options
   local index=0
   local menuItem=1
   local firstLine=1
   IFS=$'\n'
   for i in $images
   do
      if [ $firstLine -eq 0 ]
      then
         options[index]=$menuItem
         let index++
         options[index]="$i"
         let index++
         options[index]=off
         let index++
         let menuItem++
      else
         firstLine=0
         local title="$i"
      fi
   done
   local cmd=(dialog --backtitle "$bt" --checklist "          $title" 18 76 $menuItem)
   local choice=$("${cmd[@]}" "${options[@]}" 2>&1 >/dev/tty)

   #have_network_connection
   #if [ $? -eq 0 ]
   #then
   #   cmd=(dialog --backtitle "$bt" --title "WARNING -- WARNING -- WARNING" --defaultno --yesno "No network connection.  Are you sure you wish to remove?  You will need to establish a network connection before you can re-download any images" 19 76)
   #   $("${cmd[@]}" 2>&1 >/dev/tty)
   #   if [ $? -eq 0 ]
   #   then 
   #     echo "continue"
   #   else
   #     echo stop
   #   fi

      echo "Images aren't be removed right now.. this is just display/test purpose"
      IFS=$' '
      for i in $choice
      do
         let menuItem=($i*3)-2
         #from the right, delete the longest
         local image=${options[$menuItem]%% *}
         #from left, delete the shortest until space
         #so everything to the right of the image name
         local tag=${options[$menuItem]#* }
         #get rid of MB/GB or what ever
         tag=${tag% *}
         #get rid of the image size
         tag=${tag% *}
         #remove all remaing blank spaces
         tag=${tag// }

         echo "docker rmi $image:$tag"
      done
}

############################################################################### 
#
# Checks if the containers exist already and asks if you wish to remove them.
# If you choose NO, then the scripts exits immediately.  Plan to add function
# to start stopped containers.
#
# args
#   1 - demo menu choice
#   2 - demo system json
#
# return
#   exits if you choose not to remove the containers: 0 - yes remove -1 - no
############################################################################### 
show_container_warning ()
{
   local containers=$(container_list "$1" "$2")
   local cmd=(dialog --backtitle "$bt" --title "WARNING" --defaultno --yesno "One of these containers exist:\n     $containers\nYou must take care of them before performing this operation.\n\n         DO YOU WANT TO STOP AND REMOVE THEM" 19 76)

   ("${cmd[@]}" 2>&1 >/dev/tty)
   choice=$?
   if [ $choice -eq 0 ]
   then
      echo Removing...
debug "flynn: $containers"
      stop_containers "$containers"
      remove_containers "$containers"
      return 0
   else
      return -1
   fi
}

############################################################################## 
#
# Check to see if the container exists in docker
#
# args:
#    1 - demo menu choice
#    2 - demo json system
#
# return:
#    count - the number of containers found to exist for the demo selected
############################################################################### 
containers_exist ()
{
   local i=''
   local count=0

   local containers=$(container_list "$1" "$2")
   #Change the Internal Field Separator to newline for easy processing
   IFS=$'\n'

   let count=0
   for i in $containers
   do
     i=${i//\"}
     local cmd="docker ps -a --format='{{.Names}}' |grep -w "$i" |wc -l"
     let count=($count)+$(eval $cmd)
   done
   echo "$count"
}

############################################################################## 
#
# Downloads the data files which were needed for the demo
#
# args:
#    1 - Json string (ex: {"File":"myoradata.tar.gz", "Path":"/opt/oradata"}
#
############################################################################## 
download_files ()
{
       local tmpJson="$1"
       local restoreLocation=`echo $tmpJson |jq -r ".Path"`
       local rootPath=${restoreLocation%/*}
       local targetFolder=${restoreLocation##*/}
       local file=`echo $tmpJson |jq -r ".File"`

       echo "Processing: $file"
       if [ -e "$localDemoDataRepo/$file" ]
       then
            echo "$file" exists already locally so no need to download
       else
            cd "$rootPath" && { \
               curl -O "$remoteDemoDataRepo/$file" ; \
               cd -; }
       fi

       echo "Uncompressing to $rootPath" 
       echo "tar -zxf $file" "$targetFolder" 
       cd "$rootPath" && { \
          tar -zxf "$file" "$targetFolder" ; \
          cd -; }
}


############################################################################## 
#
# Will return an array (list) based on the json query passed
#
# args:
#    1 - json query string
#    2 - json
#
# return:
#   none - uses global varialbe 'options'
############################################################################## 
get_list ()
{
   unset options
   local queryStr=$1
   local jsonStr=$2

   IFS=$'\n'
   local index=1 #index of the array element
   local menuItem=1 #menu item number
   for i in `echo $jsonStr |jq "$queryStr"`
   do  
      options[index]=$menuItem
      let index++
      options[index]="${i//\"}" #remove all "
      let index++
      let menuItem++
   done
   #let index++
   #options[index]=$menuItem
   #let index++
   #options[index]="Quit/Exit"
}


############################################################################## 
#
# Show demos one can select from
#
# args:
#    1 - Json of available demos
#
# return:
#    choice - the item number selected from the list OR null if cancel selected
############################################################################## 
show_demos ()
{
   local jsonStr=$1
   get_list ".[].Name" "$jsonStr"

   #get the length of the array ${#options[@]} then divide by 2
   #and must use $(( )) to perform the division expression and return the result
   local demoEntries=$((${#options[@]}/2))
   local cmd=(dialog --backtitle "$bt" --menu "Select options:" 19 76 $demoEntries)
   local choice=$("${cmd[@]}" "${options[@]}" 2>&1 >/dev/tty)
   
   echo "$choice"
}

############################################################################## 
#
# Deploy Containers
#
# args:
#    1 - json string with available demos
#
##############################################################################
deploy_containers ()
{
   local jsonStr=$1
   local deploy=1
   local ret=$(show_demos "$jsonStr")
   if [ -n "$ret" ]
   then
      local x=$(containers_exist "$ret" "$jsonStr")
      if [ $x -ne 0 ]
      then
         deploy=$(show_container_warning "$ret" "$jsonStr")
      else
         deploy=0
      fi

      if [ $deploy -eq 0 ]
      then
         clear
         echo $ret
         local networksJson=`echo $jsonStr |jq ".[$ret].Dependencies.Networks"`
         create_networks "$networksJson"
         local systemsJson=`echo $jsonStr |jq ".[$ret].Dependencies.Systems"`
         local systemsCnt=`echo $systemsJson |jq ".|length"`
         echo System Count: "$systemsCnt"

         for ((systemsIndex=0; systemsIndex<$systemsCnt; systemsIndex++))
         do
            echo "###########################################"
            echo "###########################################"
            echo "######" Deploying System: `echo $systemsJson |jq ".[$systemsIndex].Name"`
            local assetsJson=`echo $systemsJson |jq ".[$systemsIndex].Assets"`
            local assetsCnt=`echo $assetsJson |jq ".|length"`
            for ((assetsIndex=0; assetsIndex<assetsCnt; assetsIndex++))
            do
               local assetName=`echo $assetsJson |jq -r ".[$assetsIndex].Name"`
               #assetName=${assetName//\"}
               local dataJson=`echo $assetsJson |jq ".[$assetsIndex].Data"`
               if [ `echo $dataJson |jq ".|length"` -eq 2 ]
               then
                  download_files "$dataJson"
               fi
               echo
               echo "###########################################"
               echo "Deploying Asset: $assetName"
               local assetJson=`echo $assetsJson |jq ".[$assetsIndex]"`

               # It was intentional to have generic funciton call
               # as different assets had different ways to montior/log
               # how to see if they were up completely.  Open to ideas
               # to not be dependent on each asset name being a key to work
               start_"$assetName" "$assetJson"
               echo "###########################################"
               echo
            done
            echo
            echo
         done
      else
         echo Deployment aborted
      fi
   fi
}

############################################################################## 
#
# Remove Images will display all the images in the local docker cache (repo)
# and you can select the images to remove.
#
# args:
#   none
##############################################################################
remove_images ()
{
   unset options
   #images=`docker images --format "{{.Repository}}"`
   local images=`docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}"`
   local index=1
   local menuItem=1
   local firstLine=1
   IFS=$'\n'
   for i in $images
   do
      if [[ $firstLine -eq 0 ]]
      then
         options[index]=$menuItem
         let index++
         options[index]="$i"
         let index++
         options[index]=off
         let index++
         let menuItem++
      else
         firstLine=0
         title="$i"
      fi
   done
   cmd=(dialog --backtitle "$bt" --checklist "          $title" 18 76 $menuItem)
   echo ${cmd[@]} ${options[@]}
   choice=$("${cmd[@]}" "${options[@]}" 2>&1 >/dev/tty)
   debug "No removes, selection was $choice"
   have_network_connection
}

############################################################################## 
#
# Remove demo data will display all the demo data files (used for creating
# new contianers) from the local data store (file system)
#
# args:
#   none
##############################################################################
remove_demo_data ()
{
   unset options
   local files=(`ls -a $localDemoDataRepo/*.tar.gz`)
   local index=1
   local menuItem=1
#   IFS=$'\n'
   for i in ${files[@]}
   do
      options[index]=$menuItem
      let index++
      options[index]="$i"
      let index++
      options[index]=off
      let index++
      let menuItem++
   done
   local cmd=(dialog --backtitle "$bt" --checklist "Demo data files" 18 76 "${#options[@]}")
   local choice=$("${cmd[@]}" "${options[@]}" 2>&1 >/dev/tty)
   debug "No removes, selection was $choice"

   have_network_connection
}
############################################################################## 
#
# Main Menu Selections
#
##############################################################################
main_menu ()
{
   declare -a options=(1 "Start Containers" 2 "Stop Containers" 3 "Deploy Containers" 4 "Remove Containers" 5 "Remove Images" 6 "Remove Demo Data")
   local itemCount=$((${#options[@]}/2))
   local cmd=(dialog --backtitle "$bt" --menu "Select options:" 19 76 $itemCount)
   local choice=$("${cmd[@]}" "${options[@]}" 2>&1 >/dev/tty)

   echo "${options[$(($choice*2-1))]}"
}


##############################################################################
#
#                Main Script
#  
##############################################################################
have_demofile $#
demosJson=`jq ".Demos" $1`
is_sudo

while :
do
   ret=$(main_menu)
   if [ -z "$ret" ]
   then
      clear
      echo Goodbye
      exit
   else
      case "$ret" in
         "Start Containers")
            `dialog --msgbox "Selected: $ret" 0 0 2>&1>/dev/tty`
            ;;
         "Stop Containers")
            `dialog --msgbox "Selected: $ret" 0 0 2>&1>/dev/tty`
            ;;
         "Deploy Containers")
            #`dialog --msgbox "Selected: $ret" 0 0 2>&1>/dev/tty`
            deploy_containers "$demosJson"
            ;;
         "Remove Containers")
            `dialog --msgbox "Selected: $ret" 0 0 2>&1>/dev/tty`
            ;;
         "Remove Images")
            #`dialog --msgbox "Selected: $ret" 0 0 2>&1>/dev/tty`
            remove_images
            ;;
         "Remove Demo Data")
            #`dialog --msgbox "Selected: $ret" 0 0 2>&1>/dev/tty`
            remove_demo_data
            ;;
         *)
            `dialog --msgbox "Unable to handle.\n\nOption not known" 0 0 2>&1>/dev/tty`
            ;;

      esac
   fi
done
