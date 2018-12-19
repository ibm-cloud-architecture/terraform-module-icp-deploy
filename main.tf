
# Generate a new key if this is required
resource "tls_private_key" "icpkey" {
  # count       = "${var.generate_key ? 1 : 0}" # Generate the key anyways, since the output logic needs it for interpolation
  algorithm   = "RSA"

  provisioner "local-exec" {
    command = "cat > privatekey.pem <<EOL\n${tls_private_key.icpkey.private_key_pem}\nEOL"
  }
}

## Cluster Pre-config hook
resource "null_resource" "icp-cluster-preconfig-hook-stop-on-fail" {
  count = "${var.on_hook_failure == "fail" ? var.cluster_size : 0}"

  connection {
      host          = "${element(local.icp-ips, count.index)}"
      user          = "${var.ssh_user}"
      private_key   = "${local.ssh_key}"
      agent         = "${var.ssh_agent}"
      bastion_host  = "${var.bastion_host}"
  }

  # Run cluster-preconfig commands
  provisioner "remote-exec" {
    inline = [
      "${var.hooks["cluster-preconfig"]}"
    ]
    on_failure = "fail"
  }
}
resource "null_resource" "icp-cluster-preconfig-hook-continue-on-fail" {
  count = "${var.on_hook_failure != "fail" ? var.cluster_size : 0}"

  connection {
      host          = "${element(local.icp-ips, count.index)}"
      user          = "${var.ssh_user}"
      private_key   = "${local.ssh_key}"
      agent         = "${var.ssh_agent}"
      bastion_host  = "${var.bastion_host}"
  }

  # Run cluster-preconfig commands
  provisioner "remote-exec" {
    inline = [
      "${var.hooks["cluster-preconfig"]}"
    ]
    on_failure = "continue"
  }
}

## Actions that has to be taken on all nodes in the cluster
resource "null_resource" "icp-cluster" {
  depends_on = ["null_resource.icp-cluster-preconfig-hook"]
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
      "/tmp/icp-common-scripts/version-specific.sh ${var.icp-version}",
      "/tmp/icp-common-scripts/docker-user.sh"
    ]
  }
}

## Cluster postconfig hook
resource "null_resource" "icp-cluster-postconfig-hook-stop-on-fail" {
  depends_on = ["null_resource.icp-cluster"]
  count = "${var.on_hook_failure == "fail" ? var.cluster_size : 0}"

  connection {
      host          = "${element(local.icp-ips, count.index)}"
      user          = "${var.ssh_user}"
      private_key   = "${local.ssh_key}"
      agent         = "${var.ssh_agent}"
      bastion_host  = "${var.bastion_host}"
  }

  # Run cluster-postconfig commands
  provisioner "remote-exec" {
    inline = [
      "${var.hooks["cluster-postconfig"]}"
    ]
    on_failure = "fail"
  }
}
resource "null_resource" "icp-cluster-postconfig-hook-continue-on-fail" {
  depends_on = ["null_resource.icp-cluster"]
  count = "${var.on_hook_failure != "fail" ? var.cluster_size : 0}"

  connection {
      host          = "${element(local.icp-ips, count.index)}"
      user          = "${var.ssh_user}"
      private_key   = "${local.ssh_key}"
      agent         = "${var.ssh_agent}"
      bastion_host  = "${var.bastion_host}"
  }

  # Run cluster-postconfig commands
  provisioner "remote-exec" {
    inline = [
      "${var.hooks["cluster-postconfig"]}"
    ]
    on_failure = "continue"
  }
}


