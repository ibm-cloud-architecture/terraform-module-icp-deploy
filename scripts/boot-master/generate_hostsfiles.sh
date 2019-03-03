#!/bin/bash
LOGFILE=/tmp/generate_hostsfiles.log
exec 3>&1
exec > >(tee -a ${LOGFILE} >/dev/null) 2> >(tee -a ${LOGFILE} >&3)

source /tmp/icp-bootmaster-scripts/get-args.sh

# Make sure ssh key has correct permissions set before using
chmod 600 ${cluster_dir}/ssh_key

# Global array variable for holding all cluster ip/hostnames
declare -A cluster

# Make sure /tmp/hosts is empty, in case we running this a second time
[[ -e /tmp/hosts ]] && rm /tmp/hosts

# Functions for "traditional" groups (master, proxy, worker, management)
read_from_groupfiles() {
  ## First compile a list of all nodes in the cluster with ip addresses and associated hostnames
  declare -a master_ips
  IFS=', ' read -r -a master_ips <<< $(cat ${cluster_dir}/masterlist.txt)

  declare -a worker_ips
  IFS=', ' read -r -a worker_ips <<< $(cat ${cluster_dir}/workerlist.txt)

  declare -a proxy_ips
  IFS=', ' read -r -a proxy_ips <<< $(cat ${cluster_dir}/proxylist.txt)

  ## First gather all the hostnames and link them with ip addresses
  declare -A workers
  for worker in "${worker_ips[@]}"; do
    workers[$worker]=$(ssh -o StrictHostKeyChecking=no -i ${cluster_dir}/ssh_key ${worker} hostname)
    cluster[$worker]=${workers[$worker]}
    printf "%s     %s\n" "$worker" "${cluster[$worker]}" >> /tmp/hosts
  done

  declare -A proxies
  for proxy in "${proxy_ips[@]}"; do
    proxies[$proxy]=$(ssh -o StrictHostKeyChecking=no -i ${cluster_dir}/ssh_key ${proxy} hostname)
    cluster[$proxy]=${proxies[$proxy]}
    printf "%s     %s\n" "$proxy" "${cluster[$proxy]}" >> /tmp/hosts
  done

  declare -A masters
  for m in "${master_ips[@]}"; do
    # No need to ssh to self
    if hostname -I | grep -w $m &>/dev/null
    then
      masters[$m]=$(hostname)
    else
      masters[$m]=$(ssh -o StrictHostKeyChecking=no -i ${cluster_dir}/ssh_key ${m} hostname)
    fi
    cluster[$m]=${masters[$m]}
    printf "%s     %s\n" "$m" "${cluster[$m]}" >> /tmp/hosts
  done

  # Add management nodes if separate from master nodes
  if [[ -s ${cluster_dir}/managementlist.txt ]]
  then
    declare -a management_ips
    IFS=', ' read -r -a management_ips <<< $(cat ${cluster_dir}/managementlist.txt)

    declare -A mngrs
    for m in "${management_ips[@]}"; do
      mngrs[$m]=$(ssh -o StrictHostKeyChecking=no -i ${cluster_dir}/ssh_key ${m} hostname)
      cluster[$m]=${mngrs[$m]}
      printf "%s     %s\n" "$m" "${cluster[$m]}" >> /tmp/hosts
    done
  fi

  ## Generate the hosts file for the ICP installation
  echo '[master]' > ${cluster_dir}/hosts
  for master in "${master_ips[@]}"; do
    echo $master >> ${cluster_dir}/hosts
  done

  echo  >> ${cluster_dir}/hosts
  echo '[worker]' >> ${cluster_dir}/hosts
  for worker in "${worker_ips[@]}"; do
    echo $worker >> ${cluster_dir}/hosts
  done

  echo  >> ${cluster_dir}/hosts
  echo '[proxy]' >> ${cluster_dir}/hosts
  for proxy in "${proxy_ips[@]}"; do
    echo $proxy >> ${cluster_dir}/hosts
  done

  # Add management host entries if separate from master nodes
  if [[ ! -z ${management_ips} ]]
  then
    echo  >> ${cluster_dir}/hosts
    echo '[management]' >> ${cluster_dir}/hosts
    for m in "${management_ips[@]}"; do
      echo $m >> ${cluster_dir}/hosts
    done
  fi
}


read_from_hostgroups() {
  # First parse the hostgroup json
  python /tmp/icp-bootmaster-scripts/parse-hostgroups.py ${cluster_dir}

  # Get the cluster ips
  declare -a cluster_ips
  IFS=',' read -r -a cluster_ips <<< $(cat /tmp/cluster-ips.txt)

  # Generate the hostname/ip combination
  for node in "${cluster_ips[@]}"; do
    cluster[$node]=$(ssh -o StrictHostKeyChecking=no -o ConnectionAttempts=100 -i ${cluster_dir}/ssh_key ${node} hostname)
    printf "%s     %s\n" "$node" "${cluster[$node]}" >> /tmp/hosts
  done

}

#TODO: Figure out the situation when using separate boot node
#TODO: Make sure /tmp/hosts is empty, so we don't double up all the time
update_etchosts() {
  ## Update all hostfiles in all nodes in the cluster
  ## also remove the line for 127.0.1.1
  for node in "${!cluster[@]}"; do
    # No need to ssh to self
    if hostname -I | grep -w $node &>/dev/null
    then
      cat /tmp/hosts | cat - /etc/hosts | sed -e "/127.0.1.1/d" | sudo tee /etc/hosts
    else
      cat /tmp/hosts | ssh -i ${cluster_dir}/ssh_key ${node} 'cat - /etc/hosts | sed -e "/127.0.1.1/d" | sudo tee /etc/hosts'
    fi
  done
}


if [[ $( stat -c%s /tmp/icp-host-groups.json ) -gt 2 ]]; then
  read_from_hostgroups
elif [[ -s ${cluster_dir}/masterlist.txt ]]; then
  read_from_groupfiles
else
  echo "Couldn't find any hosts" >&2
  exit 1
fi

update_etchosts
