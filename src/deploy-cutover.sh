#!/bin/bash -e

ERROR=0
if [[ -z "$AWS_DEFAULT_REGION" ]]; then echo "---> ERROR: Missing variable AWS_DEFAULT_REGION"; ERROR=1; fi
if [[ -z "$APP_NAME" ]];           then echo "---> ERROR: Missing variable APP_NAME"; ERROR=1; fi
if [[ -z "$CLUSTER_NAME" ]];       then echo "---> ERROR: Missing variable CLUSTER_NAME"; ERROR=1; fi
if [[ "$ERROR" == "1" ]]; then exit 1; fi

# Fetch deployment ID pending cutover to the green(new) enviroment
DEPLOYMENT_ID=$(aws deploy list-deployments --application-name=$CLUSTER_NAME-$APP_NAME --deployment-group=$CLUSTER_NAME-$APP_NAME --max-items=1 --query="deployments[0]" --output=text | head -n 1)

aws deploy continue-deployment --deployment-id $DEPLOYMENT_ID --deployment-wait-type "READY_WAIT"

RET=$?

if [ $RET -eq 0 ]; then
  echo "---> Cutover engaged!"
else
  echo "---> ERROR: Cutover FAILED!"
fi

exit $RET
