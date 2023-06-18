#!/usr/bin/env python3

import json
import os
from utils import validate_envs, json_template
from ecs import EcsClient

# ----- Check variables -----
print('Step 1: Checking environment variables \n')

req_vars = [
    'CLUSTER_NAME',
    'APP_NAME',
    'AWS_DEFAULT_REGION'
]

try:
    validate_envs(req_vars)
except:
    exit(1)

cluster_name = os.getenv('CLUSTER_NAME')
app_name = os.getenv('APP_NAME')
aws_default_region = os.getenv('AWS_DEFAULT_REGION')
task_def_file_name = os.getenv('TPL_FILE_NAME', 'task-definition.tpl.json')

# ----- Create task definition file -----
print('Step 2: Replace variables inside of %s \n' % task_def_file_name)

try:
    task_definition = json_template(task_def_file_name)
except:
    exit(1)

print('Task definition file: \n%s' % task_definition)
task_def = json.loads(task_definition)

# ----- Register task definition file -----
print('Step 3: Registering task definition')
task = EcsClient()

try:
    task.register_task_definition(task_def)
    print('Task definition arn: %s \n' % task.taskDefArn)
except Exception as err:
    print('Register task definition issue: %s' % err)
    exit(1)
