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
if [[ -z "$PATH_PATTERN" ]];       then echo "---> ERROR: Missing variable PATH_PATTERN"; ERROR=1; fi
if [[ -z "$RULE_PRIORITY" ]];      then echo "---> ERROR: Missing variable RULE_PRIORITY"; ERROR=1; fi

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
  --parameter-overrides \
    Name=$APP_NAME \
    ClusterName=${CLUSTER_NAME} \
    ContainerPort=${CONTAINER_PORT} \
    RulePriority=${RULE_PRIORITY} \
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


envsubst < task-definition.tpl.json > task-definition.json
echo "---> Task Definition"
cat task-definition.json

export TASK_ARN=TASK_ARN_PLACEHOLDER

envsubst < app-spec.tpl.json > app-spec.json
echo "---> App-spec for CodeDeploy"
cat app-spec.json

echo "---> Creating deployment with CodeDeploy"

set +e # disable bash exit on error

# Update the ECS service to use the updated Task version
aws ecs deploy \
  --service $APP_NAME \
  --task-definition ./task-definition.json \
  --cluster $CLUSTER_NAME \
  --codedeploy-appspec ./app-spec.json \
  --codedeploy-application $CLUSTER_NAME-$APP_NAME \
  --codedeploy-deployment-group $CLUSTER_NAME-$APP_NAME &

DEPLOYMENT_PID=$!

sleep 5 # Wait for deployment to be created so we can fetch DEPLOYMENT_ID next

DEPLOYMENT_ID=$(aws deploy list-deployments --application-name=$CLUSTER_NAME-$APP_NAME --deployment-group=$CLUSTER_NAME-$APP_NAME --max-items=1 --query="deployments[0]" --output=text | head -n 1)

echo "---> For More Deployment info: https://$AWS_DEFAULT_REGION.console.aws.amazon.com/codesuite/codedeploy/deployments/$DEPLOYMENT_ID"

echo "---> Waiting for Deployment ..."

/work/tail-ecs-events.py &
TAIL_PID=$!

wait $DEPLOYMENT_PID
RET=$?

if [ $RET -eq 0 ]; then
  echo "---> Deployment completed!"
else
  echo "---> ERROR: Deployment FAILED!"
fi

kill $TAIL_PID

exit $RET
