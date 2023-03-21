#!/usr/bin/env python3

import boto3

class DeployClient(object):
    def __init__(self):
        self.boto = boto3.client(u'codedeploy')

    def list_deployments(self, application_name, deployment_group, statuses=['InProgress', 'Ready']):    
        result = self.boto.list_deployments(
            applicationName=application_name,
            deploymentGroupName=deployment_group,
            includeOnlyStatuses=statuses
        )
        self.deployments = result['deployments']
        return result

    def create_deployment(self, application_name, deployment_config_name, deployment_group, revision):
        result = self.boto.create_deployment(
            applicationName=application_name,
            deploymentGroupName=deployment_group,
            deploymentConfigName=deployment_config_name,
            description='Deployment',
            revision=revision
        )
        self.deploymentId = result['deploymentId']
        return result
    
    def continue_deployment(self, deployment_id):
        return self.boto.continue_deployment(
            deploymentId=deployment_id,
            deploymentWaitType='READY_WAIT'
        )
    
    def get_deployment(self, deployment_id):
        result = self.boto.get_deployment(deploymentId=deployment_id)
        self.status = result['deploymentInfo']['status']
        return result
    
    def stop_deployment(self, deployment_id, auto_rollback=True):
        return self.boto.stop_deployment(
            deploymentId=deployment_id,
            autoRollbackEnabled=auto_rollback
        )
