
# Generate a new key if this is required
resource "tls_private_key" "icpkey" {
  algorithm   = "RSA"
}

# Generate a random string for password if required
resource "random_string" "generated_password" {
  length            = "32"
  special           = "false"
}

## cluster-preconfig hooks are run before icp-cluster if defined


## Actions that has to be taken on all nodes in the cluster
resource "null_resource" "icp-cluster" {
  depends_on = ["null_resource.icp-cluster-preconfig-hook-continue-on-fail", "null_resource.icp-cluster-preconfig-hook-stop-on-fail"]
  count = "${var.cluster_size}"

  connection {
      host          = "${element(local.icp-ips, count.index)}"
      user          = "${var.ssh_user}"
      private_key   = "${local.ssh_key}"
      agent         = "${var.ssh_agent}"
      bastion_host  = "${var.bastion_host}"
  }

  # Validate we can do passwordless sudo in case we are not root
  provisioner "remote-exec" {
    inline = [
      "sudo -n echo This will fail unless we have passwordless sudo access"
    ]
  }

  provisioner "remote-exec" {
    inline = [
      "mkdir -p /tmp/icp-common-scripts"
    ]
  }
  provisioner "file" {
    source      = "${path.module}/scripts/common/"
    destination = "/tmp/icp-common-scripts"
  }

  provisioner "remote-exec" {
    inline = [
      "mkdir -p ~/.ssh",
      "echo '${var.generate_key ? tls_private_key.icpkey.public_key_openssh : var.icp_pub_key}' | tee -a ~/.ssh/authorized_keys",
      "chmod a+x /tmp/icp-common-scripts/*",
      "/tmp/icp-common-scripts/prereqs.sh",
      "/tmp/icp-common-scripts/version-specific.sh ${var.icp-inception}",
      "/tmp/icp-common-scripts/docker-user.sh"
    ]
  }
}

## icp-boot-preconfig hooks are run before icp-docker, if defined

# To make script parameters more consistent we'll define a common set here
locals {
  script_options = "${join(" -", list(""), compact(list(
    var.icp-inception           == "" ? "" : "i ${var.icp-inception}",
    var.cluster-directory       == "" ? "" : "d ${var.cluster-directory}",
    var.install-verbosity       == "" ? "" : "l ${var.install-verbosity}",
    var.install-command         == "" ? "" : "c ${var.install-command}",
    var.image_location_user     == "" ? "" : "u ${var.image_location_user}",
    var.image_location_pass     == "" ? "" : "p ${var.image_location_pass}",
    var.image_location          == "" ? "" : "l ${var.image_location}",
    length(var.image_locations) == 0  ? "" : "l ${join(" -l ", var.image_locations )}",
    var.docker_package_location == "" ? "" : "o ${var.docker_package_location}",
    var.docker_image_name       == "" ? "" : "k ${var.docker_image_name}",
    var.docker_version          == "" ? "" : "s ${var.docker_version}"
  )))}"
}

resource "null_resource" "icp-docker" {
  depends_on = ["null_resource.icp-boot-preconfig-continue-on-fail", "null_resource.icp-boot-preconfig-stop-on-fail", "null_resource.icp-cluster"]

  # Boot node is always the first entry in the IP list, so if we're not pulling in parallel this will only happen on boot node
  connection {
    host          = "${element(local.icp-ips, 0)}"
    user          = "${var.ssh_user}"
    private_key   = "${local.ssh_key}"
    agent         = "${var.ssh_agent}"
    bastion_host  = "${var.bastion_host}"
  }
  
  provisioner "remote-exec" {
    inline = [
      "mkdir -p /tmp/icp-bootmaster-scripts"
    ]
  }

  provisioner "file" {
    source      = "${path.module}/scripts/boot-master/"
    destination = "/tmp/icp-bootmaster-scripts"
  }

  # Make sure scripts are executable and docker installed
  provisioner "remote-exec" {
    inline = [
      "chmod a+x /tmp/icp-bootmaster-scripts/*.sh",
      "/tmp/icp-bootmaster-scripts/install-docker.sh ${local.script_options}"
    ]
  }
}

resource "null_resource" "icp-image" {
  depends_on = ["null_resource.icp-docker"]

  # Boot node is always the first entry in the IP list
  connection {
    host          = "${element(local.icp-ips, 0)}"
    user          = "${var.ssh_user}"
    private_key   = "${local.ssh_key}"
    agent         = "${var.ssh_agent}"
    bastion_host  = "${var.bastion_host}"
  }

  provisioner "remote-exec" {
    inline = [
      "echo \"Loading image ${var.icp-inception} ${var.image_location}\"",
      "/tmp/icp-bootmaster-scripts/load-image.sh ${local.script_options}"
    ]
  }
}


# First make sure scripts and configuration files are copied
resource "null_resource" "icp-boot" {

  depends_on = ["null_resource.icp-image"]

  # The first master is always the boot master where we run provisioning jobs from
  connection {
    host          = "${local.boot-node}"
    user          = "${var.ssh_user}"
    private_key   = "${local.ssh_key}"
    agent         = "${var.ssh_agent}"
    bastion_host  = "${var.bastion_host}"
  }


  # store config yaml if it was specified
  provisioner "file" {
    source       = "${var.icp_config_file}"
    destination = "/tmp/config.yaml"
  }

  # JSON dump the contents of icp_configuration items
  provisioner "file" {
    content     = "${jsonencode(var.icp_configuration)}"
    destination = "/tmp/items-config.yaml"
  }
}