# First hook for Boot node
resource "null_resource" "icp-boot-preconfig-stop-on-fail" {
  depends_on = ["null_resource.icp-cluster-postconfig-hook", "null_resource.icp-cluster"]
  count = "${var.on_hook_failure == "fail" ? 1 : 0}"

  # The first master is always the boot master where we run provisioning jobs from
  connection {
    host          = "${local.boot-node}"
    user          = "${var.ssh_user}"
    private_key   = "${local.ssh_key}"
    agent         = "${var.ssh_agent}"
    bastion_host  = "${var.bastion_host}"
  }

  # Run stage hook commands
  provisioner "remote-exec" {
    inline = [
      "${var.hooks["boot-preconfig"]}"
    ]
    on_failure = "fail"
  }
}
resource "null_resource" "icp-boot-preconfig-continue-on-fail" {
  depends_on = ["null_resource.icp-cluster-postconfig-hook", "null_resource.icp-cluster"]
  count = "${var.on_hook_failure != "fail" ? 1 : 0}"

  # The first master is always the boot master where we run provisioning jobs from
  connection {
    host          = "${local.boot-node}"
    user          = "${var.ssh_user}"
    private_key   = "${local.ssh_key}"
    agent         = "${var.ssh_agent}"
    bastion_host  = "${var.bastion_host}"
  }

  # Run stage hook commands
  provisioner "remote-exec" {
    inline = [
      "${var.hooks["boot-preconfig"]}"
    ]
    on_failure = "continue"
  }
}

resource "null_resource" "icp-docker" {
  depends_on = ["null_resource.icp-boot-preconfig", "null_resource.icp-cluster"]

  count = "${var.parallell-image-pull ? var.cluster_size : "1"}"

  # Boot node is always the first entry in the IP list, so if we're not pulling in parallell this will only happen on boot node
  connection {
    host          = "${element(local.icp-ips, count.index)}"
    user          = "${var.ssh_user}"
    private_key   = "${local.ssh_key}"
    agent         = "${var.ssh_agent}"
    bastion_host  = "${var.bastion_host}"
  }


  provisioner "remote-exec" {
    inline = [
      "mkdir -p /tmp/icp-bootmaster-scripts",
      "sudo mkdir -p /opt/ibm/cluster",
      "sudo chown ${var.ssh_user} /opt/ibm/cluster"
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
      "/tmp/icp-bootmaster-scripts/install-docker.sh \"${var.docker_package_location}\" \"${var.docker_image_name}\" \"${var.docker_version}\""
    ]
  }
}

resource "null_resource" "icp-image" {
  depends_on = ["null_resource.icp-docker"]

  count = "${var.parallell-image-pull ? var.cluster_size : "1"}"

  # Boot node is always the first entry in the IP list, so if we're not pulling in parallell this will only happen on boot node
  connection {
    host          = "${element(local.icp-ips, count.index)}"
    user          = "${var.ssh_user}"
    private_key   = "${local.ssh_key}"
    agent         = "${var.ssh_agent}"
    bastion_host  = "${var.bastion_host}"
  }

  # If this is enterprise edition we'll need to copy the image file over and load it in local repository
  // We'll need to find another workaround while tf does not support count for this
  provisioner "file" {
      # count = "${var.enterprise-edition ? 1 : 0}"
      source = "${var.enterprise-edition ? var.image_file : "/dev/null" }"
      destination = "/tmp/${basename(var.image_file)}"
  }

  provisioner "remote-exec" {
    inline = [
      "echo \"Loading image ${var.icp-version}\"",
      "/tmp/icp-bootmaster-scripts/load-image.sh ${var.icp-version} /tmp/${basename(var.image_file)} \"${var.image_location}\" "
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
      "/tmp/icp-bootmaster-scripts/copy_cluster_skel.sh ${var.icp-version}",
      "sudo chown ${var.ssh_user} /opt/ibm/cluster/*",
      "chmod 600 /opt/ibm/cluster/ssh_key",
      "python /tmp/icp-bootmaster-scripts/load-config.py ${var.config_strategy}"
    ]
  }

  # Copy the provided or generated private key
  provisioner "file" {
      content = "${var.generate_key ? tls_private_key.icpkey.private_key_pem : var.icp_priv_key}"
      destination = "/opt/ibm/cluster/ssh_key"
  }


  # Since the file provisioner deals badly with empty lists, we'll create the optional management nodes differently
  # Later we may refactor to use this method for all node types for consistency
  provisioner "remote-exec" {
    inline = [
      "echo -n ${join(",", var.icp-master)} > /opt/ibm/cluster/masterlist.txt",
      "echo -n ${join(",", var.icp-proxy)} > /opt/ibm/cluster/proxylist.txt",
      "echo -n ${join(",", var.icp-worker)} > /opt/ibm/cluster/workerlist.txt",
      "echo -n ${join(",", var.icp-management)} > /opt/ibm/cluster/managementlist.txt"
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
      "/tmp/icp-bootmaster-scripts/generate_hostsfiles.sh"
    ]
  }
}

