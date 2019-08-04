#! /bin/bash

function setup {

    # check if depencies installed (motion, nodejs, npm) 
    if ! [ -x "$(command -v node)" ]; then
        echo "missing depency: node, can't find 'node'"
        echo "try: apt-get install node"
        exit 1
    fi 
    if ! [ -x "$(command -v npm)" ]; then
        echo "missing depency: npm, can't find 'npm'"
        echo "try: apt-get install npm"
        exit 1
    fi
    if ! [ -x "$(command -v motion)" ]; then
        echo "missing depency: motion, can't find 'motion'"
        echo "will do: apt-get install -y motion"
        apt-get install -y motion
        if ! [ -x "$(command -v motion)" ]; then
            echo "can't install missing depency: motion"
            echo "try: apt-get install motion"
            exit 1
        fi
    fi
    
    # get current script path, resolve $SOURCE until the file is no longer a symlink
    SOURCE=${BASH_SOURCE[0]}
    while [ -h "$SOURCE" ]; do
        DIR="$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)"
        SOURCE="$(readlink "$SOURCE")"
        [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
    done
    CURRENT_DIR="$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)"
    
    # ask for SSL setup
    SSLSETUP=""
    while [ "$SSLSETUP" != "y" -a "$SSLSETUP" != "n" ]; do
        read -p "setup SSL? [y/n]: " SSLSETUP
    done
    if [ "$SSLSETUP" = "y" ]; then
        
        # check for SSL depency
        if ! [ -x "$(command -v openssl)" ]; then
            echo "missing depency: openssl, can't find 'openssl'"
            echo "will do: apt-get install -y openssl"
            apt-get install -y openssl
            if ! [ -x "$(command -v openssl)" ]; then
                echo "can't install missing depency: openssl"
                echo "try: apt-get install openssl"
                exit 1
            fi
        fi
        
        # generate strong certificate, 10 years valid (-days 3650) 
        openssl req -x509 -newkey rsa:4096 -keyout ${CURRENT_DIR}/key.pem -out ${CURRENT_DIR}/cert.pem -days 3650
        
        # set certificate and private key in motion cam viewer config
        sed -i "s|\"ssl_privateKeyPath\": \".*|\"ssl_privateKeyPath\": \"${CURRENT_DIR}/key.pem\",|" "${CURRENT_DIR}/config.json"
        sed -i "s|\"ssl_certificatePath\": \".*|\"ssl_certificatePath\": \"${CURRENT_DIR}/cert.pem\",|" "${CURRENT_DIR}/config.json"
    fi

    # create unix user for service 
    useradd -r motioncamviewer

    # add user motioncamviewer to motion group
    adduser motioncamviewer motion

    # create log file
    touch /var/log/motion_cam_viewer.log
    chown motioncamviewer:motioncamviewer /var/log/motion_cam_viewer.log
    
    echo "Install node.js modules, generate random values. This will take some time..."

    # install node.js modules
    cd "${CURRENT_DIR}"
    npm install
    
    # generate random secret for salt & co, set in config
    SECRET=$(cat /dev/urandom | tr -cd 'a-f0-9' | head -c 32)
    sed -i "s|\"secret\": \".*|\"secret\": \"${SECRET}\",|" "${CURRENT_DIR}/config.json"
    
    # ask for cam viewer password, set random if empty, set in config.json
    PASSWORD=$(./set_password.sh);
        
    # ask for network interface, set local as default if empty
    echo "Which IP should be listened? (localhost: 127.0.0.1, local: 192.168.1.3 (use your local network IP), all IPs: 0.0.0.0)"
    read -p "enter your listening IP (leave empty for default: local network IP): " LISTENIP
    sed -i "s|\"networkInterface\": \".*|\"networkInterface\": \"${LISTENIP}\",|" "${CURRENT_DIR}/config.json"
    
    # ask for replace existing motion configuration
    REPLACEMONTIONCONFIG=""
    while [ "$REPLACEMONTIONCONFIG" != "y" -a "$REPLACEMONTIONCONFIG" != "n" ]; do
        read -p "replace motion configuration? [y/n] (use y, we backup the old one): " REPLACEMONTIONCONFIG
    done
    if [ $REPLACEMONTIONCONFIG = "y" ]; then
    
        # make image dir. motion default is: /var/lib/motion
        mkdir -p /home/motion/out/
        chown -R motion:motion /home/motion/
        chmod -R 775 /home/motion/

        # backup old motion config
        mv /etc/motion/motion.conf /etc/motion/motion.conf_MCVIEWER_BAK
        
        # generate user:pass for stream + control motion http auth, insert motion.conf template, overwrite motion config
        SECRETUSER=$(cat /dev/urandom | tr -cd 'a-f0-9' | head -c 16)
        SECRETPASS=$(cat /dev/urandom | tr -cd 'a-f0-9' | head -c 32)
        cat "${CURRENT_DIR}/etc/motion/motion.conf" | sed -Ee "s|(.*?)stream_authentication .*:.*|stream_authentication ${SECRETUSER}:${SECRETPASS}|" | sed -Ee "s|(.*?)webcontrol_authentication .*:.*|webcontrol_authentication ${SECRETUSER}:${SECRETPASS}|" > "/etc/motion/motion.conf"
        
        # set stream + control motion http auth in viewer config
        sed -i "s|\"motion_videoStreamAuth\": \".*|\"motion_videoStreamAuth\": \"${SECRETUSER}:${SECRETPASS}\",|" "${CURRENT_DIR}/config.json"
        sed -i "s|\"motion_controlUriAuth\": \".*|\"motion_controlUriAuth\": \"${SECRETUSER}:${SECRETPASS}\",|" "${CURRENT_DIR}/config.json"
        
        # restart motion, because of configuration changes
        echo "restart motion..."
        systemctl restart motion
        
    else
        echo "maybe you need to change motion path, control and stream configuration at: ${CURRENT_DIR}/config.json"
    fi

    # replace path in file, copy systemd config
    WHICHNODE=$(which node);
    cat "${CURRENT_DIR}/etc/systemd/system/motion_cam_viewer.service" | sed -e "s|##path##|${WHICHNODE}|g" | sed -e "s|##argument##|${CURRENT_DIR}\/app.js|g" > "/etc/systemd/system/motion_cam_viewer.service" 

    # enable & start motion cam viewer server
    echo "start motion_cam_viewer..."
    systemctl enable motion_cam_viewer
    systemctl start motion_cam_viewer    

    # system, file changes output
    echo "---"
    echo "login password: ${PASSWORD}";
    echo "listen to IP: ${LISTENIP}";
    echo "system user without shell created: motioncamviewer"
    echo "user: motioncamviewer added to group: motion"
    echo "files & folders changed:"
    echo "${CURRENT_DIR}/node_modules/"
    echo "/etc/motion.conf"
    echo "/etc/motion.conf_MCVIEWER_BAK"
    echo "/etc/systemd/system/motion_cam_viewer.service"
    echo "/var/log/motion_cam_viewer.log"
    echo "/home/motion/"
    echo "${CURRENT_DIR}/config.json"
    echo "---"
    echo "NOTICE: SSL setup need to be done manually. add absolute paths to: ./config.json : ssl_privateKeyPath, ssl_certificatePath"
    echo "motion cam viewer setup complete"
}

# ask for setup
echo "motion cam viewer setup"
echo "camera with motion support must be installed before running this setup"
echo "root permissions required for setup (we ask for root in next step)"
DOSETUP=""
while [ "$DOSETUP" != "y" -a "$DOSETUP" != "n" ]; do
    read -p "continue setup? [y/n]: " DOSETUP
done

if [ "$DOSETUP" = "n" ]; then
    exit
fi

# check root, ask for root
WHOAMI=$(whoami)
if [ "$WHOAMI" != "root" ]; then
    su -c "$(declare -f setup); setup"    
else
    setup
fi


