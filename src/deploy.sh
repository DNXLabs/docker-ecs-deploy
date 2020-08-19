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
if [[ -z "$HOSTEDZONE_NAME" ]];    then echo "---> ERROR: Missing variable HOSTEDZONE_NAME"; ERROR=1; fi
if [[ -z "$HOSTNAME" ]];           then echo "---> ERROR: Missing variable HOSTNAME"; ERROR=1; fi
if [[ -z "$HOSTNAME_BLUE" ]];      then echo "---> ERROR: Missing variable HOSTNAME_BLUE"; ERROR=1; fi
if [[ -z "$IMAGE_NAME" ]];         then echo "---> ERROR: Missing variable IMAGE_NAME"; ERROR=1; fi

if [[ "$ERROR" == "1" ]]; then exit 1; fi

echo "---> Creating/Updating Cloudformation Application Stack"
echo "--->    STACK_NAME: ecs-app-${CLUSTER_NAME}-${APP_NAME}"
echo "--->    AWS_DEFAULT_REGION: $AWS_DEFAULT_REGION"
echo "--->    APP_NAME: $APP_NAME"
echo "--->    CLUSTER_NAME: $CLUSTER_NAME"
echo "--->    HOSTNAME: $HOSTNAME"
echo "--->    HOSTNAME_BLUE: $HOSTNAME_BLUE"

