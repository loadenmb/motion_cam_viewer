#! /bin/bash

set_password() {

    # get current script path, resolve $SOURCE until the file is no longer a symlink
    SOURCE=${BASH_SOURCE[0]}
    while [ -h "$SOURCE" ]; do
        DIR="$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)"
        SOURCE="$(readlink "$SOURCE")"
        [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
    done
    CURRENT_DIR="$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)"

    # ask for cam viewer password in config.json, set random if empty
    PASSWORD=""
    ISOK=1
    while [ "$ISOK" == 1 ]; do
        >&2 echo "enter your motion cam viewer HTTP password (blank for random): " # stderr ouput, couse stdout is used as return
        >&2 echo "password rules: length: 8 - 255. must include: 1x A-z and 1x 0-9 and 1x #?!@$%^&*-"
        read PASSWORD
        ISOK=$(./password.js "$PASSWORD")
    done
    
    # split password return value by " " so its: *hash* *pass*
    readarray -d " " -t strarr <<< "$ISOK"     
    
    # set hash in config
    sed -i "s/\"password\": \".*/\"password\": \"${strarr[0]}\",/" "${CURRENT_DIR}/config.json"
    
    # pass password to script which called this
    echo ${strarr[1]}
}

# check root, ask for root
WHOAMI=$(whoami)
if [ $WHOAMI != "root" ]; then
    echo "enter root password:" # root permissions should already fetched if called from other script because of trouble with ouput and return value
    su -c "$(declare -f set_password); set_password"    
else
    set_password
fi
