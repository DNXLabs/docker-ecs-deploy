#!/usr/bin/env python3

import os
import json
import time
from ecs import EcsClient
from utils import validate_envs, json_template

# ----- Check variables -----
print("Step 1: Checking environment variables \n")

req_vars = ["CLUSTER_NAME", "APP_NAME", "AWS_DEFAULT_REGION"]

try:
    validate_envs(req_vars)
except:
    exit(1)

cluster_name = os.getenv("CLUSTER_NAME")
app_name = os.getenv("APP_NAME")
aws_default_region = os.getenv("AWS_DEFAULT_REGION")
task_def_file_name = os.getenv("TPL_FILE_NAME", "task-definition.tpl.json")

# ----- Create task definition file -----
print("Step 2: Replace variables inside of %s \n" % task_def_file_name)

try:
    task_definition = json_template(task_def_file_name)
except:
    exit(1)

print("Task definition file: \n%s" % task_definition)
task_def = json.loads(task_definition)

# ----- Register task definition file -----
print("Step 3: Registering task definition")
task = EcsClient()

try:
    task.register_task_definition(task_def)
    print("Task definition arn: %s \n" % task.taskDefArn)
except Exception as err:
    print("Register task definition issue: %s" % err)
    exit(1)

# ----- Create Deployment -----
print("Step 4: Creating Deployment")

active_task = task.describe_services(cluster_name, app_name)
active_task_def = active_task["services"][0]["taskDefinition"]

try:
    task.update_service(cluster_name, app_name, task.taskDefArn)
except Exception as err:
    print("Deployment FAILED!")
    print("ERROR: %s" % str(err).split(": ")[1])
    exit(1)

deployment = task.describe_services(cluster_name, app_name)
print("ECS dpeloyment: %s \n" % task.ecsDeployId)

# ----- Monitor Deployment -----
print("Step 5: Deployment Overview")

print(
    "Monitoring ECS service events for cluster %s on service %s:\n"
    % (cluster_name, app_name)
)

ecs_deploy = list(
    filter(lambda x: x["status"] == "PRIMARY",
           deployment["services"][0]["deployments"])
)
ecs_deploy_status = ecs_deploy[0]["rolloutState"]

deploy_timeout_period = 0
deploy_timeout = int(os.getenv("DEPLOYMENT_TIMEOUT", 900))


def rollback():
    try:
        task.update_service(cluster_name, app_name, active_task_def, True)
        print("Rollback deployment success")
    except:
        print("Rollback deployment failed")
    finally:
        exit(1)


while ecs_deploy_status == "IN_PROGRESS":
    # Tail logs from ECS service
    ecs_events = task.tail_ecs_events(cluster_name, app_name)
    for event in ecs_events:
        print(
            "%s %s"
            % ("{0:%Y-%m-%d %H:%M:%S %z}".format(event["createdAt"]), event["message"])
        )

    # Check if containers are being stoped
    last_task = task.list_tasks(cluster_name, task.ecsDeployId)
    if len(last_task["taskArns"]) > 2:
        last_task_info = task.describe_tasks(
            cluster_name, last_task["taskArns"])
        last_task_status = last_task_info["tasks"][0]["lastStatus"]
        last_task_reason = last_task_info["tasks"][0]["stoppedReason"]
        if "reason" in last_task_info["tasks"][0]["containers"][0]:
            last_task_reason = "%s \n%s" % (
                last_task_reason,
                last_task_info["tasks"][0]["containers"][0]["reason"],
            )

        if last_task_status == "STOPPED":
            print("Containers are being stoped: %s" % last_task_reason)
            rollback()

    # Rechead limit
    if deploy_timeout_period >= deploy_timeout:
        print("Deployment timeout: %s seconds" % deploy_timeout)
        rollback()

    # Get status, increment limit and sleep
    deployment = task.describe_services(cluster_name, app_name)
    ecs_deploy = list(
        filter(
            lambda x: x["status"] == "PRIMARY", deployment["services"][0]["deployments"]
        )
    )
    ecs_deploy_status = ecs_deploy[0]["rolloutState"]
    deploy_timeout_period += 2
    time.sleep(2)

# Print Status
print("\nDeployment completed:")
print("CLUSTER_NAME: %s" % cluster_name)
print("APP_NAME:     %s" % app_name)
print("TASK_ARN:     %s" % task.taskDefArn)
