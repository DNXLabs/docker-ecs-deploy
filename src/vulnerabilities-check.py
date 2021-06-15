#!/usr/bin/env python3

import os
import boto3
import json
import sys

build_version=os.environ['BUILD_VERSION']
severity=list(os.environ['SEVERITY'].split(' '))
app_name=os.environ['APP_NAME']
ecr_account=os.environ['ECR_ACCOUNT']

client = boto3.client('ecr')
response = client.describe_image_scan_findings(
    registryId=ecr_account,
    repositoryName=app_name,
    imageId={
        'imageTag': build_version
    },
)

print("---> Checking for vulnerabilities")

if len(response['imageScanFindings']['findings']) == 0:
    print("---> No vulnerabilities found")
else:
    vuln_counter=0
    for level in severity:
        vuln_report=response
        if not vuln_report['imageScanFindings']['findings'][0]['severity'] == level:
            print("---> The report doesn't have any %s vulnerabilities" %level)
        else: 
            if vuln_report['imageScanFindings']['findingSeverityCounts'][level] > 0:
                report = vuln_report['imageScanFindings']['findingSeverityCounts'][level]
                print("---> There is/are %s vulnerability(ies) level %s" %(report,level))
                print("---> Packages: %s" %vuln_report['imageScanFindings']['findings'][0]['attributes'])
            vuln_counter+=report
    
    if vuln_counter > 0:
        print("---> ERROR: Docker image contains %s vulnerability(ies)" %vuln_counter)
        exit(1)
    else:
        print("---> No vulnerabilities found")
