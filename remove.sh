#! /bin/bash

function remove {

    # get current script path, resolve $SOURCE until the file is no longer a symlink
    SOURCE=${BASH_SOURCE[0]}
    while [ -h "$SOURCE" ]; do
        DIR="$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)"
        SOURCE="$(readlink "$SOURCE")"
        [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
    done
    CURRENT_DIR="$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)"

    # stop / disable systemd service, remove config file
    systemctl stop  motioncamviewer 
    systemctl disable motioncamviewer 
    rm /etc/systemd/system/motioncamviewer.service

    # restore old motion configuration, restart motion
    cp /etc/motion/motion.conf /etc/motion/motion.conf_MCVIEWER_RM_BAK 
    rm /etc/motion/motion.conf
    mv /etc/motion/motion.conf_MCVIEWER_BAK /etc/motion/motion.conf
    systemctl restart motion
    
    # remove log file
    rm /var/log/motioncamviewer.log
    
    # delete motioncamviewer user
    userdel -rf motioncamviewer

    # remove local installed node.js modules
    rm -r "${CURRENT_DIR}/node_modules"
    
    # remove SSL setup data if exist
    if [ -e "${CURRENT_DIR}/key.pem" ]; then
        rm "${CURRENT_DIR}/key.pem"
    fi
    if [ -e "${CURRENT_DIR}/cert.pem" ]; then
        rm "${CURRENT_DIR}/cert.pem"
    fi

    # remove hidden service dir if exist, restore tor config, restart tor
    HIDDENSERIVE_DIR="/var/lib/tor/motioncamviewer/"
    if [ -e "$HIDDENSERIVE_DIR" ]; then
        cp /etc/tor/torrc /etc/tor/torrc_MCVIEWER_RM_BAK 
        rm /etc/tor/torrc 
        mv /etc/tor/torrc_MCVIEWER_BAK /etc/tor/torrc 
        rm -r "${HIDDENSERIVE_DIR}";
        systemctl restart tor
    fi
    
    # user output
    echo "---"
    echo "removed all files created while setup"
    echo "removed system user: motioncamviewer"
    echo "remove those files manually if anything works fine after reboot:"
    echo "rm /etc/tor/torrc_MCVIEWER_RM_BAK"
    echo "rm /etc/motion/motion.conf_MCVIEWER_RM_BAK"
    echo "rm ${CURRENT_DIR}/config.json"
    echo "---"
    echo "motion cam viewer uninstaller complete"
}

# ask for uninstall
echo "motion cam viewer uninstaller for Debian based systems"
echo "root permissions required for setup (we ask for root in next step)"
DOREMOVE=""
while [ "$DOREMOVE" != "y" -a "$DOREMOVE" != "n" ]; do
    read -p "continue to remove motion cam viewer? [y/n]: " DOREMOVE
done
if [ "$DOREMOVE" == "n" ]; then
    exit
fi

# check root, ask for root
WHOAMI=$(whoami)
if [ "$WHOAMI" != "root" ]; then
    su -c "$(declare -f remove); remove"    
else
    remove
fi 
