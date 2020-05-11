#!/bin/bash -e

if [[ ! -f "task-definition.tpl.json" ]]; then
    echo "---> ERROR: task-definition.tpl.json not found"
    exit 0
fi

ERROR=0
if [[ -z "$AWS_DEFAULT_REGION" ]]; then echo "---> ERROR: Missing variable AWS_DEFAULT_REGION"; ERROR=1; fi
if [[ -z "$APP_NAME" ]];           then echo "---> ERROR: Missing variable APP_NAME"; ERROR=1; fi
if [[ -z "$CLUSTER_NAME" ]];       then echo "---> ERROR: Missing variable CLUSTER_NAME"; ERROR=1; fi
if [[ -z "$IMAGE_NAME" ]];         then echo "---> ERROR: Missing variable IMAGE_NAME"; ERROR=1; fi
if [[ "$ERROR" == "1" ]]; then exit 1; fi

envsubst < task-definition.tpl.json > task-definition.json
echo "---> Task Definition"
cat task-definition.json

echo ""
echo "---> Registering Task Definition"

# Update the ECS service to use the updated Task version

TASK_ARN=$(aws ecs register-task-definition \
  --cli-input-json file://task-definition.json \
  --query="taskDefinition.taskDefinitionArn" \
  --output=text)

echo "---> Executing  ECS Task"
echo "       CLUSTER_NAME: ${CLUSTER_NAME}"
echo "       APP_NAME: ${APP_NAME}"
echo "       TASK_ARN: ${TASK_ARN}"

TASK_ID=$(aws ecs run-task \
  --cluster $CLUSTER_NAME \
  --task-definition $TASK_ARN \
  --query="tasks[0].taskArn" \
  --output=text)

# sleep 5

TASK_STATUS=$(aws ecs describe-tasks \
  --tasks $TASK_ID \
  --cluster $CLUSTER_NAME \
  --query="tasks[0].lastStatus" \
  --output=text)
echo "---> Task ID $TASK_ID"
echo "---> Task Status $TASK_STATUS"

./tail-task-logs.py $TASK_ID

# Discovery the Container Retunr status after the run-task
CONTAINER_EXIT_CODE=$(aws ecs describe-tasks \
  --tasks $TASK_ID \
  --cluster $CLUSTER_NAME \
  --query="tasks[0].containers[0].exitCode" \
  --output=text)
echo "---> Task Exit Code $CONTAINER_EXIT_CODE"  
RET=$CONTAINER_EXIT_CODE


if [ $RET -eq 0 ]; then
  echo "---> TaskStatus completed!"
else
  echo "---> ERROR: TaskStatus FAILED!"
fi

exit $RET