# Generate all necessary configuration files, load image files, etc
resource "null_resource" "icp-config" {
  depends_on = ["null_resource.icp-boot"]

  # The first master is always the boot master where we run provisioning jobs from
  connection {
    host          = "${local.boot-node}"
    user          = "${var.ssh_user}"
    private_key   = "${local.ssh_key}"
    agent         = "${var.ssh_agent}"
    bastion_host  = "${var.bastion_host}"
  }

  provisioner "remote-exec" {
    inline = [
      "/tmp/icp-bootmaster-scripts/copy_cluster_skel.sh ${local.script_options}",
      "python /tmp/icp-bootmaster-scripts/load-config.py ${var.cluster-directory} ${var.config_strategy} ${random_string.generated_password.result}"
    ]
  }

  # Copy the provided or generated private key
  provisioner "file" {
      content = "${var.generate_key ? tls_private_key.icpkey.private_key_pem : var.icp_priv_key}"
      destination = "/tmp/icp/cluster/ssh_key"
  }

  # Since the file provisioner deals badly with empty lists, we'll create the optional management nodes differently
  # Later we may refactor to use this method for all node types for consistency
  provisioner "remote-exec" {
    inline = [
      "echo -n ${join(",", var.icp-master)} > /tmp/icp/cluster/masterlist.txt",
      "echo -n ${join(",", var.icp-proxy)} > /tmp/icp/cluster/proxylist.txt",
      "echo -n ${join(",", var.icp-worker)} > /tmp/icp/cluster/workerlist.txt",
      "echo -n ${join(",", var.icp-management)} > /tmp/icp/cluster/managementlist.txt",
      "mv -f /tmp/icp/cluster/* ${var.cluster-directory}/",
      "chmod 600 ${var.cluster-directory}/ssh_key"
    ]
  }

  # JSON dump the contents of icp-host-groups items
  provisioner "file" {
    content     = "${jsonencode(var.icp-host-groups)}"
    destination = "/tmp/icp-host-groups.json"
  }
}



# Generate the hosts files on the cluster
resource "null_resource" "icp-generate-hosts-files" {
  depends_on = ["null_resource.icp-config"]

  # The first master is always the boot master where we run provisioning jobs from
  connection {
    host          = "${local.boot-node}"
    user          = "${var.ssh_user}"
    private_key   = "${local.ssh_key}"
    agent         = "${var.ssh_agent}"
    bastion_host  = "${var.bastion_host}"
  }

  provisioner "remote-exec" {
    inline = [
      "/tmp/icp-bootmaster-scripts/generate_hostsfiles.sh ${local.script_options}"
    ]
  }
}

# Boot node and local hooks are run before install if defined

# Start the installer
resource "null_resource" "icp-install" {
  depends_on = ["null_resource.local-preinstall-hook-continue-on-fail", "null_resource.local-preinstall-hook-stop-on-fail", "null_resource.icp-generate-hosts-files"]

  # The first master is always the boot master where we run provisioning jobs from
  connection {
    host          = "${local.boot-node}"
    user          = "${var.ssh_user}"
    private_key   = "${local.ssh_key}"
    agent         = "${var.ssh_agent}"
    bastion_host  = "${var.bastion_host}"
  }


  provisioner "remote-exec" {
    inline = [
      "/tmp/icp-bootmaster-scripts/start_install.sh ${local.script_options}"
    ]
  }
}

## Post install hooks are run after installation if defined

resource "null_resource" "icp-worker-scaler" {
  depends_on = ["null_resource.icp-cluster", "null_resource.icp-install"]

  triggers {
    workers = "${join(",", var.icp-worker)}"
  }

  connection {
    host          = "${local.boot-node}"
    user = "${var.ssh_user}"
    private_key   = "${local.ssh_key}"
    agent = "${var.ssh_agent}"
    bastion_host  = "${var.bastion_host}"
  }

  provisioner "remote-exec" {
    inline = [
      "echo -n ${join(",", var.icp-master)} > /tmp/masterlist.txt",
      "echo -n ${join(",", var.icp-proxy)} > /tmp/proxylist.txt",
      "echo -n ${join(",", var.icp-worker)} > /tmp/workerlist.txt",
      "echo -n ${join(",", var.icp-management)} > /tmp/managementlist.txt"
    ]
  }

  # JSON dump the contents of icp-host-groups items
  provisioner "file" {
    content     = "${jsonencode(var.icp-host-groups)}"
    destination = "/tmp/scaled-host-groups.json"
  }


  provisioner "file" {
    source      = "${path.module}/scripts/boot-master/scaleworkers.sh"
    destination = "/tmp/icp-bootmaster-scripts/scaleworkers.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod a+x /tmp/icp-bootmaster-scripts/scaleworkers.sh",
      "sudo chown ${var.ssh_user}:${var.ssh_user} -R ${var.cluster-directory}",
      "/tmp/icp-bootmaster-scripts/scaleworkers.sh ${local.script_options}",
      "sudo chown ${local.cluster_dir_owner}:${local.cluster_dir_owner} -R ${var.cluster-directory}"
    ]
  }
}

resource "null_resource" "icp-cluster-owner" {
  depends_on = ["null_resource.icp-worker-scaler", "null_resource.icp-postinstall-hook-continue-on-fail", "null_resource.icp-postinstall-hook-stop-on-fail"]

  # Change the owner of the cluster directory to the desired user
  connection {
    host          = "${local.boot-node}"
    user          = "${var.ssh_user}"
    private_key   = "${local.ssh_key}"
    agent         = "${var.ssh_agent}"
    bastion_host  = "${var.bastion_host}"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo chown ${local.cluster_dir_owner}:${local.cluster_dir_owner} -R ${var.cluster-directory}",
    ]
  }
}
