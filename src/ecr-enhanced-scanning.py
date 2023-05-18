#!/usr/bin/env python3

import os
from ecr import EcrClient
from utils import validate_envs

# ----- Check variables -----
req_vars = [
    'BUILD_VERSION',
    'APP_NAME',
    'AWS_DEFAULT_REGION',
    'ECR_ACCOUNT'
]

try:
    validate_envs(req_vars)
except:
    exit(1)

build_version = os.getenv('BUILD_VERSION')
severity = list(os.getenv('SEVERITY', 'CRITICAL HIGH').split(' '))
app_name = os.getenv('APP_NAME')
ecr_account = os.getenv('ECR_ACCOUNT')

try:
    ecr = EcrClient()
    response = ecr.describe_image_scan_findings(
        ecr_account, app_name, build_version)
    if 'enhancedFindings' not in response['imageScanFindings']:
        raise Exception('ECR Enhanced Findings not enabled')
    countResponse = len(response['imageScanFindings']['enhancedFindings'])
except Exception as err:
    print('ERROR: %s' % str(err))
    exit(1)

if countResponse == 0:
    print("---> No vulnerabilities found")
else:
    print("---> Checking for %s vulnerabilities" % (severity))
    for level in severity:
        print("\n" + "---> List of " + level + " packages")
        level_counter = 0
        for vuln_counter in range(0, countResponse):
            vuln_report = response
            if vuln_report['imageScanFindings']['enhancedFindings'][vuln_counter]['severity'] == level:
                print("%s: Package %s:%s" % (level, vuln_report['imageScanFindings']['enhancedFindings'][vuln_counter]['packageVulnerabilityDetails']['vulnerablePackages']
                      [0]['name'], vuln_report['imageScanFindings']['enhancedFindings'][vuln_counter]['packageVulnerabilityDetails']['vulnerablePackages'][0]['version']))
                level_counter += 1

        if level_counter > 0:
            print("--> Total of %s vulnerabilities %s" %
                  (level, level_counter))
        else:
            print("--> %s vulnerabilities have not been found" % (level))

    print("\n" + "---> WARNING: Overview of %s container image vulnerability(ies)" % (app_name))
    print(vuln_report['imageScanFindings']['findingSeverityCounts'])
