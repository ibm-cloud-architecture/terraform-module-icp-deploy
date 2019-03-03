#!/bin/bash
DefaultOrg="ibmcom"
DefaultRepo="icp-inception"

# Populates globals $org $repo $tag
function parse_icpversion() {

  # Determine if registry is also specified
  if [[ $1 =~ .*/.*/.* ]]
  then
    # Save the registry section of the string
    local r=$(echo ${1} | cut -d/ -f1)
    # Save username password if specified for registry
    if [[ $r =~ .*@.* ]]
    then
      local up=${r%@*}
      username=${up%%:*}
      password=${up#*:}
      registry=${r##*@}
    else
      registry=${r}
    fi
    org=$(echo ${1} | cut -d/ -f2)
  elif [[ $1 =~ .*/.* ]]
   # Determine organisation
  then
    org=$(echo ${1} | cut -d/ -f1)
  else
    org=$DefaultOrg
  fi

  # Determine repository and tag
  if [[ $1 =~ .*:.* ]]
  then
    repo=$(echo ${1##*/} | cut -d: -f1)
    tag=$(echo ${1##*/} | cut -d/ -f2 | cut -d: -f2)
  elif [[ "$1" == "" ]]
  then
    # We should autodetect the version if loaded from tarball
    # For now we grab the first matching image in docker image list.
    read -r repo tag <<<$(sudo docker image list | awk -v pat=$DefaultRepo ' $1 ~ pat { print $1 " " $2 ; exit }')

    # As a last resort we'll use the latest tag from docker hub
    if [[ -z $tag ]]; then
      repo=$DefaultRepo
      tag="latest"
    fi
  else
    # The last supported approach is to just supply version number
    repo=$DefaultRepo
    tag=$1
  fi
}

function get_inception_image() {
  # In cases where inception image has not been specified
  # we may look for inception image locally
  image=$(sudo docker image list | grep -m 1 inception | awk '{ print $1 ":" $2 }')
  echo $image
}

function ensure_directory_reachable() {
  # Ensure that the directory exists and is reachable:
  # 1) It is owned by the current user
  # 2) All parent directories are executable
  test_dir=$1
  sudo mkdir -p ${test_dir}
  sudo chown $(whoami):$(whoami) ${test_dir}
  f=${test_dir}
  while [[ $f != / ]]; do sudo chmod a+x "$f"; f=$(dirname "$f"); done;
}
