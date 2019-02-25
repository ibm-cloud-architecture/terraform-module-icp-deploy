#!/bin/bash
LOGFILE=/tmp/loadimage.log
exec 3>&1
exec > >(tee -a ${LOGFILE} >/dev/null) 2> >(tee -a ${LOGFILE} >&3)

echo "Got the parameters $@"
# Defaults
source /tmp/icp-bootmaster-scripts/functions.sh
sourcedir=/opt/ibm/cluster/images
declare -a locations

# Parse options
while getopts ":l:i:s:u:p:" opt; do
  case $opt in
    l)
      locations+=( ${OPTARG} )
      ;;
    u)
      username=${OPTARG}
      ;;
    p)
      password=${OPTARG}
      ;;
    i)
      image=${OPTARG}
      ;;
    s)
      echo "Will overwrite default sourcedir to ${OPTARG}"
      sourcedir=${OPTARG}
      ;;
    \?)
      echo "Invalid option : -$OPTARG in commmand $0 $*" >&2
      exit 1
      ;;
    :)
      echo "Missing option argument for -$OPTARG in command $0 $*" >&2
      exit 1
      ;;
  esac
done

# Figure out the version
# This will populate $org $repo and $tag
parse_icpversion ${image}
echo "registry=${registry:-not specified} org=$org repo=$repo tag=$tag"

# Make sure sourcedir exists, in case we need to donwload some archives
sudo mkdir -p ${sourcedir}
sudo chown $(whoami):$(whoami) ${sourcedir}

if [[ ! -z ${image} ]]; then
  # Figure out the version
  # This will populate $org $repo and $tag
  parse_icpversion ${image}
  echo "registry=${registry:-not specified} org=$org repo=$repo tag=$tag"
fi

# Allow downloading multiple tarballs,
# which is required in multi-arch deployments
for image_location in ${locations[@]} ; do

  # Detect which protocol to use
  if [[ "${image_location:0:4}" == "http" ]]; then
    # Extract filename from URL if possible
    if [[ "${image_location: -2}" == "gz" ]]; then
      # Assume a sensible filename can be extracted from URL
      filename=$(basename ${image_location})
    else
      # TODO We might be able to use some magic to extract actual filename.
      # For now, hard-code for x86
      echo "Not able to determine filename from URL ${image_location}" >&2
      filename="ibm-cloud-private-x86_64${tag}.tar.gz"
      echo "Set it to ${filename}" >&2

    fi

    # Download the file using auth if provided
    echo "Downloading ${image_location}" >&2
    echo "This can take a very long time" >&2
    wget -nv --continue ${username:+--user} ${username} ${password:+--password} ${password} \
     -O ${sourcedir}/${filename} "${image_location}"

    if [[ $? -gt 0 ]]; then
      echo "Error downloading ${image_location}" >&2
      exit 1
    fi

    # Set the image file name if we're on the same platform
    if [[ ${filename} =~ .*$(uname -m).* ]]; then
      echo "Setting image_file to ${sourcedir}/${filename}"
      image_file="${sourcedir}/${filename}"
    fi
  else
    # Assume NFS since this is the only other supported protocol
    # Separate out the filename and path
    nfs_mount=$(dirname ${image_location})
    image_file="${sourcedir}/$(basename ${image_location})"
    mkdir -p ${sourcedir}
    # Mount
    sudo mount.nfs $nfs_mount $sourcedir

  fi
done

# Load the offline tarball to get the inception image
if [[ -s "$image_file" ]]
then
  echo "Loading image file ${image_file}. This can take a very long time" >&2
  # If we have pv installed, we can use that for improved reporting
  if which pv >>/dev/null; then
    pv --interval 30 ${image_file} | tar zxf - -O | sudo docker load >&2
  else
    tar xf ${image_file} -O | sudo docker load >&2
  fi
else
  # If we don't have an image locally we'll pull from docker registry
  if [[ -z $(docker images -q ${registry}${registry:+/}${org}/${repo}:${tag}) ]]; then
    # If this is a private registry we may need to log in
    if [[ ! -z "$username" ]]; then
      docker login -u ${username} -p ${password} ${registry}
    fi
    # ${registry}${registry:+/} adds <registry>/ only if registry is specified
    docker pull ${registry}${registry:+/}${org}/${repo}:${tag}
  fi
fi
