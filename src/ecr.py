#!/usr/bin/env python3

import boto3

class EcrClient(object):
    def __init__(self):
        self.boto = boto3.client('ecr')
        
    def describe_image_scan_findings(self, ecr_account, app_name, build_version):
        return self.boto.describe_image_scan_findings(
            registryId=ecr_account,
            repositoryName=app_name,
            imageId={
                'imageTag': build_version
            }
        )
    