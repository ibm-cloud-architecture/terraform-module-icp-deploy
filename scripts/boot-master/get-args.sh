#!/bin/bash

while getopts ":i:d:v:c:l:u:p:o:k:s:" arg; do
    case "${arg}" in
      i)
        icp_inception=${OPTARG}
        ;;
      d)
        cluster_dir=${OPTARG}
        if [ ! -d "$cluster_dir" ]; then
          sudo mkdir -p ${cluster_dir}
        fi
        if [ ! -f /CLUSTER_DIR_REACHABLE ]; then
          f=${cluster_dir}
          while [[ $f != / ]]; do chmod a+x \"$f\"; f=$(dirname \"$f\"); done;
          sudo touch /CLUSTER_DIR_REACHABLE
        fi
        ;;
      v)
        log_verbosity=${OPTARG}
        ;;
      c)
        install_command=${OPTARG}
        ;;   
      l)
        locations+=( ${OPTARG} )
        ;;
      u)
        username=${OPTARG}
        ;;
      p)
        password=${OPTARG}
        ;;
      o)
        docker_package_location=${OPTARG}
        ;;
      k)
        docker_image=${OPTARG}
        ;;
      s)
        docker_version=${OPTARG}
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