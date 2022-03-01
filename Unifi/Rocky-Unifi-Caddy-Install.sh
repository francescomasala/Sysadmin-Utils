#!/bin/bash

function AmIRoot {
    if [[$EUID -ne 0 ]]; then
        echo "[!] Please start this script with root permission"
        exit
    fi
}

function CaddyInstall {
    echo "[!] Installing caddy"
    dnf install -y 'dnf-command(copr)'
    dnf copr enable -y @caddy/caddy
    dnf install -y caddy
}

function CaddyConfig {
cat << EOF | sudo tee /etc/caddy/Caddyfile
# UniFi Docker Caddyfile Conf.
# Admin control panel
unifi.$DOMAIN {
        reverse_proxy 10.0.0.1:8443 {
                transport http {
                        tls
                        tls_insecure_skip_verify
                }
        }
}
# Device configuration proxy
unifi.$DOMAIN:8080 {
        reverse_proxy 10.0.0.1:8080 {
                transport http
        }
}
# UniFi guest portal (https)
unifi.$DOMAIN:8843 {
        reverse_proxy 10.0.0.1:8843 {
                transport http {
                        tls
                        tls_insecure_skip_verify
                }
        }
}
# UniFi guest portal (redir to https)
unifi.$DOMAIN:8080 {
    redir https://unifi.$DOMAIN:8843
}
EOF
}

function CaddyEnable {
    echo "[!] Enabling Caddy"
    systemctl enable --now caddy
}

function SetFirewall {
    firewall-cmd --permanent --add-port=80/tcp    # Caddy Proxy for http
    firewall-cmd --permanent --add-port=443/tcp   # Caddy Proxy for https
    firewall-cmd --permanent --add-port=3478/udp  # Unifi STUN
    firewall-cmd --permanent --add-port=6789/tcp  # Mobile throughput test
    firewall-cmd --permanent --add-port=8080/tcp  # Caddy Proxy for device comms
    firewall-cmd --permanent --add-port=8843/tcp  # Caddy Proxy for Guest Portal
    firewall-cmd --permanent --add-port=10001/udp # AP Discovery
    firewall-cmd --reload
}

function DockerInstall {
    echo "[!] Installing Docker"
    dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo
    dnf update -y
    dnf install -y docker-ce docker-ce-cli containerd.io
}

function DockerCreateNet {
    docker network create --subnet=10.0.0.0/24 --gateway=10.0.0.254 unifi-net
}

function DockerCreateDisk {
    docker volume create unifi-disk
}

function DockerEnable {
    echo "[!] Enabling Docker"
    systemctl enable --now docker
}

function UnifiPull {
    docker pull linuxserver/unifi-controller:7.0.23
}

function UnifiInstall {
    docker run -d --name=Unifi -net unifi-net --ip 10.0.0.1 -v unifi-disk:/config -e PUID=1000 -e PGID=1000 -p 3478:3478/udp -p 10001:10001/udp -p 8880:8880 -p 6789:6789 -p 5514:5514/udp linuxserver/unifi-controller:7.0.23
}

AmIRoot
CaddyInstall
CaddyConfig
SetFirewall
DockerInstall
DockerEnable
UnifiPull
DockerCreateNet
DockerCreateDisk
UnifiInstall
CaddyEnable
