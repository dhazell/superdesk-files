#!/bin/bash
#this script manages the start and stopping etc of the AAP Superdesk docker environment

[ "`whoami`" == "superdesk" ] || exit #only run this script if logged in as superdesk
action=$1
HOME=/home/superdesk
script="$HOME/superdesk/scripts/docker-local-aap.sh"
logfile="$script.log"
ScriptVersion=0.9.94
cd $HOME

function superdesk-build ()
{
 echo "about to build a new set of docker containers for Superdesk from scratch"

 ### #get sudo rights before continuing
 ### sudo -s exit
 ### [ $? -ne 0 ] && exit #dont continue unless sudo is happy

 #save old file superdesk filetree
 echo "about to archive old superdesk filetree"
 echo "(note that existing elastic mongodb and redis data is left in original location for use later)"
 [ -d $HOME/superdesk ] && mv $HOME/superdesk $HOME/superdesk-$(date '+%C%y%m%d.%H%M%S')

 #clone superdesk repo from git
 rm -rf $HOME/superdesk
 git clone https://github.com/superdesk/superdesk.git

 #install python-virtualenv if not already installed , if already installed then no problem
 #sudo apt-get install -y python-virtualenv

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
 run-docker-compose    #run the docker-compose script
 wait-until-superdesk-is-running
 superdesk-init-env #initialise the superdesk environment
}

function superdesk-rebuild ()
{
 echo "about to run the $script script but don't init environment"
 run-docker-compose            #run the docker-compose script
 wait-until-superdesk-is-running
}

function run-docker-compose ()
{
 #run the $script script to build the containers
 script-status
 local PID="`find-pid`"
 echo "if the $script script is already running then stop the script ..."
 if [ $PID -gt 0 ]; then
   echo "$script script is already running (PID:$PID), so need to stop script before continuing"
   echo "about to stop the containers referenced by the superdesk/docker/docker-compose.yml script"
   script-status
   if [ -f $HOME/superdesk/docker/docker-compose.yml ]; then
     echo "About to run: docker-compose stop"
     cd $HOME/superdesk/docker
     docker-compose stop
     cd $HOME
    else
     echo "Superdesk is not currently installed as no docker-compose.yml exists"
     echo "Use docker commands to stop any containers and then retry this script"
     exit
   fi
 fi
 echo "about to run the $script script ..."
 $script 2>&1 > $logfile 2>&1 &
 sleep 2
 echo "system is starting ..."
 script-status
 echo -e "\nFor more information, in another shell, tail the logfile :\ntail -100f $logfile"
}

function wait-until-superdesk-is-running ()
{
 #wait until system is built (ie 'Done, without errors.' is seen in the logfile) before continung
 while [ "`cat $logfile | grep 'Done, without errors.'`" == "" ]; do
   echo -n "."
   sleep 1
  done
 #sleep 60
}

function superdesk-init-env ()
{
 #run the script to initialize the environment
 echo "about to initialize setup"
 ./superdesk/scripts/docker-initial-setup.sh
 echo "setup initialized"
}

function find-pid () {
 #figure out PID of $script
 local PID="`ps -ef | egrep "/bin/bash" | egrep "$script" | egrep -v egrep | awk '{print $2}' | head -1`" #note head -1 is not ideal but used to overcome rare situation where there is more than one matching line
 [ "$PID" == "" ] && PID=-1
 echo $PID
}

function containers-status ()
{
 echo "#####################"
 echo "LIST RUNNING CONTAINERS"
 docker ps
 echo "#####################"
 echo "LIST ALL CONTAINERS:"
 docker ps -a
 echo "#####################"
}

function script-status () {
 local PID="`find-pid`"
 #[ "$PID" == "0" ] && echo "script: $script is running (PID:$PID)"
 #[ "$PID" == "0" ] || echo "script: $script is NOT running"
 [ $PID -gt 0 ] && echo "script: $script is running (PID:$PID)"
 [ $PID -gt 0 ] || echo "script: $script is NOT running"
}

function usage () {
 echo "Usage : $0"
 echo "NOTE: if containers need to be stopped or removed or if environment needs to be taken back to known state, then use docker commands as required to manage the containers."
 echo "   eg : $0 superdesk-build       #used to   build superdesk environment (clones from git, builds containers, connects containers together, initializes superdesk environment)"
 echo "   eg : $0 superdesk-rebuild     #used to rebuild superdesk environment (                 builds containers, connects containers together)"
 echo ""
 echo "   eg : $0 superdesk-init-env    #used to initialise the superdesk environment"
 echo ""
 echo "   eg : $0 containers-status     #used to get status of superdesk containers"
 echo "   eg : $0 script-status         #used to get status of $script used to start superdesk environment"
}

#main
echo "ScriptVersion is $ScriptVersion"
case $action in
 superdesk-build       ) superdesk-build;;
 superdesk-rebuild     ) superdesk-rebuild;;
 superdesk-init-env    ) superdesk-init-env;;
 containers-status     ) containers-status;;
 script-status         ) script-status;;
 *                     ) usage;;
esac

