import os, sys, json, ConfigParser

hgfile = '/tmp/icp-host-groups.json'
hostfile = None
ipfile = '/tmp/cluster-ips.txt'

supplied_cluster_dir = ""
if len(sys.argv) > 1:
  supplied_cluster_dir = sys.argv[1]
  hostfile = os.path.join(supplied_cluster_dir,"/hosts")
  if not os.path.isdir(supplied_cluster_dir):
    hostfile = None

if hostfile is None:
    raise Exception("Invalid cluster directory provided: {}".format(supplied_cluster_dir))

# Exit if we don't need to do anything
if os.stat(hgfile).st_size == 0:
  exit(1)

# Load the hostgroup info from file if provided
with open(hgfile, 'r') as stream:
  hostgroups = json.load(stream)

# Create the hostfile
hf = open(hostfile, 'w')
h = ConfigParser.ConfigParser(allow_no_value=True)

ips = []
for group in hostgroups.keys():
  h.add_section(group)
  for host in hostgroups[group]:
    ips.append(host)
    h.set(group, host)

h.write(hf)
hf.close()

# Write a list of ip addresses, removing duplicates
i = open(ipfile, 'w')
i.write(",".join(list(set(ips))))
i.close()
