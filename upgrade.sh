#!/bin/bash
set -euxo pipefail

# wait for cloud-init to finish.
if [ "$(cloud-init status | perl -ne '/^status: (.+)/ && print $1')" != 'disabled' ]; then
    cloud-init status --long --wait
fi

# configure apt for non-interactive mode.
export DEBIAN_FRONTEND=noninteractive

# disable unattended upgrades.
# NB it interferes with our automation with errors alike:
#       E: Could not get lock /var/lib/dpkg/lock-frontend. It is held by process 17599 (unattended-upgr)
#       E: Unable to acquire the dpkg frontend lock (/var/lib/dpkg/lock-frontend), is another process using it?
apt-get remove -y --purge unattended-upgrades

# upgrade.
apt-get update
apt-get dist-upgrade -y
