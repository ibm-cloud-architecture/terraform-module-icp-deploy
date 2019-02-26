#!/bin/bash
###############################
##
## This script will handle the installation of docker.
##
##
###############################
LOGFILE=/tmp/install-docker.log
exec 3>&1
exec > >(tee -a ${LOGFILE} >/dev/null) 2> >(tee -a ${LOGFILE} >&3)

echo "Script started with inputs $@"
source /tmp/icp-bootmaster-scripts/get-args.sh

sourcedir=/tmp/icp-docker

function rhel_docker_install {
  # Process for RedHat VMs
  echo "Update RedHat or CentOS with latest patches"

  # Add the Extra Repo from RedHat to be able to support extra tools that needed
  sudo subscription-manager repos --enable=rhel-7-server-extras-rpms
  sudo yum update -y

  # Installing nesscarry tools for ICP to work including Netstat for tracing
  sudo yum install -y net-tools yum-utils device-mapper-persistent-data lvm2

  # Register Docker Community Edition repo for CentOS and RedHat
  sudo yum-config-manager --add-repo  https://download.docker.com/linux/centos/docker-ce.repo
  sudo yum install -y ${docker_image}${docker_version}
  if [[ $? -gt 0 ]]; then
    if which tail &>> /dev/null; then
      tail -n 5 $LOGFILE >&2
    fi

    echo "Error installing ${docker_image}${docker_version}" >&2
    exit 1
  fi

  # Start Docker locally on the host
  sudo systemctl enable docker
  sudo systemctl start docker
}

function ubuntu_docker_install {
  # Process for Ubuntu VMs
  echo "Installing ${docker_version:-latest} docker from docker repository" >&2
  sudo apt-get -q update
  # Make sure preprequisites are installed
  sudo apt-get -y -q install \
    apt-transport-https \
    ca-certificates \
    curl \
    software-properties-common

  # Add docker gpg key
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -

  # Right now hard code adding x86 repo
  local arch=$(uname -m | sed -e 's/x86_64/amd64/g' -e 's/ppc64le/ppc64el/g')
  sudo add-apt-repository \
   "deb [arch=${arch}] https://download.docker.com/linux/ubuntu \
   $(lsb_release -cs) \
   stable"

  sudo apt-get -q update
  sudo apt-get -y -q install ${docker_image}${docker_version}
  if [[ $? -gt 0 ]]; then
    if which tail &>> /dev/null; then
      tail -n 5 $LOGFILE >&2
    fi

    echo "Error installing ${docker_image}${docker_version}" >&2
    exit 1
  fi
}

# Nothing to do here if we have docker already
if docker --version &>> /dev/null
then
  # Make sure the current user has permission to use docker
  /tmp/icp-common-scripts/docker-user.sh
  echo "Docker already installed. Exiting" >&2
  exit 0
fi

# Check if we're asked to install off-line or ICP provided docker bundle
if [[ -z ${docker_package_location} ]]
then
  echo "Not required to install ICP provided docker."
else
  echo "Starting installation of ${docker_package_location}"
  mkdir -p ${sourcedir}

  # Decide which protocol to use
  if [[ "${docker_package_location:0:3}" == "nfs" ]]
  then
    # Separate out the filename and path
    nfs_mount=$(dirname ${docker_package_location:4})
    package_file="${sourcedir}/$(basename ${docker_package_location})"
    # Mount
    sudo mount.nfs $nfs_mount $sourcedir
  elif [[ "${docker_package_location:0:4}" == "http" ]]
  then
    # Figure out what we should name the file
    filename="icp-docker.bin"
    mkdir -p ${sourcedir}
    curl -o ${sourcedir}/${filename} "${docker_package_location#http:}"
    package_file="${sourcedir}/${filename}"
  fi

  chmod a+x ${package_file}
  sudo ${package_file} --install

  # Make sure our user is added to the docker group if needed
  /tmp/icp-common-scripts/docker-user.sh

  echo "Install complete..."
  exit 0
fi

## At this stage we better attempt to install from repository
if grep -q -i ubuntu /etc/*release
  then
    OSLEVEL=ubuntu

elif grep -q -i 'red hat' /etc/*release
  then
    OSLEVEL=redhat

elif grep -q -i 'CentOS' /etc/*release
  then
    OSLEVEL=redhat
else
  OSLEVEL=other
fi
echo "Operating System is $OSLEVEL"

if [[ "${OSLEVEL}" == "ubuntu" ]]
  then
    if [ "${docker_version}" == "latest" ];
    then
      docker_version=""
    else
      docker_version="=${docker_version}*"
    fi

    ubuntu_docker_install

    # Make sure our user is added to the docker group if needed
    /tmp/icp-common-scripts/docker-user.sh
    exit 0

elif [[ "${OSLEVEL}" == "redhat" ]]
  then
    if [ "${docker_version}" == "latest" ]
    then
      docker_version=""
    else
      docker_version="-${docker_version}*"
    fi
    rhel_docker_install

    # Make sure our user is added to the docker group if needed
    /tmp/icp-common-scripts/docker-user.sh
    exit 0

else
  echo "Only Ubuntu supported for repository install for now..." >&2
  echo "Please install docker manually, or with ICP provided docker bundle" >&2
  exit 1
fi
