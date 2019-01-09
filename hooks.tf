#######
## Hooks to run before any other module actions
#######

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

#######
## Hooks to run after cluster prereqs install
#######

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
  depends_on = ["null_resource.icp-cluster-postconfig-hook-continue-on-fail", "null_resource.icp-cluster-postconfig-hook-stop-on-fail", "null_resource.icp-cluster"]
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
  depends_on = ["null_resource.icp-cluster-postconfig-hook-stop-on-fail", "null_resource.icp-cluster-postconfig-hook-continue-on-fail", "null_resource.icp-cluster"]
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

#######
## Hooks to run before installation
#######
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
  depends_on = ["null_resource.icp-preinstall-hook-continue-on-fail", "null_resource.icp-preinstall-hook-stop-on-fail"]
  count = "${var.on_hook_failure == "fail" ? 1 : 0}"

  provisioner "local-exec" {
    command = "${var.local-hooks["local-preinstall"]}"
    on_failure = "fail"
  }
}
resource "null_resource" "local-preinstall-hook-continue-on-fail" {
  depends_on = ["null_resource.icp-preinstall-hook-continue-on-fail", "null_resource.icp-preinstall-hook-stop-on-fail"]
  count = "${var.on_hook_failure != "fail" ? 1 : 0}"

  provisioner "local-exec" {
    command = "${var.local-hooks["local-preinstall"]}"
    on_failure = "continue"
  }
}


# Local postinstall hook
resource "null_resource" "local-postinstall-hook-stop-on-fail" {
  depends_on = ["null_resource.icp-install"]
  count = "${var.on_hook_failure == "fail" ? 1 : 0}"

  provisioner "local-exec" {
    command = "${var.local-hooks["local-postinstall"]}"
    on_failure = "fail"
  }
}
resource "null_resource" "local-postinstall-hook-continue-on-fail" {
  depends_on = ["null_resource.icp-install"]
  count = "${var.on_hook_failure != "fail" ? 1 : 0}"

  provisioner "local-exec" {
    command = "${var.local-hooks["local-postinstall"]}"
    on_failure = "continue"
  }
}

#######
## Hooks to run after installation complete
#######

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
