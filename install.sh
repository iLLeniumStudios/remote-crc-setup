#!/bin/bash

function wait_for_clusteroperators() {
  while true; do
    local clusteroperators_status
    clusteroperators_status=$(oc get clusteroperators)
    if [[ $? != 0 ]]; then
      echo "API Server not reachable"
      sleep 2s
    fi
    echo "$clusteroperators_status" | tail -n +2 | awk '{print $3}' | grep False &>/dev/null
    local ret1=$?
    echo "$clusteroperators_status" | tail -n +2 | awk '{print $4}' | grep True &>/dev/null
    local ret2=$?
    echo "$clusteroperators_status" | tail -n +2 | awk '{print $5}' | grep True &>/dev/null
    local ret3=$?
    if [[ $ret1 != 0 ]] && [[ $ret2 != 0 ]] && [[ $ret3 != 0 ]]; then
      break
    fi
    echo "Waiting for the clusteroperators to be ready"
    sleep 10s
  done
}

# Install packages

sudo dnf install jq wget tar -y

# Disable firewalld
sudo systemctl stop firewalld
sudo systemctl disable firewalld
sudo systemctl mask --now firewalld

# Download crc
CRC_VERSION=latest
wget https://developers.redhat.com/content-gateway/rest/mirror/pub/openshift-v4/clients/crc/latest/${CRC_VERSION}/crc-linux-amd64.tar.xz
tar -xvf crc-linux-amd64.tar.xz
sudo mv crc-linux-${CRC_VERSION}-amd64/crc /usr/local/bin/
sudo chmod +x /usr/local/bin/crc
rm -rf crc-linux*

# Configure crc
crc config set memory 14336
crc config set enable-cluster-monitoring true

crc setup --log-level debug

crc start --log-level debug --pull-secret-file "${HOME}/pull-secret.json"

eval $(crc oc-env)

# Setup haproxy

sudo dnf install haproxy /usr/sbin/semanage -y
sudo semanage port -a -t http_port_t -p tcp 6443
sudo cp /etc/haproxy/haproxy.cfg{,.bak}

CRC_IP=$(crc ip)
sudo tee /etc/haproxy/haproxy.cfg &>/dev/null <<EOF
global
    log /dev/log local0

defaults
    balance roundrobin
    log global
    maxconn 100
    mode tcp
    timeout connect 5s
    timeout client 500s
    timeout server 500s

listen apps
    bind 0.0.0.0:80
    server crcvm $CRC_IP:80 check

listen apps_ssl
    bind 0.0.0.0:443
    server crcvm $CRC_IP:443 check

listen api
    bind 0.0.0.0:6443
    server crcvm $CRC_IP:6443 check
EOF

sudo systemctl enable haproxy --now
sudo systemctl start haproxy

# Change crc base domain

MACHINE_IP=$(ip addr show | awk '/inet / && $2 !~ /^127\.0\.0\.1/ {gsub(/\/.*/, "", $2); print $2; exit}')

BASE_DOMAIN="${MACHINE_IP}.nip.io"
openssl req -newkey rsa:2048 -new -nodes -x509 -days 3650 -keyout nip.key -out nip.crt -subj "/CN=${BASE_DOMAIN}" -addext "subjectAltName=DNS:apps.${BASE_DOMAIN},DNS:*.apps.${BASE_DOMAIN},DNS:api.${BASE_DOMAIN}"
oc create secret tls nip-secret --cert=nip.crt --key=nip.key -n openshift-config

oc patch -p "{\"spec\": {\"host\": \"default-route-openshift-image-registry.$BASE_DOMAIN\"}}" route default-route -n openshift-image-registry --type=merge

cat <<EOF > ingress-patch.yaml
spec:
  appsDomain: apps.${BASE_DOMAIN}
  componentRoutes:
  - hostname: console-openshift-console.apps.${BASE_DOMAIN}
    name: console
    namespace: openshift-console
    servingCertKeyPairSecret:
      name: nip-secret
  - hostname: oauth-openshift.apps.${BASE_DOMAIN}
    name: oauth-openshift
    namespace: openshift-authentication
    servingCertKeyPairSecret:
      name: nip-secret
EOF
oc patch ingresses.config.openshift.io cluster --type=merge --patch-file=ingress-patch.yaml

oc patch apiserver cluster --type=merge -p "{\"spec\":{\"servingCerts\": {\"namedCertificates\":[{\"names\":[\"api.${BASE_DOMAIN}\"],\"servingCertificate\": {\"name\": \"nip-secret\"}}]}}}"

sleep 10s

wait_for_clusteroperators

USERNAME=$(crc console -ojson | jq -r '.clusterConfig.adminCredentials.username')
PASSWORD=$(crc console -ojson | jq -r '.clusterConfig.adminCredentials.password')

echo ""

echo "The server is accessible via web console at:"
echo "  https://console-openshift-console.apps.${BASE_DOMAIN}"

echo ""

echo "Log in as administrator: "
echo "  USERNAME: ${USERNAME}"
echo "  PASSWORD: ${PASSWORD}"

echo ""



echo "Use the 'oc' command line interface:"
echo "  $ oc login -u ${USERNAME} -p ${PASSWORD} https://api.${BASE_DOMAIN}:6443"
