#!/bin/bash
set -eux

# see https://github.com/moby/moby/releases
# renovate: datasource=github-releases depName=moby/moby
docker_version='28.1.1'

# prevent apt-get et al from asking questions.
# NB even with this, you'll still get some warnings that you can ignore:
#     dpkg-preconfigure: unable to re-open stdin: No such file or directory
export DEBIAN_FRONTEND=noninteractive

# make sure the package index cache is up-to-date before installing anything.
apt-get update

# install docker.
# see https://docs.docker.com/engine/installation/linux/docker-ce/ubuntu/#install-using-the-repository
apt-get install -y apt-transport-https software-properties-common
wget -qO- https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/download.docker.com.gpg
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/download.docker.com.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" >/etc/apt/sources.list.d/docker.list
apt-get update
apt-cache madison docker-ce | head -5
docker_package_version="$(apt-cache madison docker-ce | awk "/$docker_version/{print \$3}")"
apt-get install -y "docker-ce=$docker_package_version" "docker-ce-cli=$docker_package_version" containerd.io

# configure it.
systemctl stop docker
install -m 750 -d /etc/docker
cat >/etc/docker/daemon.json <<'EOF'
{
    "experimental": false,
    "debug": false,
    "features": {
        "buildkit": true
    },
    "log-driver": "journald",
    "labels": [
        "os=linux"
    ],
    "hosts": [
        "unix://"
    ]
}
EOF
# start docker without any command line flags as its entirely configured from daemon.json.
install -d /etc/systemd/system/docker.service.d
cat >/etc/systemd/system/docker.service.d/override.conf <<'EOF'
[Service]
ExecStart=
ExecStart=/usr/bin/dockerd
EOF
systemctl daemon-reload
systemctl start docker

# kick the tires.
ctr version
docker version
docker info
docker network ls
ip link
bridge link
#docker run --rm hello-world
#docker run --rm alpine ping -c1 8.8.8.8
#docker run --rm debian:10 ping -c1 8.8.8.8
#docker run --rm debian:10-slim cat /etc/os-release
#docker run --rm ubuntu:22.04 cat /etc/os-release
