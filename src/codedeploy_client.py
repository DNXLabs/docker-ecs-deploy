import os
import boto3
import json

from utils import json_template


class CodeDeployClient(object):
    def __init__(self):
        self.boto = boto3.client("codedeploy")

    def create_app_spec(
        self, file_name: str, task_arn: str, capacity_provider_strategy=None
    ):
        env_vars = dict(os.environ)
        env_vars["TASK_ARN"] = task_arn
        env_vars["CAPACITY_PROVIDER_STRATEGY"] = ""
        if capacity_provider_strategy:
            env_vars["CAPACITY_PROVIDER_STRATEGY"] = (
                ',\\"CapacityProviderStrategy\\":[\\"%s\\"]'
                % capacity_provider_strategy
            )
        try:
            app_spec_tpl = json_template(file_name, env_vars)
        except Exception as err:
            print("Error: Templating app spec :", err)
            exit(1)
        print("App spec file content: \n%s" % app_spec_tpl)
        return json.loads(app_spec_tpl)

    def list_deployments(
        self, application_name, deployment_group, statuses=["InProgress", "Ready"]
    ):
        result = self.boto.list_deployments(
            applicationName=application_name,
            deploymentGroupName=deployment_group,
            includeOnlyStatuses=statuses,
        )
        self.deployments = result["deployments"]
        return result

    def create_deployment(
        self, application_name, deployment_config_name, deployment_group, revision
    ):
        result = self.boto.create_deployment(
            applicationName=application_name,
            deploymentGroupName=deployment_group,
            deploymentConfigName=deployment_config_name,
            description="Deployment",
            revision=revision,
        )
        self.deploymentId = result["deploymentId"]
        return result

    def continue_deployment(self, deployment_id):
        return self.boto.continue_deployment(
            deploymentId=deployment_id, deploymentWaitType="READY_WAIT"
        )

    def get_deployment(self, deployment_id):
        result = self.boto.get_deployment(deploymentId=deployment_id)
        self.status = result["deploymentInfo"]["status"]
        return result

    def stop_deployment(self, deployment_id, auto_rollback=True):
        return self.boto.stop_deployment(
            deploymentId=deployment_id, autoRollbackEnabled=auto_rollback
        )
