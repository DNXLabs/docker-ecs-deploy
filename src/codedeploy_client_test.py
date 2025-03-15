import unittest
import json
import os

from codedeploy_client import CodeDeployClient


class CodeDeployClientTest(unittest.TestCase):
    def setUp(self):
        os.environ["APP_NAME"] = "test-app"
        os.environ["CONTAINER_PORT"] = "8080"
        self.codedeploy_client = CodeDeployClient()
        # self.deploy = Deploy()

    def test_create_app_spec_should_success_with_capacity_provider_strategy(self):
        task_def_arn = "arn:aws:1234567890:asdf"
        capacity_provider_strategy = "asdfasdf"
        result = self.codedeploy_client.create_app_spec(
            "../templates/app-spec.tpl.json", task_def_arn, capacity_provider_strategy
        )
        with open("./tests/app-spec-with-capacity-provider-strategy.json", "r") as f:
            expected_json = f.read()
        expected = json.loads(expected_json)
        self.assertEqual(result, expected)

    def test_create_app_spec_should_success_without_capacity_provider_strategy(self):
        task_def_arn = "arn:aws:1234567890:asdf"
        result = self.codedeploy_client.create_app_spec(
            "../templates/app-spec.tpl.json", task_def_arn
        )
        with open("./tests/app-spec-without-capacity-provider-strategy.json", "r") as f:
            expected_json = f.read()
        expected = json.loads(expected_json)
        self.assertEqual(result, expected)


if __name__ == "__main__":
    unittest.main()
