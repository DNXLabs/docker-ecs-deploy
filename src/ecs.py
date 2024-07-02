#!/usr/bin/env python3

import boto3
from typing import List

LAUNCH_TYPE_FARGATE = "FARGATE"


class EcsClient(object):
    def __init__(self):
        self.boto = boto3.client("ecs")
        self.logs = boto3.client("logs")
        self._last_event = None
        self._log_next_token = None

    def update_service(
        self, cluster_name, app_name, task_definition, force_deployment=False
    ):
        return self.boto.update_service(
            cluster=cluster_name,
            service=app_name,
            taskDefinition=task_definition,
            forceNewDeployment=force_deployment,
        )

    def describe_services(self, cluster_name, app_name):
        result = self.boto.describe_services(cluster=cluster_name, services=[app_name])

        if "taskSets" in result["services"][0]:
            for taskSet in result["services"][0]["taskSets"]:
                if taskSet["status"] == "ACTIVE":
                    self.taskSetId = taskSet["id"]

        if "deployments" in result["services"][0]:
            for deployment in result["services"][0]["deployments"]:
                if deployment["status"] == "PRIMARY":
                    self.ecsDeployId = deployment["id"]

        return result

    def register_task_definition(self, task_definition):
        result = self.boto.register_task_definition(**task_definition)
        self.taskDefArn = result["taskDefinition"]["taskDefinitionArn"]
        return result

    def describe_task_definition(self, task_definition):
        result = self.boto.describe_task_definition(taskDefinition=task_definition)
        self.taskDefArn = result["taskDefinition"]["taskDefinitionArn"]
        return result

    def list_tasks(self, cluster_name: str, started_by, desired_status="STOPPED"):
        return self.boto.list_tasks(
            cluster=cluster_name, startedBy=started_by, desiredStatus=desired_status
        )

    def describe_tasks(self, cluster_name: str, task_arns):
        result = self.boto.describe_tasks(cluster=cluster_name, tasks=task_arns)
        self.status = result["tasks"][0]["lastStatus"]
        return result

    def run_task(
        self,
        cluster_name: str,
        task_definition,
        launchtype: str,
        subnets: List[str],
        security_groups: List[str],
        container_overrides: object,
    ):
        if launchtype == LAUNCH_TYPE_FARGATE:
            if not subnets or not security_groups:
                msg = (
                    "At least one subnet and one security "
                    "group definition are required "
                    "for launch type FARGATE"
                )
                raise Exception(msg)

            network_configuration = {
                "awsvpcConfiguration": {
                    "subnets": subnets,
                    "securityGroups": security_groups,
                    "assignPublicIp": "DISABLED",
                }
            }

            result = self.boto.run_task(
                cluster=cluster_name,
                taskDefinition=task_definition,
                launchType=launchtype,
                networkConfiguration=network_configuration,
                overrides=container_overrides,
            )

        else:
            result = self.boto.run_task(
                cluster=cluster_name,
                taskDefinition=task_definition,
                overrides=container_overrides,
            )

        self.taskArn = result["tasks"][0]["taskArn"]
        self.taskId = self.taskArn.split("/")[-1]
        self.status = result["tasks"][0]["lastStatus"]
        return result

    def describe_log_streams(self, log_group_name):
        return self.logs.describe_log_streams(
            logGroupName=log_group_name,
            orderBy="LastEventTime",
            descending=True,
            limit=1,
        )

    def get_log_events(self, log_args):
        return self.logs.get_log_events(**log_args)

    def tail_log_events(self, log_group_name, log_stream_name):
        log_args = {
            "logGroupName": log_group_name,
            "logStreamName": log_stream_name,
            "startFromHead": True,
        }

        if self._log_next_token:
            log_args["nextToken"] = self._log_next_token

        log_stream_events = self.get_log_events(log_args)

        self._log_next_token = log_stream_events["nextForwardToken"]
        return log_stream_events["events"]

    def tail_ecs_events(self, cluster_name, app_name):
        get_events = self.describe_services(cluster_name, app_name)
        events = get_events["services"][0]["events"]
        events_collected = []

        for event in events:
            if not self._last_event or event["id"] == self._last_event:
                break
            events_collected.insert(0, event)

        self._last_event = events[0]["id"]
        return events_collected