# check if there's a stack with same name in rollback_complete status
aws cloudformation deploy \
  --template-file ./cf-service.yml \
  --stack-name ecs-app-${CLUSTER_NAME}-${APP_NAME} \
  --no-fail-on-empty-changeset \
  --capabilities CAPABILITY_IAM \
  --parameter-overrides \
    Name=$APP_NAME \
    ClusterName=${CLUSTER_NAME} \
    ContainerPort=${CONTAINER_PORT} \
    HealthCheckPath=${HEALTHCHECK_PATH-/} \
    HealthCheckGracePeriod=${HEALTHCHECK_GRACE_PERIOD-60} \
    HealthCheckTimeout=${HEALTHCHECK_TIMEOUT-5} \
    HealthCheckInterval=${HEALTHCHECK_INTERVAL-10} \
    DeregistrationDelay=${DEREGISTRATION_DELAY-30} \
    Autoscaling=${AUTOSCALING-true} \
    AutoscalingTargetValue=${AUTOSCALING_TARGET_VALUE-50} \
    AutoscalingMaxSize=${AUTOSCALING_MAX_SIZE-6} \
    AutoscalingMinSize=${AUTOSCALING_MIN_SIZE-1} \
    HostedZoneName=$HOSTEDZONE_NAME \
    Hostname=$HOSTNAME \
    HostnameBlue=$HOSTNAME_BLUE \
    PathPattern=${PATH_PATTERN-/*}
    # HostnameRedirects=${HOSTNAME_REDIRECTS-} \
    # CertificateArn=$CERTIFICATE_ARN \
if [[  -z "$DEPLOY_TIMEOUT" ]]; then
  echo "---> INFO: Deploy timeout set to default of 900 seconds"
else
  echo "---> INFO: Deploy timeout set to ${DEPLOY_TIMEOUT} seconds";
fi

DEPLOY_CONCURRENCY_MODE=${DEPLOY_CONCURRENCY_MODE:-fail}
if [[ "$DEPLOY_CONCURRENCY_MODE" == "wait" ]]
then
  echo "---> INFO: Deploy concurrency mode set to 'wait' a previous deployment to finish before continuing"
else
  echo "---> INFO: Deploy concurrency mode set to 'fail'"
fi

envsubst < task-definition.tpl.json > task-definition.json
echo "---> Task Definition"
cat task-definition.json

export TASK_ARN=$(aws ecs register-task-definition --cli-input-json file://./task-definition.json | jq --raw-output '.taskDefinition.taskDefinitionArn')

envsubst < app-spec.tpl.json > app-spec.json
echo "---> App-spec for CodeDeploy"
cat app-spec.json
echo
echo "---> Creating deployment with CodeDeploy"

set +e # disable bash exit on error

DEPLOY_TIMEOUT_PERIOD=0

while [ "${DEPLOYMENT_ID}" == "" ]
do
  if [ "$DEPLOY_TIMEOUT_PERIOD" -ge "${DEPLOY_TIMEOUT:-900}" ]; then
    echo "===> Timeout reached trying to create deployment. Exiting"
    exit 1
  fi

  DEPLOYMENT_ID=$(aws deploy create-deployment \
    --application-name $CLUSTER_NAME-$APP_NAME \
    --deployment-config-name CodeDeployDefault.ECSAllAtOnce \
    --deployment-group-name $CLUSTER_NAME-$APP_NAME \
    --description Deployment \
    --revision file://app-spec.json \
    --query="deploymentId" --output text)

  if [ $? -eq 255 ] && [ "${DEPLOY_CONCURRENCY_MODE}" == "fail" ]
  then
    # In case there is already a deployment in progress, script will fail  
    echo
    echo
    echo "===> Deployment already in progress for this application environment. Please approve or rollback current deployment before performing a new deployment"
    echo
    echo
    exit 1
  fi
  
  sleep 10 # Wait until deployment is created
  DEPLOY_TIMEOUT_PERIOD=$((DEPLOY_TIMEOUT_PERIOD + 10))
done

echo "---> For more info: https://$AWS_DEFAULT_REGION.console.aws.amazon.com/codesuite/codedeploy/deployments/$DEPLOYMENT_ID"

/work/tail-ecs-events.py &
TAIL_ECS_EVENTS_PID=$!

RET=0

while [ "$(aws deploy get-deployment --deployment-id $DEPLOYMENT_ID --query deploymentInfo.status --output text)" == "Created" ]
do
  sleep 1
done

echo "---> Deployment created!"

DEPLOY_TIMEOUT_PERIOD=0
DEPLOY_TIMEOUT_REACHED=0

while [ "$(aws deploy get-deployment --deployment-id $DEPLOYMENT_ID --query deploymentInfo.status --output text)" == "InProgress" ]
do
  if [ "$DEPLOY_TIMEOUT_PERIOD" -ge "${DEPLOY_TIMEOUT:-900}" ]; then
    echo "---> WARNING: Timeout reached. Rolling back deployment..."
    aws deploy stop-deployment --deployment-id $DEPLOYMENT_ID --auto-rollback-enabled
    DEPLOY_TIMEOUT_REACHED=1
  fi
  sleep 1
  DEPLOY_TIMEOUT_PERIOD=$((DEPLOY_TIMEOUT_PERIOD + 1))
done

TASK_SET_ID=$(aws ecs describe-services --cluster $CLUSTER_NAME --service $APP_NAME --query "services[0].taskSets[?status == 'ACTIVE'].id" --output text)
if [ "${TASK_SET_ID}" != "" ]; then
  echo "---> Task Set ID: $TASK_SET_ID"
fi

# Due the known issue on Codedeploy, CodeDeploy will fail the deployment if the ECS service is unhealthy/unstable for 5mins for replacement 
# taskset during the wait status, this 5mins is a non-configurable value as today.
# For the reason above we wait for 10 minutes before consider the deployment in ready status as successful

WAIT_PERIOD=0
MAX_WAIT=300 #$(aws ecs describe-services --cluster $CLUSTER_NAME --service $APP_NAME --query services[0].healthCheckGracePeriodSeconds --output text)
MAX_WAIT_BUFFER=60

echo "---> Waiting $((MAX_WAIT + MAX_WAIT_BUFFER)) seconds for tasks to stabilise"

while [ "$(aws deploy get-deployment --deployment-id $DEPLOYMENT_ID --query deploymentInfo.status --output text)" == "Ready" ]
do
  if [ "$WAIT_PERIOD" -ge "$((MAX_WAIT + MAX_WAIT_BUFFER))" ]; then
    break
  fi
  sleep 10
  WAIT_PERIOD=$((WAIT_PERIOD + 10))
done

DEPLOYMENT_STATUS=$(aws deploy get-deployment --deployment-id $DEPLOYMENT_ID --query deploymentInfo.status --output text)
echo "---> Deployment status: $DEPLOYMENT_STATUS"

if [ "$DEPLOYMENT_STATUS" == "Failed" ] || [ "$DEPLOYMENT_STATUS" == "Stopped" ]
then
  if [ "$TASK_SET_ID" != "" ]
  then
    TASK_ARN=$(aws ecs list-tasks --cluster $CLUSTER_NAME --desired-status STOPPED --started-by $TASK_SET_ID --query taskArns[0] --output text)
    if [ "${TASK_ARN}" != "None" ]; then
      echo "---> Displaying logs of STOPPED task: $TASK_ARN"
      /work/tail-task-logs.py $TASK_ARN
    fi
  fi
  RET=1
elif [ "$DEPLOYMENT_STATUS" == "Succeeded" ]
then
  RET=0
fi

if [ $RET -eq 0 ]; then
  echo "---> Completed!"
else
  if [ $DEPLOY_TIMEOUT_REACHED -eq 1 ]; then
    echo "---> Deploy timeout reached and rollback triggered."
  fi
  echo "---> ERROR: Deployment FAILED!"
fi

kill $TAIL_ECS_EVENTS_PID

exit $RET