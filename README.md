# Terraform ICP Provision Module
This terraform module can be used to deploy IBM Cloud Private on any supported infrastructure vendor.
Tested on Ubuntu 16.04 and RHEL 7 on SoftLayer, VMware, AWS and Azure.

### Pre-requisites

If the default SSH user is not the root user, the default user must have password-less sudo access.


## Inputs

| Variable           | Default       |Required| Description                            |
|--------------------|---------------|--------|----------------------------------------|
| **Cluster settings** |
|icp-inception         |               |No*      |Version of ICP to provision. Not required when See below for details on using private registry|
|icp-master          |               |No*     |IP address of ICP Masters. Required if you don't use icp-host-groups |
|icp-worker          |               |No*     |IP addresses of ICP Worker nodes. Required if you don't use icp-host-groups       |
|icp-proxy           |               |No*     |IP addresses of ICP Proxy nodes. Required if you don't use icp-host-groups        |
|icp-management      |               |No      |IP addresses of ICP Management Nodes, if management is to be separated from master nodes. Optional|
| icp-host-groups   |                 |No*     | Map of host types and IPs. See below for details. |
| boot-node          |               |No*     | IP Address of boot node. Needed when using icp-host-groups or when using a boot node separate from first master node. If separate it must be included in `cluster_size` |
|cluster_size        |               |Yes     |Define total clustersize. Workaround for terraform issue #10857. Normally computed|
| **ICP Configuration** |
|icp_config_file     |               |No      |Yaml configuration file for ICP installation.|
|icp_configuration   |               |No      |Configuration items for ICP installation. See [KnowledgeCenter](https://www.ibm.com/support/knowledgecenter/SSBS6K_2.1.0/installing/config_yaml.html) for reference. Note: Boolean values (true/false) must be supplied as strings|
|config_strategy     |merge          |No      |Strategy for original config.yaml shipped with ICP. Default is merge, everything else means override. |
| **ICP Boot node to cluster communication** |
|generate_key        |True           |No      |Whether to generate a new ssh key for use by ICP Boot Master to communicate with other nodes|
|icp_pub_key         |               |No      |Public ssh key for ICP Boot master to connect to ICP Cluster. Only use when generate_key = false|
|icp_priv_key        |               |No      |Private ssh key for ICP Boot master to connect to ICP Cluster. Only use when generate_key = false|
| **Terraform installation process** |
|hooks               | |No      |Hooks into different stages in the cluster setup process. See below for details|
|local-hooks         | |No      |Locally run hooks at different stages in the cluster setup process. See below for details|
|on_hook_failure     |fail  |    |Behavior when hooks fail. Anything other than `fail` will `continue`|
|install-verbosity   | |No      | Verbosity of the icp ansible installer. -v to -vvvv. See ansible documentation for verbosity information |
| **Terraform to cluster ssh configuration**|
|ssh_user            |root           |No      |Username for Terraform to ssh into the ICP cluster. This is typically the default user with for the relevant cloud vendor|
|ssh_key_base64      |               |No      |base64 encoded content of private ssh key|
|ssh_agent           |True           |No      |Enable or disable SSH Agent. Can correct some connectivity issues. Default: true (enabled)|
|bastion_host        |               |No      |Specify hostname or IP to connect to nodes through a SSH bastion host. Assumes same SSH key and username as cluster nodes|
| **Docker and ICP Enterprise Edition Image configuration** |
|docker_package_location|               |No      |http or nfs location of docker installer which ships with ICP. Typically used for RHEL which does not support docker-ce|
|docker_image_name   |docker-ce      |No      |Name of docker image to install when installing from Ubuntu or Centos repository |
|docker_version      |latest         |No      |Version of docker image to install from Ubuntu or Centos repository. i.e. `18.06.1` `latest` install latest version. |
|image_location      |             |No      |Location of image file. Start with `nfs:` or `http` to indicate protocol to download with. See example below |
|image_location_user |  | No |Username if authentication required for image_location |
|image_location_pass |  | No | Password if authentication required for image_location |

## Outputs

- icp_public_key
    * The public key used for boot master to connect via ssh for cluster setup
- icp_private_key
    * The public key used for boot master to connect via ssh for cluster setup
- install_complete
    * Boolean value that is set to true when ICP installation process is completed
- icp_version
    * The ICP version that has been installed
- cluster_ips
    * List of IPs of the cluster

### ICP Version specifications
The `icp-inception` field supports the format `org`/`repo`:`version`. `ibmcom` is the default organisation and `icp-inception` is the default repo, so if you're installing for example version `2.1.0.2` from Docker Hub it's sufficient to specify `2.1.0.2` as the version number.

It is also supported to install from private docker registries.
In this case the format is:
`username`:`password`@`private_registry_server`/`org`/`repo`:`version`.

So for exmaple

`myuser:SomeLongPassword@myprivateregistry.local/ibmcom/icp-inception:2.1.0.2`


### Remote Execution Hooks
It is possible to execute arbitrary commands between various phases of the cluster setup and installation process.
Currently, the following hooks are defined. Each hook must be a list of commands to run.

| Hook name          | Where executed | When executed                                              |
|--------------------|----------------|------------------------------------------------------------|
| cluster-preconfig  | all nodes      | Before any of the module scripts |
| cluster-postconfig | all nodes      | After prerequisites are installed |
| boot-preconfig     | boot master    | Before any module scripts on boot master |
| preinstall         | boot master    | After configuration image load and configuration generation|
| postinstall        | boot master    | After successful ICP installation                          |

### Local Execution Hooks
It is possible to execute arbitrary commands between various phases of the cluster setup and installation process.
Currently, the following hooks are defined. Each hook must be a single command to run.

| Hook name          | When executed                                              |
|--------------------|------------------------------------------------------------|
| local-preinstall   | After configuration and preinstall remote hook |
| local-postinstall  | After successful ICP installation |

These hooks support the execution of a single command or a local script. While this is a local-exec [command](https://www.terraform.io/docs/provisioners/local-exec.html#command), passing additional interpreter/environment parameters are not supported and therefore everything will be treated as a BASH script.


### Host groups
In ICP version 2.1.0.2 the concept of host groups were introduced. This allows users to define groups of hosts by an arbritrary name that will be labelled such that they can be dedicated to particular workloads. You can read more about host groups on the [KnowledgeCenter](https://www.ibm.com/support/knowledgecenter/en/SSBS6K_2.1.0.2/installing/hosts.html)

To support this an input map called `icp-host-groups` were introduced, and this can be used to generate the relevant hosts file for the ICP installer. When using this field it should be used **instead of** the `icp-master`, `icp-worker`, etc fields.

## Usage example

### Using hooks

```hcl
module "icpprovision" {
    source = "github.com/ibm-cloud-architecture/terraform-module-icp-deploy?ref=3.0.0"

    icp-master  = ["${softlayer_virtual_guest.icpmaster.ipv4_address}"]
    icp-worker  = ["${softlayer_virtual_guest.icpworker.*.ipv4_address}"]
    icp-proxy   = ["${softlayer_virtual_guest.icpproxy.*.ipv4_address}"]

    icp-inception = "3.1.2"

    cluster_size  = "${var.master["nodes"] + var.worker["nodes"] + var.proxy["nodes"]}"

    icp_configuration = {
      "network_cidr"              = "192.168.0.0/16"
      "service_cluster_ip_range"  = "172.16.0.1/24"
      "default_admin_password"    = "My0wnPassw0rd"
    }

    generate_key = true

    ssh_user       = "ubuntu"
    ssh_key_base64 = "${base64encode(file("~/.ssh/id_rsa"))}"

    hooks = {
      "cluster-preconfig" = [
        "echo This will run on all nodes",
        "echo And I can run as many commands",
        "echo as I want",
        "echo ....they will run in order"
      ]
      "postinstall" = [
        "echo Performing some post install backup",
        "${ var.postinstallbackup != "true" ? "" : "sudo chmod a+x /tmp/icp_backup.sh ; sudo /tmp/icp_backup.sh" }"
      ]
    }
}
```


#### Using HostGroups

```hcl
module "icpprovision" {
    source = "github.com/ibm-cloud-architecture/terraform-module-icp-deploy?ref=3.0.0"

    # We will define master, management, worker, proxy and va (Vulnerability Assistant) as well as a custom db2 group
    icp-host-groups = {
      master     = "${openstack_compute_instance_v2.icpmaster.*.access_ip_v4}"
      management = "${openstack_compute_instance_v2.icpmanagement.*.access_ip_v4}"
      worker     = "${openstack_compute_instance_v2.icpworker.*.access_ip_v4}"
      proxy      = "${openstack_compute_instance_v2.icpproxy.*.access_ip_v4}"
      va         = "${openstack_compute_instance_v2.icpva.*.access_ip_v4}"

      hostgroup-db2        = "${openstack_compute_instance_v2.icpdb2.*.access_ip_v4}"
    }

    # We always have to specify a node to bootstrap the cluster. It can be any of the cluster nodes, or a separate node that has network access to the cluster.
    # We will use the first master node as boot node to run the ansible installer from
    boot-node   = "${openstack_compute_instance_v2.icpmaster.0.access_ip_v4}"

    icp-inception = "3.1.2"

    cluster_size  = "${var.master["nodes"] + var.worker["nodes"] + var.proxy["nodes"]}"

    icp_configuration = {
      "network_cidr"              = "192.168.0.0/16"
      "service_cluster_ip_range"  = "172.16.0.1/24"
      "default_admin_password"    = "My0wnPassw0rd"
    }
}
```

#### Community Edition

```hcl
module "icpprovision" {
    source = "github.com/ibm-cloud-architecture/terraform-module-icp-deploy?ref=3.0.0"

    icp-master  = ["${softlayer_virtual_guest.icpmaster.ipv4_address}"]
    icp-worker  = ["${softlayer_virtual_guest.icpworker.*.ipv4_address}"]
    icp-proxy   = ["${softlayer_virtual_guest.icpproxy.*.ipv4_address}"]

    icp-inception = "3.1.2"

    cluster_size  = "${var.master["nodes"] + var.worker["nodes"] + var.proxy["nodes"]}"

    icp_configuration = {
      "network_cidr"              = "192.168.0.0/16"
      "service_cluster_ip_range"  = "172.16.0.1/24"
      "default_admin_password"    = "My0wnPassw0rd"
    }

    generate_key = true

    ssh_user       = "ubuntu"
    ssh_key_base64 = "${base64encode(file("~/.ssh/id_rsa"))}"

}
```

#### Enterprise Edition

From NFS location

```hcl
module "icpprovision" {
    source = "github.com/ibm-cloud-architecture/terraform-module-icp-deploy?ref=3.0.0"

    icp-master = ["${softlayer_virtual_guest.icpmaster.ipv4_address}"]
    icp-worker = ["${softlayer_virtual_guest.icpworker.*.ipv4_address}"]
    icp-proxy  = ["${softlayer_virtual_guest.icpproxy.*.ipv4_address}"]

    image_location = "nfs:fsf-lon0601b-fz.adn.networklayer.com:/IBM02S6275/data01/ibm-cloud-private-x86_64-2.1.0.1.tar.gz"

    cluster_size  = "${var.master["nodes"] + var.worker["nodes"] + var.proxy["nodes"]}"

    icp_configuration = {
      "network_cidr"              = "192.168.0.0/16"
      "service_cluster_ip_range"  = "172.16.0.1/24"
      "default_admin_password"    = "My0wnPassw0rd"
    }

    generate_key = true

    ssh_user       = "ubuntu"
    ssh_key_base64 = "${base64encode(file("~/.ssh/id_rsa"))}"

}
```

From HTTP location

```hcl
module "icpprovision" {
    source = "github.com/ibm-cloud-architecture/terraform-module-icp-deploy?ref=3.0.0"

    icp-master = ["${softlayer_virtual_guest.icpmaster.ipv4_address}"]
    icp-worker = ["${softlayer_virtual_guest.icpworker.*.ipv4_address}"]
    icp-proxy  = ["${softlayer_virtual_guest.icpproxy.*.ipv4_address}"]

    image_location = "https://myserver.host/myfiles/ibm-cloud-private-x86_64-2.1.0.1.tar.gz"


    cluster_size  = "${var.master["nodes"] + var.worker["nodes"] + var.proxy["nodes"]}"

    icp_configuration = {
      "network_cidr"              = "192.168.0.0/16"
      "service_cluster_ip_range"  = "172.16.0.1/24"
      "default_admin_password"    = "My0wnPassw0rd"
    }

    generate_key = true

    ssh_user       = "ubuntu"
    ssh_key_base64 = "${base64encode(file("~/.ssh/id_rsa"))}"

}
```

There are several examples for different providers available from [IBM Cloud Architecture Solutions Group github page](https://github.com/ibm-cloud-architecture)
- [ICP on SoftLayer](https://github.com/ibm-cloud-architecture/terraform-icp-softlayer)
- [ICP on VMware](https://github.com/ibm-cloud-architecture/terraform-icp-vmware)


### ICP Configuration
Configuration file is generated from items in the following order

1. config.yaml shipped with ICP (if config_strategy = merge, else blank)
2. config.yaml specified in `icp_config_file`
3. key: value items specified in `icp_configuration`

Details on configuration items on ICP KnowledgeCenter
* [ICP 1.2.0](https://www.ibm.com/support/knowledgecenter/SSBS6K_1.2.0/installing/config_yaml.html)
* [ICP 2.1.0](https://www.ibm.com/support/knowledgecenter/SSBS6K_2.1.0/installing/config_yaml.html)


### Scaling
The module supports automatic scaling of worker nodes.
To scale simply add more nodes in the root resource supplying the `icp-worker` variable.
You can see working examples for softlayer [in the icp-softlayer](https://github.com/ibm-cloud-architecture/terraform-icp-softlayer) repository

Please note, because of how terraform handles module dependencies and triggers, it is currently necessary to retrigger the scaling resource **after scaling down** nodes.
If you don't do this ICP will continue to report inactive nodes until the next scaling event.
To manually trigger the removal of deleted node, run these commands:

1. `terraform taint --module icpprovision null_resource.icp-worker-scaler`
2. `terraform apply`


## Module Versions

As new use cases and best practices emerge code will be added to and changed the in module. Any changes in the code leads to a new release version. The module versions follow a [semantic versioning](https://semver.org/) scheme.

To avoid breaking existing templates which depends on the module it is recommended to add a version tag to the module source when pulling directly from git.


### Versions and changes
#### 3.0.0
- Retire parallel image pull
- Retire unused variables (enterprise-edition, image_file, ssh_key, ssh_key_file)
- Default to generate strong default admin password if no password is specified
- Detect inception image when installing from offline tarball
- Rename `icp-version` variable to more descriptive `icp-inception`
- Overhaul of scaler function
- Add support for automatic installation of docker on RHEL and Centos
- Add support for downloading multi-arch images
- Fix wget output spamming during wget image download
- Include BATS test for testing scripts locally
- Rewrite image-load to take username and password separately when downloading from HTTP source

#### 2.4.0
- Add support for local hooks
- Support specifying docker version when installing docker with apt (Ubuntu only)
- Ensure /opt/ibm is present before copying cluster skeleton

#### 2.3.7
- Add retry logic to apt-get when installing prerequisites. Sometimes cloud-init or some other startup process can hold a lock on apt.

#### 2.3.6
- Retry ssh from boot to cluster nodes when generating /etc/hosts entries. Fixes issues when some cluster nodes are provisioned substantially slower.
- Report exit code from docker when running ansible installer, rather than the last command in the pipelist (tee)

#### 2.3.5
- Skip blanks when generating config.yaml as yaml.safe_dump exports them as '' which ansible installer doesn't like

#### 2.3.4
- Create backup copy of original config.yaml to keep options and comments
- Support nested dictionaries when parsing `icp_configuration` to convert true/false strings to booleans

#### 2.3.3
- Fix empty icp-master list issue when using icp-host-groups
- Fix issue with docker package install from nfs source
- Make docker check silent when docker is not installed

#### 2.3.2
- Fix issues with terraform formatting of boolean values in config.yaml

#### 2.3.1
- Fix issue with non-hostgroups installations not generating hosts files
- Fix boot-node not being optional in non-hostgroups installations
- Fix issue with boot node trying to ssh itself
- Install docker from repository if no other method selected (ubuntu only)
- Fix apt install issue for prerequisites

#### 2.3.0
- Add full support for separate boot node
- Save icp install log output to /tmp/icp-install-log.txt
- Add option for verbosity on icp install log output

#### 2.2.2
- Fix issues with email usernames when using private registry
- Fix passwords containing ':' when using private registry

#### 2.2.1
- Fix scaler error when using hostgroups

#### 2.2.0
- Added support for hostgroups
- Updated preprequisites scripts to avoid emediate failure in airgapped installations
- Include module outputs


#### 2.1.0
- Added support for install hooks
- Added support for converged proxy nodes (combined master/proxy)
- Added support for private docker registry

#### 2.0.1
- Fixed problem with worker scaler

#### 2.0.0
- Added support for ssh bastion host
- Added support for dedicated management hosts
- Split up null_resource provisioners to increase granularity
- Added support for parallel load of EE images
- Various fixes

#### 1.0.0
- Initial release
