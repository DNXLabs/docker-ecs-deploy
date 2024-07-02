#!/usr/bin/env python3

import json
import os
from string import Template


def validate_envs(req_vars):
    missing = set(req_vars) - set(os.environ)
    if missing:
        print("Environment variables not set: %s" % missing)
        raise
    return True


def validate_json(json_data):
    try:
        json.loads(json_data)
        return True
    except ValueError as err:
        print("JSON not valide: %s" % err)


def json_template(json_template: str, env_vars=os.environ):
    try:
        json_file = open(json_template)
        data = json_file.read()
    except:
        print("File %s not found" % json_template)

    try:
        template = Template(data).substitute(env_vars)
    except KeyError as err:
        print("Missing variable %s" % str(err))
        exit(1)
    except Exception as err:
        print(f"Error substituting variables. Error: '{err}'")
        exit(1)

    try:
        validate_json(template)
    except Exception as err:
        print(f"Error validating JSON. Error: '{err}'")

    return template


#   "command": [ "sh", "-c", "export DD_AGENT_HOST=$(curl http://169.254.169.254/latest/meta-data/local-ipv4); ${COMMAND}" ],