# Boot node hook
resource "null_resource" "icp-preinstall-hook-stop-on-fail" {
  depends_on = ["null_resource.icp-generate-hosts-files"]
  count = "${var.on_hook_failure == "fail" ? 1 : 0}"

  # The first master is always the boot master where we run provisioning jobs from
  connection {
    host          = "${local.boot-node}"
    user          = "${var.ssh_user}"
    private_key   = "${local.ssh_key}"
    agent         = "${var.ssh_agent}"
    bastion_host  = "${var.bastion_host}"
  }

  # Run stage hook commands
  provisioner "remote-exec" {
    inline = [
      "${var.hooks["preinstall"]}"
    ]
    on_failure = "fail"
  }
}

################ CRISTIE FIX ################
# Local preinstall hook

## Cluster Pre-config hook
resource "null_resource" "icp-cluster-preconfig-hook" {
  count = "${contains(keys(var.hooks), "cluster-preconfig") ? var.cluster_size : 0}"

  connection {
      host          = "${element(local.icp-ips, count.index)}"
      user          = "${var.ssh_user}"
      private_key   = "${local.ssh_key}"
      agent         = "${var.ssh_agent}"
      bastion_host  = "${var.bastion_host}"
  }

  # Run cluster-preconfig commands
  provisioner "remote-exec" {
    inline = [
      "${var.hooks["cluster-preconfig"]}"
    ]
  }
}

## Cluster postconfig hook
resource "null_resource" "icp-cluster-postconfig-hook" {
  depends_on = ["null_resource.icp-cluster"]
  count = "${contains(keys(var.hooks), "cluster-postconfig") ? var.cluster_size : 0}"

  connection {
      host          = "${element(local.icp-ips, count.index)}"
      user          = "${var.ssh_user}"
      private_key   = "${local.ssh_key}"
      agent         = "${var.ssh_agent}"
      bastion_host  = "${var.bastion_host}"
  }

  # Run cluster-postconfig commands
  provisioner "remote-exec" {
    inline = [
      "${var.hooks["cluster-postconfig"]}"
    ]
  }
}

resource "null_resource" "icp-preinstall-hook" {
  depends_on = ["null_resource.icp-generate-hosts-files"]
  count = "${contains(keys(var.hooks), "preinstall") ? 1 : 0}"

  # The first master is always the boot master where we run provisioning jobs from
  connection {
    host          = "${local.boot-node}"
    user          = "${var.ssh_user}"
    private_key   = "${local.ssh_key}"
    agent         = "${var.ssh_agent}"
    bastion_host  = "${var.bastion_host}"
  }

  # Run stage hook commands
  provisioner "remote-exec" {
    inline = [
      "${var.hooks["preinstall"]}"
    ]
  }
}

resource "null_resource" "icp-boot-preconfig" {
  depends_on = ["null_resource.icp-cluster-postconfig-hook", "null_resource.icp-cluster"]
  count = "${contains(keys(var.hooks), "boot-preconfig") ? 1 : 0}"

  # The first master is always the boot master where we run provisioning jobs from
  connection {
    host          = "${local.boot-node}"
    user          = "${var.ssh_user}"
    private_key   = "${local.ssh_key}"
    agent         = "${var.ssh_agent}"
    bastion_host  = "${var.bastion_host}"
  }

  # Run stage hook commands
  provisioner "remote-exec" {
    inline = [
      "${var.hooks["boot-preconfig"]}"
    ]
  }
}


