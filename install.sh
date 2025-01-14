#!/usr/bin/bash

#SERVER_NAME=''
#SERVER_CERT="/etc/overplus/$SERVER_NAME.crt"
#SERVER_KEY="/etc/overplus/$SERVER_NAME.crt"
VERSION="v1.0.3"
blue(){
    echo -e "\033[34m\033[01m$1\033[0m"
}
green(){
    echo -e "\033[32m\033[01m$1\033[0m"
}
red(){
    echo -e "\033[31m\033[01m$1\033[0m"
}

if [[ -f /etc/redhat-release ]]; then
    release="centos"
    systemPackage="yum"
    systempwd="/usr/lib/systemd/system/"
    elif cat /etc/issue | grep -Eqi "debian"; then
    release="debian"
    systemPackage="apt-get"
    systempwd="/lib/systemd/system/"
    elif cat /etc/issue | grep -Eqi "ubuntu"; then
    release="ubuntu"
    systemPackage="apt-get"
    systempwd="/lib/systemd/system/"
    elif cat /etc/issue | grep -Eqi "centos|red hat|redhat"; then
    release="centos"
    systemPackage="yum"
    systempwd="/usr/lib/systemd/system/"
    elif cat /proc/version | grep -Eqi "debian"; then
    release="debian"
    systemPackage="apt-get"
    systempwd="/lib/systemd/system/"
    elif cat /proc/version | grep -Eqi "ubuntu"; then
    release="ubuntu"
    systemPackage="apt-get"
    systempwd="/lib/systemd/system/"
    elif cat /proc/version | grep -Eqi "centos|red hat|redhat"; then
    release="centos"
    systemPackage="yum"
    systempwd="/usr/lib/systemd/system/"
fi


