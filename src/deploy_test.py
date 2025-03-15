import unittest
import os
import json

import deploy

class DeployTest(unittest.TestCase):
    def setUp(self):
        os.environ['IMAGE_NAME'] = 'dnxlabs/docker-ecs'
        os.environ['DEFAULT_COMMAND'] = "\"ls -la\""
        os.environ['CPU'] = '1500'
        os.environ['MEMORY'] = '3000'
        os.environ['APP_NAME'] = 'test-app'
        os.environ['CONTAINER_PORT'] = '8080'
        os.environ['CLUSTER_NAME'] = 'test-cluster'
        os.environ['AWS_DEFAULT_REGION'] = 'ap-southeast-2'
        os.environ['AWS_ACCOUNT_ID'] = '1234567890'
        self.deploy = deploy.Deploy()

    def test_create_task_definition(self):
        result = self.deploy.create_task_definition("../templates/task-definition.tpl-default.json")
        with open("./tests/task-definition-default.json", 'r') as f:
            expected_json = f.read()
        expected = json.loads(expected_json)
        self.assertEqual(result, expected)

    def test_create_app_spec_should_success_with_capacity_provider_strategy(self):
        task_def_arn = "arn:aws:1234567890:asdf"
        self.deploy.capacity_provider_strategy = "asdfasdf"
        result = self.deploy.create_app_spec("../templates/app-spec.tpl.json", task_def_arn)
        with open("./tests/app-spec-with-capacity-provider-strategy.json", "r") as f:
            expected_json = f.read()
        expected = json.loads(expected_json)
        self.assertEqual(result, expected)

    def test_create_app_spec_should_success_without_capacity_provider_strategy(self):
        task_def_arn = "arn:aws:1234567890:asdf"
        result = self.deploy.create_app_spec("../templates/app-spec.tpl.json", task_def_arn)
        with open("./tests/app-spec-without-capacity-provider-strategy.json", "r") as f:
            expected_json = f.read()
        expected = json.loads(expected_json)
        self.assertEqual(result, expected)

if __name__ == '__main__':
    unittest.main()

