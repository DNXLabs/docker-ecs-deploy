import unittest
import os
import json

import deploy

class DeployTest(unittest.TestCase):
    def setUp(self):
        self.deploy = deploy.Deploy()
        os.environ['IMAGE_NAME'] = 'dnxlabs/docker-ecs'
        os.environ['DEFAULT_COMMAND'] = "\"ls -la\""
        os.environ['CPU'] = '1500'
        os.environ['MEMORY'] = '3000'
        os.environ['APP_NAME'] = 'test-app'
        os.environ['CONTAINER_PORT'] = '8080'
        os.environ['CLUSTER_NAME'] = 'test-cluster'
        os.environ['AWS_DEFAULT_REGION'] = 'ap-southeast-2'
        os.environ['AWS_ACCOUNT_ID'] = '1234567890'

    def test_create_task_definition(self):
        result = self.deploy.create_task_definition("../templates/task-definition.tpl-default.json")
        with open("./tests/task-definition-default.json", 'r') as f:
            expected = f.read()
        expected_json = json.loads(expected)
        self.assertEqual(result, expected_json)

    def test_create_app_spec(self):
        result = self.deploy.create_app_spec("../templates/app-spec.tpl.json")
        pass

    def test_upper(self):
        self.assertEqual('foo'.upper(), 'FOO')

if __name__ == '__main__':
    unittest.main()
