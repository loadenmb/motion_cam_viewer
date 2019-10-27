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
    
    # copy config template
    cp "${CURRENT_DIR}/config-sample.json" "${CURRENT_DIR}/config.json"
    
    # ask for port until port is integer
    PORT=""
    while [ -z "$PORT" ]; do
        read -p "HTTP server port [integer / 0 for default: 8024]: " PORT
        case $PORT in
            ''|*[!0-9]*) PORT="" ;;
            *) ;;
        esac
    done
    
    # set default HTTP port "8024" if 0
    if [ "$PORT" == "0" ]; then
        PORT=8024
    fi
    
    # set port in config
    sed -i "s|\"port\": [0-9]+|\"port\": ${PORT},|" "${CURRENT_DIR}/config.json"
    
    # ask for hidden service setup
    TORSETUP=""
    while [ "$TORSETUP" != "y" -a "$TORSETUP" != "n" ]; do
        read -p "setup tor hidden service? [y/n]: " TORSETUP
    done
    if [ "$TORSETUP" == "y" ]; then
    
        # check if tor is installed / install tor
        if ! [ -x "$(command -v tor)" ]; then
            echo "missing depency: tor, can't find 'tor'"
            echo "will do: apt-get install -y motion"
            apt-get install -y tor
            if ! [ -x "$(command -v tor)" ]; then
                echo "can't install missing depency: tor"
                echo "try: apt-get install tor"
                exit 1
            fi
        fi
        
        # backup tor config
        cp /etc/tor/torrc /etc/tor/torrc_MCVIEWER_BAK
        
        # setup basic authenticated hidden service sshd
        # NOTICE: sed -i '1i XXX' FILEPATH; adds value (XXX) on first line of file /etc/tor/torrc/

        # "basic" authenticated hidden server, set service name: HiddenServiceAuthorizeClient
        sed -i "1i HiddenServiceAuthorizeClient basic motioncamviewer" /etc/tor/torrc

        # forward hidden service port to local ssh: HiddenServicePort
        sed -i "1i HiddenServicePort ${PORT} 127.0.0.1:${PORT}" /etc/tor/torrc

        # hidden service directory contains services private key, address: HiddenServiceDir
        sed -i "1i HiddenServiceDir /var/lib/tor/motioncamviewer/" /etc/tor/torrc

        # restart tor to load new settings, wait
        echo "Tor restart. This will take some time..."
        systemctl stop tor
        sleep 5
        systemctl start tor
        sleep 10  
        
        # formated hidden service data output for user
        # get hidden service url, login from file, remove comment
        HIDDEN_SERVICE_COOKIE=$(cat /var/lib/tor/motioncamviewer/hostname | sed -Ee "s| # client:||") 

        # get hidden service uri from cookie, get string until first whitespace
        HIDDEN_SERVICE_HOST=$(echo ${HIDDEN_SERVICE_COOKIE} | sed -Ee 's| .*||')
        
        # set hidden service enabled in config
        sed -i "s|\"tor_HiddenService_enabled\": .*|\"tor_HiddenService_enabled\": true,|" "${CURRENT_DIR}/config.json"
    fi
    
    # ask for SSL setup
    SSLSETUP=""
    while [ "$SSLSETUP" != "y" -a "$SSLSETUP" != "n" ]; do
        read -p "setup SSL? [y/n]: " SSLSETUP
    done
    if [ "$SSLSETUP" == "y" ]; then
        
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
        
        # generate strong certificate, 10 years valid (-days 3650), re ask on error
        echo "openssl will no re-ask for pass phrase if validation fails. THIS WILL TAKE TIME"
        OPENSSL_REASK=1;
        while [ "$OPENSSL_REASK" == "1" ]; do
            openssl req -x509 -newkey rsa:4096 -keyout ${CURRENT_DIR}/key.pem -out ${CURRENT_DIR}/cert.pem -days 3650
            if [ $? -eq 0 ]; then
                OPENSSL_REASK=0
            fi
        done
        
        # set certificate and private key in motion cam viewer config
        sed -i "s|\"ssl_privateKeyPath\": \".*|\"ssl_privateKeyPath\": \"${CURRENT_DIR}/key.pem\",|" "${CURRENT_DIR}/config.json"
        sed -i "s|\"ssl_certificatePath\": \".*|\"ssl_certificatePath\": \"${CURRENT_DIR}/cert.pem\",|" "${CURRENT_DIR}/config.json"
        
        # ask for SSL port if 2 interfaces (tor@localhost, https@X) enabled
        if [ "$TORSETUP" == "y" ]; then
            
            # ask for port until port is integer
            PORT_SSL=""
            while [ -z "$PORT_SSL" ]; do
                read -p "HTTPS server port [integer / 0 for default: 8025]: " PORT_SSL
                case $PORT_SSL in
                    ''|*[!0-9]*) PORT_SSL="" ;;
                    *) ;;
                esac
            done
            
            # set default SSL HTTP port "8025" if 0
            if [ "$PORT_SSL" == "0" ]; then
                PORT_SSL=8025
            fi
            
            # set ssl port in config
            sed -i "s|\"ssl_port\": [0-9]+|\"ssl_port\": ${PORT_SSL},|" "${CURRENT_DIR}/config.json"
        
        # ask to disable default HTTP if HTTPS and no tor setup
        else
            DISABLEHTTP=""
            while [ "$DISABLEHTTP" != "y" -a "$DISABLEHTTP" != "n" ]; do
                read -p "disable HTTP (HTTPS only)? [n/y]: " DISABLEHTTP
            done
            if [ "$DISABLEHTTP" = "y" ]; then
                
                # set port in config to 0 -> disable HTTP without SSL
                sed -i "s|\"port\": [0-9]+|\"port\": 0,|" "${CURRENT_DIR}/config.json"
            fi
            
        fi
    fi
    
    # ask for network interface, set local as default if empty
    echo "Which IP should be listened? (localhost: 127.0.0.1, local: (use your local network IP), all IPs: 0.0.0.0)"
    read -p "enter your listening IP (leave empty for default: local network IP): " LISTENIP
    sed -i "s|\"networkInterface\": \".*|\"networkInterface\": \"${LISTENIP}\",|" "${CURRENT_DIR}/config.json"

    # create unix user for service 
    useradd -r motioncamviewer

    # add user motioncamviewer to motion group
    adduser motioncamviewer motion
    
    # make image exist, set user, dir read / write able by group. motion default is: /var/lib/motion
    mkdir -p /var/lib/motion
    chown -R motion:motion /var/lib/motion
    chmod -R 775 /var/lib/motion

    # create log file
    touch /var/log/motioncamviewer.log
    chown motioncamviewer:motioncamviewer /var/log/motioncamviewer.log
    
    echo "Install node.js modules, generate random values. This will take some time..."

    # install node.js modules
    cd "${CURRENT_DIR}"
    npm install
    
    # generate random secret for salt & co, set in config
    SECRET=$(cat /dev/urandom | tr -cd 'a-f0-9' | head -c 32)
    sed -i "s|\"secret\": \".*|\"secret\": \"${SECRET}\",|" "${CURRENT_DIR}/config.json"
    
    # ask for cam viewer password, set random if empty, set in config.json
    PASSWORD=$(./set_password.sh);
    
    # ask for replace existing motion configuration
    REPLACEMONTIONCONFIG=""
    while [ "$REPLACEMONTIONCONFIG" != "y" -a "$REPLACEMONTIONCONFIG" != "n" ]; do
        read -p "replace motion configuration? [y/n] (use y, we backup the old one): " REPLACEMONTIONCONFIG
    done
    if [ $REPLACEMONTIONCONFIG = "y" ]; then

        ## enable motion via system
        systemctl enable motion
    
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
    cat "${CURRENT_DIR}/etc/systemd/system/motioncamviewer.service" | sed -e "s|##path##|${WHICHNODE}|g" | sed -e "s|##argument##|${CURRENT_DIR}\/app.js|g" > "/etc/systemd/system/motioncamviewer.service" 

    # enable & start motion cam viewer server
    echo "start motioncamviewer..."
    systemctl enable motioncamviewer
    systemctl start motioncamviewer    

    # system, file changes output
    echo "---"
    echo "system user without shell created: motioncamviewer"
    echo "user: motioncamviewer added to group: motion"
    echo "files & folders changed:"
    echo "${CURRENT_DIR}/node_modules/"
    echo "/etc/motion.conf"
    echo "/etc/motion.conf_MCVIEWER_BAK"
    echo "/etc/systemd/system/motioncamviewer.service"
    echo "/var/log/motioncamviewer.log"
    echo "/etc/motion.conf"
    echo "${CURRENT_DIR}/config.json"
    
    # show files created for SSL setup
    if [ "$SSLSETUP" = "y" ]; then
        echo "${CURRENT_DIR}/key.pem"
        echo "${CURRENT_DIR}/cert.pem"
    fi
    
    # show hidden service data
    if [ "$TORSETUP" = "y" ]; then
        echo "/etc/tor/torrc" # changed for setup
        echo "---"
        echo "tor auth cookie; add next line to your local tor configuration at /etc/tor/torrc:"
        echo "HidServAuth ${HIDDEN_SERVICE_COOKIE}"
        echo "tor hidden service onion url:"
        echo "${HIDDEN_SERVICE_HOST}"
        echo "tor hidden service dir:"
        echo "/var/lib/tor/motioncamviewer/"
        echo "---"
    else
        echo "---"
    fi
    
    # get current local ip for user output if not set
    if [ -z "${LISTENIP}" ]; then 
        LISTENIP=$(hostname -I | awk '{ print $1 }')
    fi
    
    # show HTTP application settings
    echo "login password: ${PASSWORD}"   
    if [ "$DISABLEHTTP" != "y" ]; then
        echo "listen to IP / port: http://${LISTENIP}:${PORT}";
    fi
    if [ "$SSLSETUP" == "y" ]; then
        echo "listen to IP / port: https://${LISTENIP}:${PORT_SSL}";
    fi
    echo "---"
    echo "motion cam viewer setup complete"
}

# ask for setup
echo "motion cam viewer setup for Debian based systems"
echo "camera with motion support must be installed before running this setup"
echo "root permissions required for setup (we ask for root in next step)"
DOSETUP=""
while [ "$DOSETUP" != "y" -a "$DOSETUP" != "n" ]; do
    read -p "continue setup? [y/n]: " DOSETUP
done
if [ "$DOSETUP" == "n" ]; then
    exit
fi

# check root, ask for root
WHOAMI=$(whoami)
if [ "$WHOAMI" != "root" ]; then
    su -c "$(declare -f setup); setup"    
else
    setup
fi


