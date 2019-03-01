#!/usr/bin/env bats

export APT_PREREQS="lsb-release:dialog:wget"
export YUM_PREREQS="subscription-manager:wget"

load helpers


@test "Download single from http source" {
  run run_in_docker \
    -i ${IMAGE} \
    -s "/tmp/icp-bootmaster-scripts/load-image.sh" \
    -p "-l https://httpbin.org/anything/ibm-cloud-private-x86_64-3.1.2.tar.gz -d /opt/ibm/cluster" \
    -t "ls /opt/ibm/cluster/images/ibm-cloud-private-x86_64-3.1.2.tar.gz" \
    -f "sudo:docker:tar"

  [ $status -eq 0 ]
}

@test "Download single from http source with authentication" {
  run run_in_docker \
    -i ${IMAGE} \
    -s "/tmp/icp-bootmaster-scripts/load-image.sh" \
    -p "-u foo -p ibm-cloud-private-x86_64-3.1.2.tar.gz -l https://httpbin.org/basic-auth/foo/ibm-cloud-private-x86_64-3.1.2.tar.gz -d /opt/ibm/cluster" \
    -t "ls /opt/ibm/cluster/images/ibm-cloud-private-x86_64-3.1.2.tar.gz" \
    -f "sudo:docker:tar"

  [ $status -eq 0 ]
}

@test "Download multiple from http source" {
  run run_in_docker \
    -i ${IMAGE} \
    -s "/tmp/icp-bootmaster-scripts/load-image.sh" \
    -p "-l https://httpbin.org/anything/ibm-cloud-private-x86_64-3.1.2.tar.gz -l https://httpbin.org/anything/ibm-cloud-private-s390x-3.1.2.tar.gz -d /opt/ibm/cluster" \
    -t "ls /opt/ibm/cluster/images/ibm-cloud-private-x86_64-3.1.2.tar.gz /opt/ibm/cluster/images/ibm-cloud-private-s390x-3.1.2.tar.gz" \
    -f "sudo:docker:tar"

  [ $status -eq 0 ]
}

@test "Incorrect URL should fail" {
  run run_in_docker \
    -i ${IMAGE} \
    -s "/tmp/icp-bootmaster-scripts/load-image.sh" \
    -p "-l https://dead.url.bar/ibm-cloud-private-x86_64-3.1.2.tar.gz -d /opt/ibm/cluster" \
    -f "sudo:docker:tar"

  [ $status -gt 0 ]
}

@test "Incorrect authentication should fail" {
  run run_in_docker \
    -i ${IMAGE} \
    -s "/tmp/icp-bootmaster-scripts/load-image.sh" \
    -p "-u foo -p bar -l https://httpbin.org/basic-auth/foo/ibm-cloud-private-x86_64-3.1.2.tar.gz -d /opt/ibm/cluster" \
    -f "sudo:docker:tar"

  [ $status -gt 0 ]
}