function generate_certifiate(){
    # Install the latest version of easy-rsa from source, if not already installed.
    if [ ! -d "/etc/overplus/easy-rsa" ]; then
        local version="3.1.1"
        wget -O ~/easy-rsa.tgz https://github.com/OpenVPN/easy-rsa/releases/download/v${version}/EasyRSA-${version}.tgz
        mkdir -p /etc/overplus/easy-rsa
        tar xzf ~/easy-rsa.tgz --strip-components=1 --directory /etc/overplus/easy-rsa
        rm -f ~/easy-rsa.tgz
        cd /etc/overplus/easy-rsa/ || return

        # Generate a random, alphanumeric identifier of 16 characters for CN and one for server name
        SERVER_CN="cn_$(head /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)"
        echo "$SERVER_CN" >SERVER_CN_GENERATED
        SERVER_NAME="server_$(head /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)"
        echo "$SERVER_NAME" >SERVER_NAME_GENERATED
        # Create the PKI, set up the CA, the DH params and the server certificate
        ./easyrsa --batch init-pki
        ./easyrsa --batch build-ca nopass
        ./easyrsa --batch --days=3650 build-server-full "$SERVER_NAME" nopass
        ./easyrsa --batch --days=3650 gen-crl
    else
        # If easy-rsa is already installed, grab the generated SERVER_NAME
        # for client configs
        cd /etc/overplus/easy-rsa/ || return
        SERVER_NAME=$(cat SERVER_NAME_GENERATED)
    fi
    # Move all the generated files
    cp pki/ca.crt pki/private/ca.key "pki/issued/$SERVER_NAME.crt" "pki/private/$SERVER_NAME.key" /etc/overplus/easy-rsa/pki/crl.pem /etc/overplus
    # Make cert revocation list readable for non-root
    chmod 644 /etc/overplus/crl.pem
}
function install_overplus(){
    $systemPackage -y install openssl
    $systemPackage -y install  xz-utils  wget unzip zip curl tar
    Port443=`netstat -tlpn | awk -F '[: ]+' '$1=="tcp"{print $5}' | grep -w 443`
    if [ -n "$Port443" ]; then
        process443=`netstat -tlpn | awk -F '[: ]+' '$5=="443"{print $9}'`
        red "============================================================="
        red "检测到443端口被占用，占用进程为：${process443}，本次安装结束"
        red "============================================================="
        exit 1
    fi
    
    SOFTWARE_PACKAGE=https://github.com/xyanrch/overplus/releases/download/${VERSION}/LinuxRelease.zip
    #PORT_CHOICE=${PORT_CHOICE:-1}
    #PORT="443"
    
    
    green "======================="
    
    blue "please input overplus user password:"
    green "======================="
    read USER_PASSWORD
    
    blue "What port do you want Overplus to listen to?"
    echo "   1) Default(recommend): 443"
    echo "   2) Custom"
    until [[ $PORT_CHOICE =~ ^[1-2]$ ]]; do
        read -rp "Port choice [1-2]: " -e -i 1 PORT_CHOICE
    done
    case $PORT_CHOICE in
        1)
            PORT="443"
        ;;
        2)
            until [[ $PORT =~ ^[0-9]+$ ]] && [ "$PORT" -ge 1 ] && [ "$PORT" -le 65535 ]; do
                read -rp "Custom port [1-65535]: " -e -i 1194 PORT
            done
        ;;
        3)
    esac
    generate_certifiate
    cd
    blue "download overplus package ..."
    wget $SOFTWARE_PACKAGE
    unzip  LinuxRelease.zip >/dev/null 2>&1
    cd LinuxRelease
    tar -xvf overplus-linux-amd64.tar.xz >/dev/null 2>&1
    
    cp overplus/overplus /usr/bin/overplus
    cp overplus/ConfigTemplate/server.json /etc/overplus/server.json
    #cp /home/xx/overplus/ConfigTemplate/server.json /etc/overplus/server.json
    
    NAME=$(cat /etc/overplus/easy-rsa/SERVER_NAME_GENERATED)
    SERVER_CERT="/etc/overplus/${NAME}.crt"
    SERVER_KEY="/etc/overplus/${NAME}.key"
    sed -i "s/VAR_PORT/$PORT/" /etc/overplus/server.json
    sed -i "s/VAR_PASSWORD/$USER_PASSWORD/" /etc/overplus/server.json
    
    sed -i "s~VAR_SERVER_CERT~${SERVER_CERT}~" /etc/overplus/server.json
    sed -i "s~VAR_SERVER_KEY~$SERVER_KEY~" /etc/overplus/server.json
    
    # mkdir -p /var/overplus
    cp overplus/ConfigTemplate/overplus.service /etc/systemd/system/overplus.service
    
    cd
    if [ -f LinuxRelease.zip ]; then
        rm -rf LinuxRelease.zip
    fi
    if [ -d './LinuxRelease' ]; then
        rm -rf LinuxRelease
    fi
    
    chmod 664 /etc/systemd/system/overplus.service
    systemctl daemon-reload
    systemctl start overplus.service
    systemctl enable overplus.service
    
    green " ===================================="
    green "Overplus has sucessfully installed"
    green "Please run \"systemctl status overplus.service\" to check service status"
    green " ===================================="
    green "Your sever config is located :/etc/overplus/server.json"
    cat /etc/overplus/server.json
    
    
    
}
function remove_overplus(){
    systemctl stop overplus
    systemctl disable overplus
    if [ -d /etc/overplus ]; then
        rm -rf /etc/overplus
    fi
    if [ -f /usr/bin/overplus ]; then
        rm -rf /usr/bin/overplus
    fi
    if [ -f /etc/systemd/system/overplus.service ]; then
        rm -rf /etc/systemd/system/overplus.service
    fi
    
}

start_menu(){
    clear
    green " ===================================="
    green "  Welcome to the overplus installer!      "
    
    green " ======================================="
    echo
    green " 1. Install overplus"
    red " 2. Remove overplus"
    
    blue " 0. Exit"
    echo
    read -p "Please input number:" num
    case "$num" in
        1)
            install_overplus
        ;;
        2)
            remove_overplus
        ;;
        0)
            exit 1
        ;;
        *)
            clear
            red "Please input correct number"
            sleep 1s
            start_menu
        ;;
    esac
}

start_menu
