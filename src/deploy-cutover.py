#!/usr/bin/env python3

import os
from codedeploy import DeployClient
from utils import validate_envs

# ----- Check variables -----
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

# Fetch deployment 'Ready' status and cutover
deploy = DeployClient()

application_name = '-'.join([cluster_name, app_name])
deployment_group  = application_name

try:
    deploy.list_deployments(application_name, deployment_group, ['Ready'])    
    deploy.continue_deployment(deploy.deployments[0])
    print('---> Cutover engaged!')
except:
    print('---> ERROR: Cutover FAILED!')
    exit(1)
    