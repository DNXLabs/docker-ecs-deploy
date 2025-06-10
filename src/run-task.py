#!/usr/bin/env python3

import os
import json
import random
import time
from ecs import EcsClient
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
launchtype = os.getenv('SERVICE_TYPE')
subnets = os.getenv('SUBNETS')
security_groups = os.getenv('SECURITY_GROUPS')
task_def_file_name = os.getenv('TPL_FILE_NAME', 'task-definition.tpl.json')
env_vars = dict(os.environ)

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

# ----- Run task -----
print('Step 4: Running task')

if subnets:
    subnets = subnets.split(",")
if security_groups:
    security_groups = security_groups.split(",")

try:
    task.run_task(cluster_name, task.taskDefArn,
                  launchtype, subnets, security_groups)
except Exception as err:
    print(err)
    exit(1)

task_time = 0
while task.status not in ['RUNNING', 'STOPPED']:
    try:
        running_task = task.describe_tasks(cluster_name, [task.taskArn])
        sleep = (2 * random.uniform(0, 3))
        task_time = task_time + int(sleep)
        time.sleep(sleep)
    except:
        print("Error get runnning task")
        exit(1)
else:
    print('Provisioning time: %s seconds' % task_time)

print('\n======== RUNNING TASK ========')
print('CLUSTER_NAME: %s' % cluster_name)
print('APP_NAME:     %s' % app_name)
print('TASK_DEF_ARN: %s' % task.taskDefArn)
print('TASK_ARN:     %s' % task.taskArn)

log_msg = None
last_logs = None

print('\n======== TASK LOGS ========')
while True:
    try:
        log_group_name = task_def['containerDefinitions'][0]['logConfiguration']['options']['awslogs-group']
        log_prefix = task_def['containerDefinitions'][0]['logConfiguration']['options']['awslogs-stream-prefix']
        log_stream_name = '/'.join([log_prefix, app_name, task.taskId])
        
        log_events = task.tail_log_events(log_group_name, log_stream_name)
        for event in log_events:
            print(event['message'])
    except:
        if not log_msg:
            log_msg = 'No logs sent to CloudWatch'
            print(log_msg)
    finally:
        running_task = task.describe_tasks(cluster_name, [task.taskArn])
        sleep = (2 * random.uniform(0, 3))
        time.sleep(sleep)
        
    if last_logs:
        break

    if task.status == 'STOPPED':
        last_logs = True
        continue

print('\n======== TASK STOPPED ========')
all_tasks = running_task['tasks']
for task_item in all_tasks:
    print('Task ID:        %s' % task_item['taskArn'].split('/')[-1])
    print('Task ARN:       %s' % task_item['taskArn'])
    print('Service Name:   %s' % app_name)
    print('Cluster Name:   %s' % cluster_name)
    if 'startedAt' in task_item:
        print('Started at:     %s' % task_item['startedAt'])
    print('Stopped at:     %s' % task_item['stoppedAt'])
    print('Stopped Reason: %s' % task_item['stoppedReason'])
    if 'stopCode' in task_item:
        print('Stop Code:      %s' % task_item['stopCode'])
    for container in task_item['containers']:
        if 'exitCode' in container:
            print('Exit code for container %s: %s' % (container['name'], container['exitCode']))
            if container['exitCode'] != 0:
                print('Container %s in task %s failed with exit code %s' % (container['name'], task_item['taskArn'], container['exitCode']))
                exit(container['exitCode'])
        if 'reason' in container:
            print('Reason for container %s: %s' % (container['name'], container['reason']))

print('All tasks completed successfully')
exit(0)
