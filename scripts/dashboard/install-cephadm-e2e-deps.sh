#!/usr/bin/env bash

set -ex

on_error() {
    if [ "$1" != "0" ]; then
        printf "\n\nERROR $1 thrown on line $2\n\n"
        printf "\n\nCollecting info...\n\n"
        sudo journalctl --since "10 min ago" --no-tail --no-pager -x
        printf "\n\nERROR: displaying containers' logs:\n\n"
        docker ps -aq | xargs docker logs
        printf "\n\nTEST FAILED.\n\n"
    fi
}

trap 'on_error $? $LINENO' ERR

sudo apt -y install libvirt-daemon-system libvirt-daemon-driver-qemu qemu-kvm libvirt-clients

sudo usermod -aG libvirt $(id -un)
newgrp libvirt  # Avoid having to log out and log in for group addition to take effect.
sudo systemctl enable --now libvirtd

if [[ $(command -v docker) == '' ]]; then
    # Set up docker official repo and install docker.
    sudo apt update -y
    sudo apt install \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo \
        "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
        $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt update -y
    sudo apt install -y docker-ce docker-ce-cli containerd.io
fi
sudo groupadd docker || true
sudo usermod -aG docker $(id -un)
sudo systemctl start docker
sudo chgrp "$(id -un)" /var/run/docker.sock

docker info
docker container prune -f

KCLI_CONFIG_DIR="${HOME}/.kcli"
mkdir -p ${KCLI_CONFIG_DIR}
if [[ ! -f "${KCLI_CONFIG_DIR}/id_rsa" ]]; then
    ssh-keygen -t rsa -q -f "${KCLI_CONFIG_DIR}/id_rsa" -N ""
fi

: ${KCLI_CONTAINER_IMAGE:='quay.io/karmab/kcli:2543a61'}

docker pull ${KCLI_CONTAINER_IMAGE}

echo "#!/usr/bin/env bash

docker run --net host --security-opt label=disable \
    -v ${KCLI_CONFIG_DIR}:/root/.kcli \
    -v ${PWD}:/workdir \
    -v /var/lib/libvirt/images:/var/lib/libvirt/images \
    -v /var/run/libvirt:/var/run/libvirt \
    -v /var/tmp:/ignitiondir \
    ${KCLI_CONTAINER_IMAGE} \""'${@}'"\"
" | sudo tee /usr/local/bin/kcli
sudo chmod +x /usr/local/bin/kcli

# Install required deps.
sudo apt update -y
sudo apt install -y nodejs npm openssh-server

# KCLI cleanup function can be found here: https://github.com/ceph/ceph/blob/master/src/pybind/mgr/dashboard/ci/cephadm/start-cluster.sh
sudo mkdir -p /var/lib/libvirt/images/ceph-dashboard
kcli create pool -p /var/lib/libvirt/images/ceph-dashboard ceph-dashboard
kcli create network -c 192.168.100.0/24 ceph-dashboard
