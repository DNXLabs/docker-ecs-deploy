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
if [[ -z "$HOSTEDZONE_NAME" ]];    then echo "---> ERROR: Missing variable HOSTEDZONE_NAME"; ERROR=1; fi
if [[ -z "$HOSTNAME" ]];           then echo "---> ERROR: Missing variable HOSTNAME"; ERROR=1; fi
if [[ -z "$HOSTNAME_BLUE" ]];      then echo "---> ERROR: Missing variable HOSTNAME_BLUE"; ERROR=1; fi
if [[ -z "$CERTIFICATE_ARN" ]];    then echo "---> ERROR: Missing variable CERTIFICATE_ARN"; ERROR=1; fi

if [[ "$ERROR" == "1" ]]; then exit 1; fi

echo "---> Creating/Updating Cloudformation Application Stack"
echo "--->    STACK_NAME: ecs-app-${CLUSTER_NAME}-${APP_NAME}-${REVISION-latest}"
echo "--->    AWS_DEFAULT_REGION: $AWS_DEFAULT_REGION"
echo "--->    APP_NAME: $APP_NAME"
echo "--->    CLUSTER_NAME: $CLUSTER_NAME"

aws cloudformation deploy \
  --template-file ./cf-service-common.yml \
  --stack-name ecs-app-${CLUSTER_NAME}-${APP_NAME} \
  --parameter-overrides \
    Name=$APP_NAME \
    ClusterName=$CLUSTER_NAME \
    HostedZoneName=$HOSTEDZONE_NAME \
    Hostname=$HOSTNAME \
    HostnameBlue=$HOSTNAME_BLUE \
    CertificateArn=$CERTIFICATE_ARN \
    HostnameRedirects=${HOSTNAME_REDIRECTS-} \

echo "---> Creating/Updating Cloudformation Application Stack"
echo "--->    STACK_NAME: ecs-app-${CLUSTER_NAME}-${APP_NAME}-${REVISION-latest}"
echo "--->    AWS_DEFAULT_REGION: $AWS_DEFAULT_REGION"
echo "--->    APP_NAME: $APP_NAME"
echo "--->    CLUSTER_NAME: $CLUSTER_NAME"
echo "--->    HOSTNAME: $HOSTNAME"
echo "--->    HOSTNAME_BLUE: $HOSTNAME_BLUE"

aws cloudformation deploy \
  --template-file ./cf-service.yml \
  --stack-name ecs-app-${CLUSTER_NAME}-${APP_NAME}-${REVISION-latest} \
  --parameter-overrides \
    Name=$APP_NAME \
    ClusterName=$CLUSTER_NAME \
    ContainerPort=$CONTAINER_PORT \
    HostnameRedirects=${HOSTNAME_REDIRECTS-} \
    RulePriority=$RULE_PRIORITY \
    Revision=${REVISION-latest} \
    HealthCheckPath=${HEALTHCHECK_PATH-/} \
    HealthCheckGracePeriod=${HEALTHCHECK_GRACE_PERIOD-60} \
    HealthCheckTimeout=${HEALTHCHECK_TIMEOUT-5} \
    HealthCheckInterval=${HEALTHCHECK_INTERVAL-10} \
    DeregistrationDelay=${DEREGISTRATION_DELAY-30} \
    Autoscaling=${AUTOSCALING-Enable} \
    AutoscalingTargetValue=${AUTOSCALING_TARGET_VALUE-50} \
    AutoscalingMaxSize=${AUTOSCALING_MAX_SIZE-6} \
    AutoscalingMinSize=${AUTOSCALING_MIN_SIZE-1} \

envsubst < task-definition.tpl.json > task-definition.json
echo "---> Task Definition"
cat task-definition.json

export TASK_ARN=$(aws ecs register-task-definition --cli-input-json file://./task-definition.json | jq --raw-output '.taskDefinition.taskDefinitionArn')
echo "---> Registered ECS Task Definition"
echo "--->    TASK_ARN: $TASK_ARN"

# TODO:
# - Create a task set in the ecs service create above
# - Wait for healthcheck to pass and finish deployment
# - Cutover

DEPLOYMENT_PID=$!

sleep 5 # Wait for deployment to be created so we can fetch DEPLOYMENT_ID next

DEPLOYMENT_ID=$(aws deploy list-deployments --application-name=$CLUSTER_NAME-$APP_NAME --deployment-group=$CLUSTER_NAME-$APP_NAME --max-items=1 --query="deployments[0]" --output=text | head -n 1)



echo "---> Waiting for Deployment ..."

wait $DEPLOYMENT_PID
RET=$?

if [ $RET -eq 0 ]; then
  echo "---> Deployment completed!"
else
  echo "---> ERROR: Deployment FAILED!"
fi

exit $RET
