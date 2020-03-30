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

# In case there is already a deployment in progress, script will fail  

if [ $? -eq 255 ]; then
    echo "Deployment already in progress. Please approve current deployment before performing a new deployment"
    exit 1
else

sleep 5 # Wait for deployment to be created

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

# Due the known issue on Codedeploy, CodeDeploy will fail the deployment if the ECS service is unhealthy/unstable for 5mins for replacement 
# taskset during the wait status, this 5mins is a non-configurable value as today.
# For the reason above we wait for 10 minutes before consider the deployment in ready status as successful

RET=$?

wait_period=0

while true
do
    echo "Time Now: `date +%H:%M:%S`"
    echo "Sleeping for 30 seconds"
    # Here 600 is 600 seconds i.e. 10 minutes * 60 = 600 sec
    wait_period=$(($wait_period+30))
    #if [ $wait_period -gt 600 ] && [ "$(aws deploy get-deployment --deployment-id $DEPLOYMENT_ID --query deploymentInfo.status --output text)" == "Ready" ]; then
    if [ $wait_period -gt 600 ]; then
         echo "The script successfully ran for 10 minutes, exiting now.."
             if ! [ "$(aws deploy get-deployment --deployment-id $DEPLOYMENT_ID --query deploymentInfo.status --output text)" == "Ready" ]; then
               #echo "Deployment not successful"
               RET=1
               break
             elif [ "$(aws deploy get-deployment --deployment-id $DEPLOYMENT_ID --query deploymentInfo.status --output text)" == "Ready" ]; then
               #echo "Deployed successfully!"
               RET=0
               break
             fi
         break
      else
         sleep 30
      fi
done

#RET=$?

if [ $RET -eq 0 ]; then
  echo "---> Deployment completed!"
else
  echo "---> ERROR: Deployment FAILED!"
fi

kill $TAIL_PID

exit $RET

fi
