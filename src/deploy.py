import os
import json
import time
from ecs_client import EcsClient
from codedeploy_client import CodeDeployClient
from utils import validate_envs, json_template


class Deploy(object):
    def __init__(self):
        self.name = "Deploy"
        self.required_vars = ["CLUSTER_NAME", "APP_NAME", "AWS_DEFAULT_REGION"]
        self.debug = True
        self.cluster_name = os.getenv("CLUSTER_NAME")
        self.app_name = os.getenv("APP_NAME")
        self.aws_default_region = os.getenv("AWS_DEFAULT_REGION")
        self.launchtype = os.getenv("SERVICE_TYPE")
        self.subnets = os.getenv("SUBNETS")
        self.security_groups = os.getenv("SECURITY_GROUPS")
        self.task_def_file_name = os.getenv("TPL_FILE_NAME", "task-definition.tpl.json")
        self.app_spec_file_name = os.getenv("APPSPEC_FILE_NAME", "app-spec.tpl.json")
        self.capacity_provider_strategy = os.getenv("CAPACITY_PROVIDER_STRATEGY")

        self.taskSetId = None

        self.ecs_client = EcsClient()
        self.codedeploy_client = CodeDeployClient()

    def create_task_definition(self, file_name: str):
        try:
            task_definition = json_template(file_name)
        except Exception as err:
            print("Error: Templating task definition: ", err)
            exit(1)
        print("Task definition file: \n%s" % task_definition)
        return json.loads(task_definition)

    def run(self):
        print("Step 1: Validating environment variables \n")
        try:
            validate_envs(self.required_vars)
        except Exception as err:
            print("Error: Validating environment variables: ", err)
            exit(1)

        print("Step 2: Replace variables inside of %s \n" % self.task_def_file_name)
        task_def = self.create_task_definition(self.task_def_file_name)

        print("Step 3: Registering task definition \n")
        try:
            self.ecs_client.register_task_definition(task_def)
            print("Task definition arn: %s \n" % self.ecs_client.taskDefArn)
        except Exception as err:
            print("Error: Register task definition: ", err)
            exit(1)

        print("Step 4: Creating App Spec for CodeDeploy \n")
        task_arn = self.ecs_client.taskDefArn
        app_spec = self.codedeploy_client.create_app_spec(
            self.app_spec_file_name, task_arn, self.capacity_provider_strategy
        )

        print("Step 5: Creating Deployment \n")
        application_name = "-".join([self.cluster_name, self.app_name])
        deployment_config_name = "CodeDeployDefault.ECSAllAtOnce"
        deployment_group = application_name

        try:
            self.codedeploy_client.list_deployments(application_name, deployment_group)
            if len(self.codedeploy_client.deployments) > 0:
                raise Exception(
                    "Deployment in progress: https://%s.console.aws.amazon.com/codesuite/codedeploy/deployments/%s"
                    % (self.aws_default_region, self.codedeploy_client.deployments[0])
                )
        except Exception as err:
            print("Error: Listing deployments failed: %s" % str(err))
            exit(1)

        try:
            self.codedeploy_client.create_deployment(
                application_name, deployment_config_name, deployment_group, app_spec
            )
            print(
                "Successfully created deployment: %s"
                % self.codedeploy_client.deploymentId
            )
            print(
                "For more info, you can follow your deployment at: https://%s.console.aws.amazon.com/codesuite/codedeploy/deployments/%s \n"
                % (self.aws_default_region, self.codedeploy_client.deploymentId)
            )
        except Exception as err:
            print(
                "Error: Deployment of application %s on deployment group %s failed: %s"
                % (application_name, deployment_group, err)
            )
            exit(1)

        print("Step 6: Deployment Overview \n")
        print(
            "Monitoring deployment %s for %s on deployment group %s"
            % (self.codedeploy_client.deploymentId, application_name, deployment_group)
        )
        while not hasattr(self.ecs_client, "taskSetId"):
            self.ecs_client.describe_services(self.cluster_name, self.app_name)
            time.sleep(2)
        print("Task Set ID: %s \n" % self.ecs_client.taskSetId)
        print(
            "Monitoring ECS service events for cluster %s on service %s:\n"
            % (self.cluster_name, self.app_name)
        )

        deploy_timeout_period = 0
        deploy_timeout = int(os.getenv("DEPLOYMENT_TIMEOUT", 900))

        self.codedeploy_client.get_deployment(self.codedeploy_client.deploymentId)

        def stop_deploy(deployment_id):
            try:
                self.codedeploy_client.stop_deployment(deployment_id)
                print("Rollback deployment success")
            except:
                print("Rollback deployment failed")
            finally:
                exit(1)

        while self.codedeploy_client.status in ["Created", "InProgress", "Queued"]:
            # Tail logs from ECS service
            ecs_events = self.ecs_client.tail_ecs_events(
                self.cluster_name, self.app_name
            )
            for event in ecs_events:
                print(
                    "%s %s"
                    % (
                        "{0:%Y-%m-%d %H:%M:%S %z}".format(event["createdAt"]),
                        event["message"],
                    )
                )

            # Check if containers are being stoped
            last_task = self.ecs_client.list_tasks(
                self.cluster_name, self.ecs_client.taskSetId
            )
            if len(last_task["taskArns"]) > 2:
                last_task_info = self.ecs_client.describe_tasks(
                    self.cluster_name, last_task["taskArns"]
                )
                last_task_status = last_task_info["tasks"][0]["lastStatus"]
                last_task_reason = last_task_info["tasks"][0]["stoppedReason"]

                if last_task_status == "STOPPED":
                    print("Containers are being stoped: %s" % last_task_reason)
                    stop_deploy(self.codedeploy_client.deploymentId)

            # Rechead limit
            if deploy_timeout_period >= deploy_timeout:
                print("Deployment timeout: %s seconds" % deploy_timeout)
                stop_deploy(self.codedeploy_client.deploymentId)

            # Get status, increment limit and sleep
            self.codedeploy_client.get_deployment(self.codedeploy_client.deploymentId)
            deploy_timeout_period += 2
            time.sleep(2)

        deployment_info = deploy.get_deployment(deploy.deploymentId)
        print()
        if deploy.status == "Ready":
            print(
                "Deployment of application %s on deployment group %s ready and waiting for cutover"
                % (application_name, deployment_group)
            )
            exit(0)

        if deploy.status == "Succeeded":
            print(
                "Deployment of application %s on deployment group %s succeeded"
                % (application_name, deployment_group)
            )
            exit(0)

        if deployment_info.get("deploymentInfo", {}).get("errorInformation"):
            print(
                "Deployment failed: %s"
                % deployment_info.get("deploymentInfo", {})
                .get("errorInformation", {})
                .get("code")
            )
            print(
                "Error: %s"
                % deployment_info.get("deploymentInfo", {})
                .get("errorInformation", {})
                .get("message")
            )
            exit(1)


if __name__ == "__main__":
    deploy = Deploy()
    deploy.run()
