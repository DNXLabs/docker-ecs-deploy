#!/bin/bash

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

if [[  -z "$DEPLOY_TIMEOUT" ]]; then
  echo "---> INFO: Deploy timeout set to default of 900 seconds"
else
  echo "---> INFO: Deploy timeout set to ${DEPLOY_TIMEOUT} seconds";
fi

STACK_NAME="ecs-app-${CLUSTER_NAME}-${APP_NAME}"

echo "---> Creating/Updating Cloudformation Application Stack"
echo "--->    STACK_NAME: ${STACK_NAME}"
echo "--->    AWS_DEFAULT_REGION: ${AWS_DEFAULT_REGION}"
echo "--->    APP_NAME: ${APP_NAME}"
echo "--->    CLUSTER_NAME: ${CLUSTER_NAME}"

# check if there's a stack with same name in rollback_complete status
aws cloudformation deploy \
  --template-file ./cf-service.yml \
  --stack-name ${STACK_NAME} \
  --no-fail-on-empty-changeset \
  --parameter-overrides \
    Name=$APP_NAME \
    ClusterName=${CLUSTER_NAME} \
    HealthCheckPath=${HEALTHCHECK_PATH-/} \
    HealthCheckTimeout=${HEALTHCHECK_TIMEOUT-5} \
    HealthCheckInterval=${HEALTHCHECK_INTERVAL-10} \
    DeregistrationDelay=${DEREGISTRATION_DELAY-30} \
    Autoscaling=${AUTOSCALING-false} \
    AutoscalingTargetValue=${AUTOSCALING_TARGET_VALUE-50} \
    AutoscalingMaxSize=${AUTOSCALING_MAX_SIZE-8} \
    AutoscalingMinSize=${AUTOSCALING_MIN_SIZE-2} \
    HostedZoneName=${HOSTEDZONE_NAME-} \
    Hostname=${APP_HOSTNAME-} \
    HostnameCreate=${HOSTNAME_CREATE-false} \
    PathPattern=${PATH_PATTERN-/*} \
    LogRetentionDays=${LOG_RETENTION_DAYS-90} \
  --capabilities CAPABILITY_IAM

if [ $? -eq 255 ]; then
  aws cloudformation describe-stack-events \
    --stack-name ${STACK_NAME} \
    --max-items 20 \
    --query 'StackEvents[*].[ResourceStatus,LogicalResourceId,ResourceStatusReason]' \
    --output text
  echo "---> ERROR: Failed to deploy ECS Service stack. Check Cloudformation events above"
  exit 255
fi

COLOR_LIVE=$(aws cloudformation describe-stacks \
  --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[?OutputKey==`ColorLive`].OutputValue' --output text)

echo "---> Color Live: ${COLOR_LIVE}"

if [ "${COLOR_LIVE}" == "Green" ]; then COLOR_TEST="Blue"; else COLOR_TEST="Green"; fi

envsubst < task-definition.tpl.json > task-definition.json
echo "---> Task Definition:"
cat task-definition.json

export TASK_DEFINITION_ARN=$(aws ecs register-task-definition --cli-input-json file://./task-definition.json | jq --raw-output '.taskDefinition.taskDefinitionArn')
echo "---> Task Definition ARN: ${TASK_DEFINITION_ARN}"

STACK_NAME_TASKSET="ecs-app-${CLUSTER_NAME}-${APP_NAME}-task-${COLOR_TEST}"

echo "---> Creating/Updating Cloudformation Application TaskSet on Test Listener Stack"
echo "--->    STACK_NAME: ${STACK_NAME_TASKSET}"
echo "--->    AWS_DEFAULT_REGION: ${AWS_DEFAULT_REGION}"
echo "--->    APP_NAME: ${APP_NAME}"
echo "--->    CLUSTER_NAME: ${CLUSTER_NAME}"
echo "--->    COLOR: ${COLOR_TEST}"

aws cloudformation deploy \
  --template-file ./cf-service-taskset.yml \
  --stack-name ${STACK_NAME_TASKSET} \
  --no-fail-on-empty-changeset \
  --parameter-overrides \
    Name=${APP_NAME} \
    ClusterName=${CLUSTER_NAME} \
    TaskDefinitionArn=${TASK_DEFINITION_ARN} \
    ContainerPort=${CONTAINER_PORT} \
    Color=${COLOR_TEST} \
  --capabilities CAPABILITY_IAM &

sleep 30

TASK_SET_ID=$(aws cloudformation describe-stack-resource \
  --stack-name ${STACK_NAME_TASKSET} \
  --logical-resource-id EcsTaskSet \
  --query 'StackResourceDetail.PhysicalResourceId' --output text)
# result comes as 'cluster_name|service_name|ecs-svc/5174143321895914558', need to remove prefix
TASK_SET_ID=${TASK_SET_ID##*|} 

echo "---> Task Set created: ${TASK_SET_ID}"

DEPLOY_TIMEOUT_PERIOD=0

while [ "$(aws ecs describe-task-sets --cluster ${CLUSTER_NAME} --service ${APP_NAME} --task-sets ${TASK_SET_ID} --output text --query 'taskSets[0].stabilityStatus')" != "STEADY_STATE" ]
do
  if [ "$DEPLOY_TIMEOUT_PERIOD" -ge "${DEPLOY_TIMEOUT:-900}" ]; then
    echo "---> ERROR: Timeout reached. Rolling back deployment..."
    aws cloudformation cancel-update-stack --stack-name ${STACK_NAME_TASKSET} || true
    aws cloudformation delete-stack --stack-name ${STACK_NAME_TASKSET}
    echo "     Rollback complete"

    TASK_ARN=$(aws ecs list-tasks --cluster $CLUSTER_NAME --desired-status STOPPED --started-by ${TASK_SET_ID} --query taskArns[0] --output text)
    if [ "${TASK_ARN}" != "None" ]; then
      echo "---> Displaying logs of STOPPED task: $TASK_ARN"
      /work/tail-task-logs.py $TASK_ARN
    fi
    echo "---> Deployment FAILED"
    exit 1
  fi
  sleep 1
  DEPLOY_TIMEOUT_PERIOD=$((DEPLOY_TIMEOUT_PERIOD + 1))
done

echo "---> Deployment COMPLETED to Test Listener, ready for cutover"

exit 0