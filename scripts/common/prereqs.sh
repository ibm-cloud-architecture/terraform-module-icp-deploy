#!/bin/bash
#This script updates hosts with required prereqs
#if [ $# -lt 1 ]; then
#  echo "Usage $0 <hostname>"
#  exit 1
#fi

#HOSTNAME=$1

LOGFILE=/tmp/prereqs.log
exec > $LOGFILE 2>&1

#Find Linux Distro
if grep -q -i ubuntu /etc/*release
  then
    OSLEVEL=ubuntu
  else
    OSLEVEL=other
fi
echo "Operating System is $OSLEVEL"

ubuntu_install(){
  packages_to_check="\
python-yaml \
thin-provisioning-tools \
lvm2"
  sudo sysctl -w vm.max_map_count=262144
  packages_to_install=""

  for package in ${packages_to_check}; do
    if ! dpkg -l ${package} &> /dev/null; then
      packages_to_install="${packages_to_install} ${package}"
    fi
  done

  if [ ! -z "${packages_to_install}" ]; then
    # attempt to install, probably won't work airgapped but we'll get an error immediately
    echo "Attempting to install: ${packages_to_install} ..."
    flock --timeout 60 --exclusive --close /var/lib/apt/lists/lock apt-get -y -o Dpkg::Options::="--force-confold" update
    while [ $? -ne 0 ]; do
      echo "Another process has f-locked /var/lib/apt/lists/lock" 1>&2
      sleep 10;
      flock --timeout 60 --exclusive --close /var/lib/apt/lists/lock apt-get -y -o Dpkg::Options::="--force-confold" update
    done

    flock --timeout 60 --exclusive --close /var/lib/dpkg/lock apt-get -y -o Dpkg::Options::="--force-confold" install ${packages_to_install}
    while [ $? -ne 0 ]; do
      echo "Another process has f-locked /var/lib/dpkg/lock" 1>&2
      sleep 10;
      flock --timeout 60 --exclusive --close /var/lib/dpkg/lock apt-get -y -o Dpkg::Options::="--force-confold" install ${packages_to_install}
    done
  fi
}

crlinux_install(){
  packages_to_check="\
PyYAML \
device-mapper \
libseccomp \
libtool-ltdl \
libcgroup \
iptables \
device-mapper-persistent-data \
lvm2"

  for package in ${packages_to_check}; do
    if ! rpm -q ${package} &> /dev/null; then
      packages_to_install="${packages_to_install} ${package}"
    fi
  done

  if [ ! -z "${packages_to_install}" ]; then
    # attempt to install, probably won't work airgapped but we'll get an error immediately
    echo "Attempting to install: ${packages_to_install} ..."
    sudo yum install -y ${packages_to_install}
  fi
}

if [ "$OSLEVEL" == "ubuntu" ]; then
  ubuntu_install
else
  crlinux_install
fi

echo "Complete.."
exit 0
