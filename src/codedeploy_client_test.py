import unittest
import boto3
from moto import mock_aws

from codedeploy_client import CodeDeployClient


class CodeDeployClientTest(unittest.TestCase):
    def setUp(self):
        self.codedeploy_client = CodeDeployClient()

    @mock_aws
    def test_create_deployment(self):
        application_name = "test_application"
        deployment_config_name = ""
        deployment_group = ""
        revision = ""
        client = boto3.client("codedeploy")
        result = client.create_deployment(
            applicationName=application_name,
            deploymentGroupName=deployment_group,
            deploymentConfigName=deployment_config_name,
            description="Deployment",
            revision=revision,
        )
        print(result)
        # result = self.codedeploy_client.create_deployment(application_name, deployment_config_name, deployment_group, revision)


if __name__ == "__main__":
    unittest.main()
