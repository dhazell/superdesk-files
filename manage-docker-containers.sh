#!/bin/bash
#this script manages the start and stopping etc of the AAP Superdesk docker environment

[ "`whoami`" == "superdesk" ] || exit #only run this script if logged in as superdesk
action=$1
script="superdesk/scripts/docker-local-aap.sh"
logfile="$script.log"
ScriptVersion=0.9.92
cd /home/superdesk

function destroy-containers ()
{
 echo about to stop and delete any containers and rename old $logfile logfile if it exists
 if [ "`docker ps -aq`" != "" ]; then
   echo stopping running containers ...
   docker stop $(docker ps -q) # > /dev/null
   echo deleting all containers ...
   docker rm $(docker ps -aq)  # > /dev/null
   sleep 5
 fi
 [ -f $logfile ] && mv $logfile $logfile-$(date '+%C%y%m%d.%H%M%S')
}

function build-containers ()
{
 echo about to build a new set of docker containers for Superdesk from scratch

 #get sudo rights before continuing
 sudo -s exit
 [ $? -ne 0 ] && exit #dont continue unless sudo is happy

 #clear out old containers
 destroy-containers

 #save old file superdesk filetree
 echo about to archive old superdesk filetree
 echo "(note that existing elastic mongodb and redis data is left in original location for use later)"
 [ -d superdesk ] && mv superdesk superdesk-$(date '+%C%y%m%d.%H%M%S')

 #clone superdesk repo from git
 git clone https://github.com/superdesk/superdesk.git

 #install python-virtualenv if not already installed , if already installed then no problem
 sudo apt-get install -y python-virtualenv

 #get docker-compose.yml file ready for aap
 #make backup file of docker-compose.yml
 cp -p superdesk/docker/docker-compose.yml superdesk/docker/docker-compose.yml-$(date '+%C%y%m%d.%H%M%S')
 #update ip-addresses
 export ip=$(ifconfig eth0 |  perl -ne 'print if /inet addr/' | perl -pe 's|.*?(\d+.\d+.\d+.\d+).*|$1|'); perl -pi -e 's/127.0.0.1/$ENV{ip}/g' superdesk/docker/docker-compose.yml
 #add references for TZ to be australian sydney time not UTC
 perl -e 'undef $/; $file=<>; while ($file=~m/(.+?\n)(\b|$)/isg) {$data=$1;  if ( $data!~m|environment:| ) {$data =~ s|(\w.+?:)|$1\n  environment:|is; }; $data =~ s|(environment:)|$1\n   - TZ=Australia/Sydney|is; print "$data\n";}' superdesk/docker/docker-compose.yml > /tmp/docker-compose.yml; mv /tmp/docker-compose.yml superdesk/docker/docker-compose.yml
 #line up key value pairs in yml file
 perl -pi -e 's|^  -|   -|'                superdesk/docker/docker-compose.yml
 #modify data path to make sure mongo elastic redis data is stored outside the superdesk filetree
 perl -pi -e 's|- ../data/|- ../../data/|' superdesk/docker/docker-compose.yml

 #Update docker-compose version in requirements.txt to match latest available version
 cp -p superdesk/docker/requirements.txt superdesk/docker/requirements.txt-$(date '+%C%y%m%d.%H%M%S')
 perl -pi -e 's|docker-compose==1.2.0|docker-compose==1.3.0|' superdesk/docker/requirements.txt

 #Create a docker-initial-setup.sh to be used later
 cp -p ./superdesk/scripts/docker-local-create-user.sh ./superdesk/scripts/docker-initial-setup.sh
 perl -pi -e 's|(docker-compose.*)|docker-compose run backend ./scripts/fig_wrapper.sh python3 manage.py app:initialize_data\n$1|' superdesk/scripts/docker-initial-setup.sh

 #Make aap version of the docker-local-demo.sh
 cp -p superdesk/scripts/docker-local-demo.sh $script

 #run the scripts and build the docker environment
 runScripts
}

function runScripts ()
{
 echo about to run the $script script and then the script to intialise environment

 #run the $script script to build the containers
 status-script
 local PID="`findpid`"
 if [ $PID -gt 0 ]; then
   echo "$script script is already running (PID:$PID), so exiting"
   exit
  else
   for instance in $(docker ps -q); do docker stop $instance; done  # stop running containers if they exist
   echo "about to run the $script script ..."
   $script 2>&1 > $logfile 2>&1 &
   sleep 2
   echo "system is starting ..."
   status-script
   echo -e "\nFor more information, in another shell, tail the logfile :\ncd ~\ntail -100f $logfile"
 fi

 #wait until system is built (ie 'Done, without errors.' is seen in the logfile) before continung
 while [ "`cat superdesk/scripts/docker-local-aap.sh.log | grep 'Done, without errors.'`" == "" ]; do
   echo -n "."
   sleep 1
  done
 echo waiting a minute before initializing the docker environment
 sleep 60

 #run the script to initialize the environment
 echo about to initialize setup
 ./superdesk/scripts/docker-initial-setup.sh
 echo setup initialized
}

function rebuild-containers ()
{
 echo about to call the runScripts funciton to run the $script script and then intialise environment
 runScripts
}

function findpid () {
 #figure out PID of $script
 local PID="`ps -ef | egrep "/bin/bash" | egrep "$script" | egrep -v egrep | awk '{print $2}' | head -1`" #note head -1 is not ideal but used to overcome rare situation where there is more than one matching line
 [ "$PID" == "" ] && PID=-1
 echo $PID
}

function stop-containers () {
 status-script
 for instance in $(docker ps -q); do docker stop $instance; done  # stop running containers if they exist
}

function kill-containers () {
 status-script
 for instance in $(docker ps -q); do docker kill $instance; done  # kill running containers if they exist
}

function status-containers ()
{
 docker ps
}

function status-script () {
 local PID="`findpid`"
 #[ "$PID" == "0" ] && echo "script: $script is running (PID:$PID)"
 #[ "$PID" == "0" ] || echo "script: $script is NOT running"
 [ $PID -gt 0 ] && echo "script: $script is running (PID:$PID)"
 [ $PID -gt 0 ] || echo "script: $script is NOT running"
}

function usage () {
 echo "Usage : $0"
 echo "   eg : $0 build-containers   #used to build the docker environment (clones from git, and builds from new repo, and runs and initializes the docker environment)"
 echo "   eg : $0 rebuild-containers #used to rebuild the docker environment (runs and initializes the docker environment)"
 echo "   eg : $0 stop-containers    #used to stop the containers in ihe docker environment"
 echo "   eg : $0 status-containers  #used to get status of the docker environment"
 echo "   eg : $0 status-script      #used to get status of the $script used to start docker environment"
 echo "   eg : $0 destroy-containers #used to destroy the docker environment"
 echo ""
 echo "      : Use command below with extra care as risk of corrupting data"
 echo "   eg : $0 kill-containers    #used to kill but not delete the containers in the docker environment"
}

#main
echo "ScriptVersion is $ScriptVersion"
case $action in
 build-containers   ) build-containers;;
 rebuild-containers ) rebuild-containers;;
 stop-containers    ) stop-containers;;
 status-containers  ) status-containers;;
 status-script      ) status-script;;
 destroy-containers ) destroy-containers;;
 kill-containers    ) kill-containers;;
 *                  ) usage;;
esac

