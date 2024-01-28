#!/bin/bash

# Stop on errors, comment in, if needed
#set -e

GAME_PATH="/palworld"

function installServer() {
    # force a fresh install of all
    echo ">>> Doing a fresh install of the gameserver"
    /home/steam/steamcmd/steamcmd.sh +force_install_dir "$GAME_PATH" +login anonymous +app_update 2394010 validate +quit
}

function updateServer() {
    # force an update and validation
    echo ">>> Doing an update of the gameserver"
    /home/steam/steamcmd/steamcmd.sh +force_install_dir "$GAME_PATH" +login anonymous +app_update 2394010 validate +quit
}

function startServer() {
    # IF Bash extendion usaged:
    # https://stackoverflow.com/a/13864829
    # https://pubs.opengroup.org/onlinepubs/9699919799/utilities/V3_chap02.html#tag_18_06_02

    echo ">>> Starting the gameserver"
    cd $GAME_PATH || exit 1

    echo ">>> Setting up Engine.ini ..."
    config_file="${GAME_PATH}/Pal/Saved/Config/LinuxServer/Engine.ini"
    pattern1="OnlineSubsystemUtils.IpNetDriver"
    pattern2="^NetServerMaxTickRate=[0-9]*"

    if grep -qE "$pattern1" "$config_file"; then
        echo "Found [/Script/OnlineSubsystemUtils.IpNetDriver] section"
    else
        echo "Found no [/Script/OnlineSubsystemUtils.IpNetDriver], adding it"
        echo -e "\n[/Script/OnlineSubsystemUtils.IpNetDriver]" >>"$config_file"
    fi
    if grep -qE "$pattern2" "$config_file"; then
        echo "Found NetServerMaxTickRate parameter, chaning it to $NETSERVERMAXTICKRATE"
        sed -E -i "s/$pattern2/NetServerMaxTickRate=$NETSERVERMAXTICKRATE/" "$config_file"
    else
        echo "Found no NetServerMaxTickRate parameter, adding it to $NETSERVERMAXTICKRATE"
        echo "NetServerMaxTickRate=$NETSERVERMAXTICKRATE" >>"$config_file"
    fi
    echo ">>> Finished setting up Engine.ini ..."

    echo ">>> Setting up PalWorldSettings.ini ..."
    echo "Checking if config exists"
    if [ ! -f ${GAME_PATH}/Pal/Saved/Config/LinuxServer/PalWorldSettings.ini ]; then
        echo "No config found, generating one"
        if [ ! -d ${GAME_PATH}/Pal/Saved/Config/LinuxServer ]; then
            mkdir -p ${GAME_PATH}/Pal/Saved/Config/LinuxServer
        fi
        # Copy default-config, which comes with the server to gameserver-save location
        cp ${GAME_PATH}/DefaultPalWorldSettings.ini ${GAME_PATH}/Pal/Saved/Config/LinuxServer/PalWorldSettings.ini

        # Print out message to user
        echo ">>> Please edit the config file ${GAME_PATH}/Pal/Saved/Config/LinuxServer/PalWorldSettings.ini and restart the server"
        echo ">>> Aborting server start ..."
        exit 1
    fi

    START_OPTIONS=""
    if [[ -n $COMMUNITY_SERVER ]] && [[ $COMMUNITY_SERVER == "true" ]]; then
        START_OPTIONS="$START_OPTIONS EpicApp=PalServer"
    fi
    if [[ -n $MULTITHREAD_ENABLED ]] && [[ $MULTITHREAD_ENABLED == "true" ]]; then
        START_OPTIONS="$START_OPTIONS -useperfthreads -NoAsyncLoadingThread -UseMultithreadForDS"
    fi
    ./PalServer.sh "$START_OPTIONS"
}

function startMain() {
    if [[ -n $BACKUP_ENABLED ]] && [[ $BACKUP_ENABLED == "true" ]]; then
        # Preparing the cronlist file
        echo "$BACKUP_CRON_EXPRESSION /backupmanager.sh" >>cronlist
        # Making sure supercronic is enabled and the cronfile is loaded
        /usr/local/bin/supercronic cronlist &
    fi

    # Check if server is installed, if not try again
    if [ ! -f "$GAME_PATH/PalServer.sh" ]; then
        installServer
    fi
    if [ $ALWAYS_UPDATE_ON_START == "true" ]; then
        updateServer
    fi
    startServer
}

term_handler() {
    kill -SIGTERM $(pidof PalServer-Linux-Test)
    tail --pid=$(pidof PalServer-Linux-Test) -f 2>/dev/null
    exit 143
}

trap 'kill ${!}; term_handler' SIGTERM

startMain &
killpid="$!"
while true; do
    wait $killpid
    exit 0
done
