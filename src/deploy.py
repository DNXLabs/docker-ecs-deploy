#!/usr/bin/env python3

import os
import json
import time
from ecs import EcsClient
from codedeploy import DeployClient
from utils import validate_envs, json_template

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
launchtype = os.getenv('SERVICE_TYPE')
subnets = os.getenv('SUBNETS')
security_groups = os.getenv('SECURITY_GROUPS')
task_def_file_name = os.getenv('TPL_FILE_NAME', 'task-definition.tpl.json')
app_spec_file_name = os.getenv('APPSPEC_FILE_NAME', 'app-spec.tpl.json')
capacity_provider_strategy = os.getenv('CAPACITY_PROVIDER_STRATEGY')

# ----- Create task definition file -----
print('Step 2: Replace variables inside of %s \n' % task_def_file_name)

try:
    task_definition = json_template(task_def_file_name)
except:
    exit(1)

print('Task definition file: \n%s' % task_definition)
task_def = json.loads(task_definition)

# ----- Register task definition file -----
print('Step 3: Registering task definition \n')
task = EcsClient()

try:
    task.register_task_definition(task_def)
    print('Task definition arn: %s \n' % task.taskDefArn)
except Exception as err:
    print('Register task definition issue: %s' % err)
    exit(1)

# ----- Code Deploy -----
print('Step 4: Creating App Spec for CodeDeploy \n')

env_vars = dict(os.environ)
env_vars['TASK_ARN'] = task.taskDefArn
env_vars['CAPACITY_PROVIDER_STRATEGY'] = ''
if capacity_provider_strategy:
    env_vars['CAPACITY_PROVIDER_STRATEGY'] = ',\"CapacityProviderStrategy\":[\'%s\']' % capacity_provider_strategy

try:
    app_spec_tpl = json_template(app_spec_file_name, env_vars)
except:
    exit(1)

print('App spec file: \n%s' % app_spec_tpl)
app_spec = json.loads(app_spec_tpl)

# ----- Create Deployment -----
print('Step 5: Creating Deployment \n')
deploy = DeployClient()

application_name = '-'.join([cluster_name, app_name])
deployment_config_name = 'CodeDeployDefault.ECSAllAtOnce'
deployment_group  = application_name

try:
    deploy.list_deployments(application_name, deployment_group)
    if len(deploy.deployments) > 0:
        raise Exception('Deployment in progress: https://%s.console.aws.amazon.com/codesuite/codedeploy/deployments/%s' %
                        (aws_default_region, deploy.deployments[0]))
except Exception as err:
    print('Error: %s' % str(err))
    exit(1)

try:
    deploy.create_deployment(
        application_name, deployment_config_name, deployment_group, app_spec)
    print('Successfully created deployment: %s' % deploy.deploymentId)
    print('For more info, you can follow your deployment at: https://%s.console.aws.amazon.com/codesuite/codedeploy/deployments/%s \n' %
          (aws_default_region, deploy.deploymentId))
except:
    print('Deployment of application %s on deployment group %s failed' %
          (application_name, deployment_group))
    exit(1)

# ----- Monitor Deployment -----
print('Step 6: Deployment Overview \n')

print('Monitoring deployment %s for %s on deployment group %s' % (deploy.deploymentId, application_name, deployment_group))

while not hasattr(task, 'taskSetId'):
  # set task.taskSetId
  task.describe_services(cluster_name, app_name)
  time.sleep(2)
  
print('Task Set ID: %s \n' % task.taskSetId)
  
print('Monitoring ECS service events for cluster %s on service %s:\n' % (cluster_name, app_name))

deploy_timeout_period = 0
deploy_timeout = int(os.getenv('DEPLOYMENT_TIMEOUT', 900))

# deploy.status
deploy.get_deployment(deploy.deploymentId)

def stop_deploy(deployment_id):
    try:
        deploy.stop_deployment(deployment_id)
        print('Rollback deployment success')
    except:
        print('Rollback deployment failed')
    finally:
        exit(1)
    
while deploy.status in ['Created', 'InProgress', 'Queued']:
    # Tail logs from ECS service
    ecs_events = task.tail_ecs_events(cluster_name, app_name)
    for event in ecs_events:
      print('%s %s' % ('{0:%Y-%m-%d %H:%M:%S %z}'.format(event['createdAt']), event['message']))
    
    # Check if containers are being stoped
    last_task = task.list_tasks(cluster_name, task.taskSetId)
    if len(last_task['taskArns']) > 2:
        last_task_info = task.describe_tasks(cluster_name, last_task['taskArns'])
        last_task_status = last_task_info['tasks'][0]['lastStatus']
        last_task_reason = last_task_info['tasks'][0]['stoppedReason']
        
        if last_task_status == 'STOPPED':
            print('Containers are being stoped: %s' % last_task_reason)
            stop_deploy(deploy.deploymentId)
        
    # Rechead limit
    if deploy_timeout_period >= deploy_timeout:
        print('Deployment timeout: %s seconds' % deploy_timeout)
        stop_deploy(deploy.deploymentId)
        
    # Get status, increment limit and sleep
    deploy.get_deployment(deploy.deploymentId)
    deploy_timeout_period += 2
    time.sleep(2)

# Print Status
deployment_info = deploy.get_deployment(deploy.deploymentId)

print()
if deploy.status == "Ready":
    print('Deployment of application %s on deployment group %s ready and waiting for cutover' % (application_name, deployment_group))
    exit(0)
    
if deploy.status == "Succeeded":
    print('Deployment of application %s on deployment group %s succeeded' % (application_name, deployment_group))
    exit(0)

if deployment_info.get('deploymentInfo', {}).get('errorInformation'):
    print('Deployment failed: %s' % deployment_info.get('deploymentInfo', {}).get('errorInformation', {}).get('code'))
    print('Error: %s' %  deployment_info.get('deploymentInfo', {}).get('errorInformation', {}).get('message'))