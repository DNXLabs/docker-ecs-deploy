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

aws ecs run-task \
  --cluster $CLUSTER_NAME \
  --task-definition $TASK_ARN


/work/tail-ecs-events.py &
TAIL_PID=$!

RET=$?



if [ $RET -eq 0 ]; then
  echo "---> Deployment completed!"
else
  echo "---> ERROR: Deployment FAILED!"
fi

kill $TAIL_PID
exit $RET
