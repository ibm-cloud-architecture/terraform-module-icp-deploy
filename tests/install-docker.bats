#!/usr/bin/env bats

# These variables are used by the run_in_docker function
export APT_PREREQS="sudo:curl:lsb-release:dialog"
export YUM_PREREQS="sudo:curl:subscription-manager"

load helpers

@test "Install latest docker on ${IMAGE}" {
  run run_in_docker \
    -i ${IMAGE} \
    -s "/tmp/icp-bootmaster-scripts/install-docker.sh" \
    -p "-k docker-ce -s latest" \
    -t "docker --version"
  [ $status -eq 0 ]
}

@test "Install version pinned docker on ${IMAGE}" {
  run run_in_docker \
    -i ${IMAGE} \
    -s "/tmp/icp-bootmaster-scripts/install-docker.sh" \
    -p "-k docker-ce -s 18.06.1" \
    -t "docker --version"
  [ $status -eq 0 ]
}


@test "Install invalid docker version on ${IMAGE} should fail" {
  run run_in_docker \
    -i ${IMAGE} \
    -s "/tmp/icp-bootmaster-scripts/install-docker.sh" \
    -p "-k docker-ce -s 3.1.1" \
    -t "docker --version"
  [ $status -gt 0 ]
}
