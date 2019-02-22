#!/bin/bash
cluster_base="/opt/ibm"

while getopts ":v:c:l:" arg; do
    case "${arg}" in
      v)
        icp_version=${OPTARG}
        ;;
      c)
        cluster_base=${OPTARG}
        ;;
      l)
        log_verbosity=${OPTARG}
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

docker run -e LICENSE=accept -e ANSIBLE_CALLBACK_WHITELIST=profile_tasks,timer --net=host -t -v ${cluster_base}/cluster:/installer/cluster ${registry}${registry:+/}${org}/${repo}:${tag} install ${log_verbosity} |& tee /tmp/icp-install-log.txt
exit ${PIPESTATUS[0]}
