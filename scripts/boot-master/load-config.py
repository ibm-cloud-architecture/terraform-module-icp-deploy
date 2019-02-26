#!/bin/env python
import os, sys, yaml, json, getpass
config_file = '/tmp/config.yaml'
config_items = '/tmp/items-config.yaml'
config_orig = None

# Load config from config file if provided
if os.stat(config_file).st_size == 0:
  config_f = {}
else:
  with open(config_file, 'r') as stream:
    try:
        config_f = yaml.load(stream)
    except yaml.YAMLError as exc:
        print(exc)


# Load config items if provided
with open(config_items, 'r') as stream:
  config_i = json.load(stream)

supplied_cluster_dir = ""
if len(sys.argv) > 1:
  supplied_cluster_dir = sys.argv[1]
  config_orig = os.path.join(supplied_cluster_dir,"/config.yaml")
  if not os.path.exists(config_orig):
    config_orig = None

if config_orig is None:
    raise Exception("Invalid cluster directory provided: {}".format(supplied_cluster_dir))

# If merging changes, start by loading default values. Else start with empty dict
if len(sys.argv) > 2:
  if sys.argv[2] == "merge":
    with open(config_orig, 'r') as stream:
      try:
        config_o = yaml.load(stream)
      except yaml.YAMLError as exc:
        print(exc)
  else:
    config_o = {}


# First accept any changes from supplied config file
config_o.update(config_f)

# Second accept any changes from supplied config items
config_o.update(config_i)

# Automatically add the ansible_become if it does not exist, and if we are not root
if not 'ansible_user' in config_o and getpass.getuser() != 'root':
  config_o['ansible_user'] = getpass.getuser()
  config_o['ansible_become'] = True

# Detect if a default admin password has been provided by user, set the terraform generated password if not
if ((not 'default_admin_password' in config_f and
    not 'default_admin_password' in config_i) or
        config_o['default_admin_password'] == ''):
    if len(sys.argv) > 3:
      config_o['default_admin_password'] = sys.argv[3]
    else:
      raise Exception("default_admin_password not set and none provided from terraform")

# to handle terraform bug regarding booleans, we must parse dictionaries to find strings "true" or "false"
# and convert them to booleans.
# Also skip blanks as yaml.safe_dump dumps them as '' which ansible installer does not like
def parsedict(d):

  t_dict = {}
  if type(d) is dict:
    for key, value in d.iteritems():

      # Handle nested dictionaries
      if type(value) is dict:
        t_dict[key] = parsedict(value)

      elif type(value) is str or type(value) is unicode:
        if value.lower() == 'true':
          t_dict[key] = True
        elif value.lower() == 'false':
          t_dict[key] = False
        elif value == '':
          # Skip blanks
          continue
        else:
          t_dict[key] = value

      else:
        # We will not look for booleans in lists and such things
        t_dict[key] = value

  return t_dict


# Write the new configuration
with open(config_orig, 'w') as of:
  yaml.safe_dump(parsedict(config_o), of, explicit_start=True, default_flow_style = False)
