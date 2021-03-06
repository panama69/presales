#!/bin/bash

if [[ $# -lt 1 ]] ; then
    echo 'usage:  ./processJobs.sh http://<jenkinshost>:<port>'
    echo '    if using accounts: ./processJobs.sh http://<username>:<userpassword>@<jenkinshost>:<port>'
    exit 1
fi
#HOST="http://localhost:8085"
HOST="$1"
ALLGOOD=0
EXP_JOBS="exported_jobs"

clear
echo Utility to Export or Import Jenkins Jobs
PS3='Please enter the number of your choice to perform: '
options=("Export jobs" "Import jobs")
select opt in "${options[@]}" "Quit"
do
  case "$REPLY" in
    1)
      #check if location exists to place the exported jobs
      if [[ -d ./"$EXP_JOBS" ]]
      then
           PS3='An export folder exists.  Do you want to overwrite?'
           yesno=("Yes" "No")
           select ans in "${yesno[@]}"
           do
                case "$REPLY" in
                     1|'Y'|'y')
                          ALLGOOD=1
                          break;;
                     2|'N'|'n')
                          ALLGOOD=0
                          break;;
                esac
           done
      fi
      if [[ ! -d ./"$EXP_JOBS" ]]
      then
        mkdir "$EXP_JOBS"
      fi

   if [[ "$ALLGOOD" -eq 1 ]]
   then
      #check if jar file exists for use and download if doesnt
      #this is simple in that assumption is the HOST is accessible
      if [[ ! -f ./jenkins-cli.jar ]]
      then
        echo Must download the Jenkins CLI
        curl -O $HOST/jnlpJars/jenkins-cli.jar
        #giving a little time to make sure the writes are completed
        sleep 1
      fi
      #should enhance to check for spaces in the job name as they need to be replaced with %20 for web safe
      for job in `java -jar jenkins-cli.jar -s $HOST list-jobs`
      do
        echo Exporting: $job
        curl $HOST/job/$job/config.xml -o ./"$EXP_JOBS"/$job.xml &> /dev/null
      done
    fi
      break
      ;;
    2)
      for job in `ls "$EXP_JOBS"/*.xml`
      do
        echo Importing: $job
        jobName=`echo $job|awk -F"/" '{print $2}'|awk -F"." '{print $1}'`
        curl --fail -X POST $HOST/createItem?name=$jobName --header "Content-Type: application/xml" -d "@$job"
      done
      break
      ;;
    3|'q'|'Q')
      break
      ;;
    *)
      echo invalid option
      ;;
  esac
done