resource "null_resource" "local-preinstall-hook" {
  depends_on = ["null_resource.icp-preinstall-hook"]
  provisioner "local-exec" {
    command = "${var.hooks["local-preinstall"]}"
  }

}

################ CRISTIE FIX ################

resource "null_resource" "icp-preinstall-hook-continue-on-fail" {
  depends_on = ["null_resource.icp-generate-hosts-files"]
  count = "${var.on_hook_failure != "fail" ? 1 : 0}"

  # The first master is always the boot master where we run provisioning jobs from
  connection {
    host          = "${local.boot-node}"
    user          = "${var.ssh_user}"
    private_key   = "${local.ssh_key}"
    agent         = "${var.ssh_agent}"
    bastion_host  = "${var.bastion_host}"
  }

  # Run stage hook commands
  provisioner "remote-exec" {
    inline = [
      "${var.hooks["preinstall"]}"
    ]
    on_failure = "continue"
  }
}

# Local preinstall hook
resource "null_resource" "local-preinstall-hook-stop-on-fail" {
  depends_on = ["null_resource.icp-preinstall-hook"]
  count = "${var.on_hook_failure == "fail" ? 1 : 0}"

  provisioner "local-exec" {
    command = "${var.hooks["local-preinstall"]}"
    on_failure = "fail"
  }
}
resource "null_resource" "local-preinstall-hook-continue-on-fail" {
  depends_on = ["null_resource.icp-preinstall-hook"]
  count = "${var.on_hook_failure != "fail" ? 1 : 0}"

  provisioner "local-exec" {
    command = "${var.hooks["local-preinstall"]}"
    on_failure = "continue"
  }
}

# Start the installer
resource "null_resource" "icp-install" {
  depends_on = ["null_resource.local-preinstall-hook", "null_resource.icp-generate-hosts-files"]

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
      "/tmp/icp-bootmaster-scripts/start_install.sh ${var.icp-version} ${var.install-verbosity}"
    ]
  }
}

# Local postinstall hook
resource "null_resource" "local-postinstall-hook-stop-on-fail" {
  depends_on = ["null_resource.icp-install"]
  count = "${var.on_hook_failure == "fail" ? 1 : 0}"

  provisioner "local-exec" {
    command = "${var.hooks["local-postinstall"]}"
    on_failure = "fail"
  }
}
resource "null_resource" "local-postinstall-hook-continue-on-fail" {
  depends_on = ["null_resource.icp-install"]
  count = "${var.on_hook_failure != "fail" ? 1 : 0}"

  provisioner "local-exec" {
    command = "${var.hooks["local-postinstall"]}"
    on_failure = "continue"
  }
}

# Hook for Boot node
resource "null_resource" "icp-postinstall-hook-stop-on-fail" {
  depends_on = ["null_resource.icp-install"]
  count = "${var.on_hook_failure == "fail" ? 1 : 0}"

  # The first master is always the boot master where we run provisioning jobs from
  connection {
    host          = "${local.boot-node}"
    user          = "${var.ssh_user}"
    private_key   = "${local.ssh_key}"
    agent         = "${var.ssh_agent}"
    bastion_host  = "${var.bastion_host}"
  }

  # Run stage hook commands
  provisioner "remote-exec" {
    inline = [
      "${var.hooks["postinstall"]}"
    ]
    on_failure = "fail"
  }
}
resource "null_resource" "icp-postinstall-hook-continue-on-fail" {
  depends_on = ["null_resource.icp-install"]
  count = "${var.on_hook_failure != "fail" ? 1 : 0}"

  # The first master is always the boot master where we run provisioning jobs from
  connection {
    host          = "${local.boot-node}"
    user          = "${var.ssh_user}"
    private_key   = "${local.ssh_key}"
    agent         = "${var.ssh_agent}"
    bastion_host  = "${var.bastion_host}"
  }

  # Run stage hook commands
  provisioner "remote-exec" {
    inline = [
      "${var.hooks["postinstall"]}"
    ]
    on_failure = "continue"
  }
}

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
      "/tmp/icp-bootmaster-scripts/scaleworkers.sh ${var.icp-version}"
    ]
  }



}
