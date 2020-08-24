#!/bin/bash

ERROR=0
if [[ -z "$AWS_DEFAULT_REGION" ]]; then echo "---> ERROR: Missing variable AWS_DEFAULT_REGION"; ERROR=1; fi
if [[ -z "$APP_NAME" ]];           then echo "---> ERROR: Missing variable APP_NAME"; ERROR=1; fi
if [[ -z "$CLUSTER_NAME" ]];       then echo "---> ERROR: Missing variable CLUSTER_NAME"; ERROR=1; fi
if [[ "$ERROR" == "1" ]]; then exit 1; fi

set -e

STACK_NAME="ecs-app-${CLUSTER_NAME}-${APP_NAME}"

COLOR_LIVE=$(aws cloudformation describe-stacks \
  --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[?OutputKey==`ColorLive`].OutputValue' --output text)

if [ "${COLOR_LIVE}" == "Green" ]; then COLOR_TEST="Blue"; else COLOR_TEST="Green"; fi

echo "---> Initiating Cutover For Application Stack"
echo "--->    STACK_NAME: ${STACK_NAME}"
echo "--->    AWS_DEFAULT_REGION: ${AWS_DEFAULT_REGION}"
echo "--->    APP_NAME: ${APP_NAME}"
echo "--->    CLUSTER_NAME: ${CLUSTER_NAME}"
echo "--->    COLOR_LIVE: ${COLOR_LIVE}"

TASK_SET_ID=$(aws cloudformation describe-stack-resource \
  --stack-name ecs-app-${CLUSTER_NAME}-${APP_NAME}-taskset-${COLOR_TEST} \
  --logical-resource-id EcsTaskSet \
  --query 'StackResourceDetail.PhysicalResourceId' --output text)
# result comes as 'cluster_name|service_name|ecs-svc/5174143321895914558', need to remove prefix
TASK_SET_ID=${TASK_SET_ID##*|}

echo "---> Cutover to new stack set: ${TASK_SET_ID} (${COLOR_TEST})"
aws ecs update-service-primary-task-set \
  --cluster ${CLUSTER_NAME} \
  --service ${APP_NAME} \
  --primary-task-set ${TASK_SET_ID}

aws cloudformation deploy \
  --template-file ./cf-service.yml \
  --stack-name ${STACK_NAME} \
  --no-fail-on-empty-changeset \
  --parameter-overrides \
    ColorLive=${COLOR_TEST} \
  --capabilities CAPABILITY_IAM

echo "---> Removing previous stack set, if exists (${COLOR_LIVE})"
aws cloudformation delete-stack --stack-name ecs-app-${CLUSTER_NAME}-${APP_NAME}-taskset-${COLOR_LIVE} || true

echo "---> Cutover COMPLETED"

exit 0