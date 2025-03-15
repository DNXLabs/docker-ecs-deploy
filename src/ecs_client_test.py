import unittest
import boto3
import os
from moto import mock_aws
from ecs_client import EcsClient


@mock_aws
class EcsClientTest(unittest.TestCase):
    def setUp(self):
        os.environ["MOTO_ECS_SERVICE_RUNNING"] = "3"
        os.environ["AWS_ACCESS_KEY_ID"] = "testing"
        os.environ["AWS_SECRET_ACCESS_KEY"] = "testing"
        os.environ["AWS_SECURITY_TOKEN"] = "testing"
        os.environ["AWS_SESSION_TOKEN"] = "testing"
        os.environ["AWS_DEFAULT_REGION"] = "us-east-1"

        self.cluster_name = "test-cluster"
        self.app_name = "test-app"
        ecs_client = boto3.client("ecs")
        ecs_client.create_cluster(clusterName=self.cluster_name)
        ecs_client.register_task_definition(
            family=self.app_name,
            containerDefinitions=[
                {
                    "name": "task",
                    "image": "123456789012.dkr.ecr.us-west-2.amazonaws.com/derp:live",
                    "cpu": 1024,
                    "memory": 2048,
                    "memoryReservation": 2048,
                    "portMappings": [
                        {"containerPort": 8000, "hostPort": 8000, "protocol": "tcp"}
                    ],
                    "essential": True,
                    "mountPoints": [],
                    "volumesFrom": [],
                    "linuxParameters": {"initProcessEnabled": True},
                    "logConfiguration": {"logDriver": "json-file"},
                }
            ],
        )
        ecs_client.create_service(
            cluster=self.cluster_name,
            serviceName=self.app_name,
            taskDefinition=self.app_name,
            desiredCount=1,
        )

        self.client = EcsClient()

    def test_describe_service(self):
        result = self.client.describe_service(self.cluster_name, self.app_name)
        self.assertEqual(len(result["services"]), 1)
        self.assertEqual(
            result["services"][0]["serviceArn"],
            "arn:aws:ecs:us-east-1:123456789012:service/test-cluster/test-app",
        )
        self.assertEqual(result["services"][0]["serviceName"], self.app_name)
        self.assertEqual(
            result["services"][0]["clusterArn"],
            "arn:aws:ecs:us-east-1:123456789012:cluster/test-cluster",
        )

    def test_get_deployment_id(self):
        result = self.client.get_deployment_id(self.cluster_name, self.app_name)
        expected = self.client.get_service(self.cluster_name, self.app_name)
        self.assertEqual(result, expected["services"][0]["deployments"][0]["id"])


if __name__ == "__main__":
    unittest.main()
