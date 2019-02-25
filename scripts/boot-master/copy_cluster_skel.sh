#!/bin/bash
LOGFILE=/tmp/copyclusterskel.log
target="/opt/ibm"
exec 3>&1
exec > >(tee -a ${LOGFILE} >/dev/null) 2> >(tee -a ${LOGFILE} >&3)

echo "Script started with inputs $@"

while getopts ":v:t:" arg; do
    case "${arg}" in
      v)
        icp_version=${OPTARG}
        ;;
      t)
        target=${OPTARG}
        ;;
    esac
done

source /tmp/icp-bootmaster-scripts/functions.sh

# If loaded from tarball, icp version may not be specified in terraform
if [[ -z "${icp_version}" ]]; then
  icp_version=$(get_inception_image)
fi

# Figure out the version
# This will populate $org $repo and $tag
parse_icpversion ${icp_version}
echo "registry=${registry:-not specified} org=$org repo=$repo tag=$tag"

# Ensure that /opt/ibm is present and copy default data directory
sudo mkdir -p ${target}
sudo chown $(whoami):$(whoami) -R ${target}
docker run -e LICENSE=accept -v ${target}:/data ${registry}${registry:+/}${org}/${repo}:${tag} cp -r cluster /data
# Ensure that all data copied from installer has proper ownership
sudo chown $(whoami):$(whoami) -R ${target}

# Take a backup of original config file, to keep a record of original settings and comments
cp ${target}/cluster/config.yaml ${target}/cluster/config.yaml-original
