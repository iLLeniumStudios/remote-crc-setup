# remote-crc-setup

Allows you to setup a remote crc cluster exposed at `https://console-openshift-console.apps.<local-ip>.nip.io`

## Minimum requirements

| Resource              | Required         |
|-----------------------|------------------|
| CPU                   | 4 Core / Threads |
| RAM                   | 16GB             |
| Disk                  | 80GB             |
| OS                    | Rocky Linux 9    |
| Nested Virtualization | Enabled          |

## Pre-requisites

### Create a new user and login

- SSH as root

```bash
ssh root@<ip>
```

- Create the `crc` user

```bash
adduser crc
echo password | passwd crc --stdin
echo "crc ALL=(root) NOPASSWD:ALL" | tee -a /etc/sudoers.d/crc
chmod 0440 /etc/sudoers.d/crc
```

## Installation

- SSH as `crc` user created above (Do no use su -)

- Run the installation script
```bash
curl https://raw.githubusercontent.com/iLLeniumStudios/remote-crc-setup/main/install.sh | bash
```

- Wait for the script to finish the installation. You should see something like this once everything is done:

```bash
Console available here: https://console-openshift-console.apps.10.0.6.188.nip.io
Console Login Credentials:
USERNAME: kubeadmin PASSWORD: vAFof-LsHb3-S2dv6-Yj3mF

CLI Login Command: oc login -u kubeadmin -p vAFof-LsHb3-S2dv6-Yj3mF https://api.10.0.6.188.nip.io:6443
```

> Note that the script enables cluster monitoring components as well. If you don't need those, you can disable them from the `install.sh` script
