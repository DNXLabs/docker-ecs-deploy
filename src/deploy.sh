#!/bin/bash -e

if [[ ! -f "task-definition.tpl.json" ]]; then
    echo "---> ERROR: task-definition.tpl.json not found"
    exit 0
fi

ERROR=0
if [[ -z "$AWS_DEFAULT_REGION" ]]; then echo "---> ERROR: Missing variable AWS_DEFAULT_REGION"; ERROR=1; fi
if [[ -z "$APP_NAME" ]];           then echo "---> ERROR: Missing variable APP_NAME"; ERROR=1; fi
if [[ -z "$CLUSTER_NAME" ]];       then echo "---> ERROR: Missing variable CLUSTER_NAME"; ERROR=1; fi
if [[ -z "$CONTAINER_PORT" ]];     then echo "---> ERROR: Missing variable CONTAINER_PORT"; ERROR=1; fi
if [[ -z "$IMAGE_NAME" ]];         then echo "---> ERROR: Missing variable IMAGE_NAME"; ERROR=1; fi
if [[ "$ERROR" == "1" ]]; then exit 1; fi

envsubst < task-definition.tpl.json > task-definition.json
echo "---> Task Definition"
cat task-definition.json

export TASK_ARN=$(aws ecs register-task-definition --cli-input-json file://./task-definition.json | jq --raw-output '.taskDefinition.taskDefinitionArn')
# export TASK_ARN=TASK_ARN_PLACEHOLDER

envsubst < app-spec.tpl.json > app-spec.json
echo
echo "---> App-spec for CodeDeploy"
cat app-spec.json

echo
echo "---> Creating deployment with CodeDeploy"

set +e # disable bash exit on error

# Update the ECS service to use the updated Task version
# aws ecs deploy \
#   --service $APP_NAME \
#   --task-definition ./task-definition.json \
#   --cluster $CLUSTER_NAME \
#   --codedeploy-appspec ./app-spec.json \
#   --codedeploy-application $CLUSTER_NAME-$APP_NAME \
#   --codedeploy-deployment-group $CLUSTER_NAME-$APP_NAME &

# # Update the ECS service to use the updated Task version
DEPLOYMENT_ID=$(aws deploy create-deployment \
  --application-name $CLUSTER_NAME-$APP_NAME \
  --deployment-config-name CodeDeployDefault.ECSAllAtOnce \
  --deployment-group-name $CLUSTER_NAME-$APP_NAME \
  --description Deployment \
  --revision file://app-spec.json \
  --query="deploymentId" --output text)

# sleep 5 # Wait for deployment to be created so we can fetch DEPLOYMENT_ID next

# DEPLOYMENT_ID=$(aws deploy list-deployments --application-name=$CLUSTER_NAME-$APP_NAME --deployment-group=$CLUSTER_NAME-$APP_NAME --max-items=1 --query="deployments[0]" --output=text | head -n 1)

echo "---> For more info: https://$AWS_DEFAULT_REGION.console.aws.amazon.com/codesuite/codedeploy/deployments/$DEPLOYMENT_ID"

/work/tail-ecs-events.py &
TAIL_PID=$!

while [ "$(aws deploy get-deployment --deployment-id $DEPLOYMENT_ID --query deploymentInfo.status --output text)" == "Created" ]
do
  sleep 1
done

echo "---> Deployment created!"

while [ "$(aws deploy get-deployment --deployment-id $DEPLOYMENT_ID --query deploymentInfo.status --output text)" == "InProgress" ]
do
  sleep 1
done

# aws deploy wait deployment-successful --deployment-id $DEPLOYMENT_ID

RET=$?

if [ $RET -eq 0 ]; then
  echo "---> Deployment completed!"
else
  echo "---> ERROR: Deployment FAILED!"
fi

kill $TAIL_PID

exit $RET
