#!/bin/bash -e

ERROR=0
if [[ -z "$AWS_DEFAULT_REGION" ]]; then echo "---> ERROR: Missing variable AWS_DEFAULT_REGION"; ERROR=1; fi
if [[ -z "$APP_NAME" ]];           then echo "---> ERROR: Missing variable APP_NAME"; ERROR=1; fi
if [[ -z "$CLUSTER_NAME" ]];       then echo "---> ERROR: Missing variable CLUSTER_NAME"; ERROR=1; fi
if [[ -z "$BUILD_VERSION" ]];      then echo "---> ERROR: Missing variable BUILD_VERSION"; ERROR=1; fi
if [[ -z "$SEVERITY" ]];           then echo "---> ERROR: Missing variable SEVERITY"; ERROR=1; fi
if [[ "$ERROR" == "1" ]];          then exit 1; fi

echo "---> Checking for vulnerabilites"

VULN_COUNTER=0

for LEVEL in $SEVERITY; do
    VULN_REPORT=$(aws ecr describe-image-scan-findings --repository-name $APP_NAME --image-id imageTag=$BUILD_VERSION --region $AWS_DEFAULT_REGION | python3 -c "import sys, json; print(json.load(sys.stdin)['imageScanFindings']['findingSeverityCounts']['$LEVEL'])")

    if [[ $VULN_REPORT -gt 0 ]]; then
        echo "---> There are $VULN_REPORT vulnerabilities level $LEVEL"
    fi
    VULN_COUNTER=$(($VULN_COUNTER+$VULN_REPORT))
done

if [[ $VULN_COUNTER -gt 0 ]]; then
    echo "---> ERROR: Docker image contains $VULN_COUNTER vulnerabilites"
    exit 1
else
    echo "---> No vulnerabilities found"
fi