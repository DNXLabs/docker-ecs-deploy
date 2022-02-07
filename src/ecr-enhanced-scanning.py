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

countResponse = len(response['imageScanFindings']['enhancedFindings'])

if countResponse == 0:
    print("---> No vulnerabilities found")
else: 
    print("---> Checking for %s vulnerabilities" %(severity))
    for level in severity:
        print ("\n" + "---> List of " + level + " packages")
        level_counter = 0
        for vuln_counter in range(0,countResponse):
            vuln_report=response
            if vuln_report['imageScanFindings']['enhancedFindings'][vuln_counter]['severity'] == level:
                print("%s: Package %s:%s" %(level,vuln_report['imageScanFindings']['enhancedFindings'][vuln_counter]['packageVulnerabilityDetails']['vulnerablePackages'][0]['name'],vuln_report['imageScanFindings']['enhancedFindings'][vuln_counter]['packageVulnerabilityDetails']['vulnerablePackages'][0]['version']))
                level_counter+=1

        if level_counter > 0:
            print("--> Total of %s vulnerabilities %s" %(level,level_counter))
        else:
            print("--> %s vulnerabilities have not been found" %(level))
            
    print("\n" + "---> WARNING: Overview of %s container image vulnerability(ies)" %(app_name))
    print(vuln_report['imageScanFindings']['findingSeverityCounts'])