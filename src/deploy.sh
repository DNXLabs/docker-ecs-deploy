#!/usr/bin/env bash

set +e
set -o noglob


#
# Set Colors
#

bold="\e[1m"
dim="\e[2m"
underline="\e[4m"
blink="\e[5m"
reset="\e[0m"
red="\e[31m"
green="\e[32m"
blue="\e[34m"


#
# Common Output Styles
#

h1() {
  printf "\n${bold}${underline}%s${reset}\n" "$(echo "$@" | sed '/./,$!d')"
}
h2() {
  printf "\n${bold}%s${reset}\n" "$(echo "$@" | sed '/./,$!d')"
}
info() {
  printf "${dim}➜ %s${reset}\n" "$(echo "$@" | sed '/./,$!d')"
}
success() {
  printf "${green}✔ %s${reset}\n" "$(echo "$@" | sed '/./,$!d')"
}
error() {
  printf "${red}${bold}✖ %s${reset}\n" "$(echo "$@" | sed '/./,$!d')"
}
warnError() {
  printf "${red}✖ %s${reset}\n" "$(echo "$@" | sed '/./,$!d')"
}
warnNotice() {
  printf "${blue}✖ %s${reset}\n" "$(echo "$@" | sed '/./,$!d')"
}
note() {
  printf "\n${bold}${blue}Note:${reset} ${blue}%s${reset}\n" "$(echo "$@" | sed '/./,$!d')"
}

# Runs the specified command and logs it appropriately.
#   $1 = command
#   $2 = (optional) error message
#   $3 = (optional) success message
#   $4 = (optional) global variable to assign the output to
runCommand() {
  command="$1"
  info "$1"
  output="$(eval $command 2>&1)"
  ret_code=$?

  if [ $ret_code != 0 ]; then
    warnError "$output"
    if [ ! -z "$2" ]; then
      error "$2"
    fi
    exit $ret_code
  fi

  if [ ! -z "$3" ]; then
    success "$3"
  fi

  if [ ! -z "$4" ]; then
    eval "$4='$output'"
  fi
}

typeExists() {
  if [ $(type -P $1) ]; then
    return 0
  fi
  return 1
}

jsonValue() {
  key=$1
  num=$2
  awk -F"[,:}]" '{for(i=1;i<=NF;i++){if($i~/'$key'\042/){print $(i+1)}}}' | tr -d '"' | sed -n ${num}p
}

vercomp() {
  if [[ $1 == $2 ]]
  then
    return 0
  fi
  local IFS=.
  local i ver1=($1) ver2=($2)

  # fill empty fields in ver1 with zeros
  for ((i=${#ver1[@]}; i<${#ver2[@]}; i++))
  do
    ver1[i]=0
  done

  for ((i=0; i<${#ver1[@]}; i++))
  do
    if [[ -z ${ver2[i]} ]]
    then
      # fill empty fields in ver2 with zeros
      ver2[i]=0
    fi
    if ((10#${ver1[i]} > 10#${ver2[i]}))
    then
      return 1
    fi
    if ((10#${ver1[i]} < 10#${ver2[i]}))
    then
      return 2
    fi
  done
  return 0
}

isjsonValid() {
  file=$1
  info "Verifying if file $file is a valid JSON"
  if [ $(cat $file | jq empty > /dev/null 2>&1; echo $?) -eq 0 ]; then
    success "File $file is a valid JSON file"
  else
    error "File $file is not a valid JSON file"
  fi
  return $?
}

# ----- Check variables -----
h1 "Step 1: Checking environment variables"

if [[ ! -f "task-definition.tpl.json" ]]; then
    error "File: task-definition.tpl.json not found"
    exit 1
fi

if [ -z "$AWS_DEFAULT_REGION" ]; then
  error "Please set the \"\$AWS_DEFAULT_REGION\" variable"
  exit 1
fi

if [ -z "$APP_NAME" ]; then
  error "Please set the \"\$APP_NAME\" variable"
  exit 1
fi

if [ -z "$CLUSTER_NAME" ]; then
  error "Please set the \"\$CLUSTER_NAME\" variable"
  exit 1
fi

if [ -z "$CONTAINER_PORT" ]; then
  error "Please set the \"\$CONTAINER_PORT\" variable"
  exit 1
fi

if [ -z "$IMAGE_NAME" ]; then
  error "Please set the \"\$IMAGE_NAME\" variable"
  exit 1
fi

success "Variables ok"

# ----- Create task definition file -----
h1 "Step 2: Replace variables inside of task-definition.tpl.json"
runCommand "envsubst < task-definition.tpl.json > task-definition.json" \
            "Create task definition file failed" \
            "Create task definition file"

isjsonValid "task-definition.json"
info "Task definition file:"
cat task-definition.json | jq

# ----- Register task definition file -----
h1 "Step 3: Registering task definition"
runCommand "aws ecs register-task-definition --cli-input-json file://./task-definition.json" \
            "Register task definition failed" \
            "Register task definition" \
            OUTPUT_TASK_ARN

OUTPUT_TASK_ARN=$(echo $OUTPUT_TASK_ARN | jq --raw-output '.taskDefinition.taskDefinitionArn')
export TASK_ARN=$OUTPUT_TASK_ARN

# ----- Create app spec file -----
if [ ! -z "$CAPACITY_PROVIDER_STRATEGY" ]; then
  CAPACITY_PROVIDER_STRATEGY=',\"CapacityProviderStrategy\":['${CAPACITY_PROVIDER_STRATEGY}']'
fi

h1 "Step 4: Creating App Spec for CodeDeploy"
runCommand "envsubst < app-spec.tpl.json > app-spec.json" \
            "Create app-spec file failed" \
            "Create app-spec file"

isjsonValid "app-spec.json"
info "App spec file:"
cat app-spec.json | jq

# ----- Create Deployment -----
h1 "Step 5: Creating Deployment"
APPLICATION_NAME=$CLUSTER_NAME-$APP_NAME
DEPLOYMENT_CONFIG_NAME=CodeDeployDefault.ECSAllAtOnce
DEPLOYMENT_GROUP=$CLUSTER_NAME-$APP_NAME

# TODO: Check if is there any deployment in progress

DEPLOYMENT_CMD="aws deploy create-deployment \
    --output json \
    --application-name $APPLICATION_NAME \
    --deployment-config-name $DEPLOYMENT_CONFIG_NAME \
    --deployment-group-name $DEPLOYMENT_GROUP \
    --description Deployment \
    --revision file://app-spec.json"

DEPLOYMENT_OUTPUT=""
runCommand "$DEPLOYMENT_CMD" \
           "Deployment of application \"$APPLICATION_NAME\" on deployment group \"$DEPLOYMENT_GROUP\" failed" \
           "" \
           DEPLOYMENT_OUTPUT

DEPLOYMENT_ID=$(echo $DEPLOYMENT_OUTPUT | jsonValue 'deploymentId' | tr -d ' ')
success "Successfully created deployment: \"$DEPLOYMENT_ID\""
note "For more info, you can follow your deployment at: https://$AWS_DEFAULT_REGION.console.aws.amazon.com/codesuite/codedeploy/deployments/$DEPLOYMENT_ID"


# ----- Monitor Deployment -----
h1 "Step 6: Deployment Overview"

DEPLOY_TIMEOUT_PERIOD=0

DEPLOYMENT_GET="aws deploy get-deployment --output json --deployment-id \"$DEPLOYMENT_ID\""
h2 "Monitoring deployment \"$DEPLOYMENT_ID\" for \"$APPLICATION_NAME\" on deployment group $DEPLOYMENT_GROUP ..."
info "$DEPLOYMENT_GET"

TASK_SET_ID=""

while [ "${TASK_SET_ID}" == "" ]; do
  TASK_SET_ID=$(aws ecs describe-services --cluster $CLUSTER_NAME --service $APP_NAME --query "services[0].taskSets[?status == 'ACTIVE'].id" --output text)
  sleep 1
done

info "Task Set ID: $TASK_SET_ID"

# If the environment supports live reloading use carriage returns for a single line.
if [ "true" == "${AWS_CODE_DEPLOY_OUTPUT_STATUS_LIVE:-true}" ]; then
  status_opts="\r${bold}"
  status_opts_live="\r${bold}${blink}"
else
  status_opts="\n${bold}"
  status_opts_live="\n${bold}"
fi

h2 "Monitoring ECS service events for cluster ($CLUSTER_NAME) on service ($APP_NAME):"
/work/tail-ecs-events.py & TAIL_ECS_EVENTS_PID=$!
printf "\n"

while :
  do
    DEPLOYMENT_GET_OUTPUT="$(eval $DEPLOYMENT_GET 2>&1)"
    if [ $? != 0 ]; then
      warnError "$DEPLOYMENT_GET_OUTPUT"
      error "Deployment of application \"$APPLICATION_NAME\" on deployment group \"$DEPLOYMENT_GROUP\" failed"
      exit 1
    fi

    # Deployment Overview
    IN_PROGRESS=$(echo "$DEPLOYMENT_GET_OUTPUT" | jsonValue "InProgress" | tr -d "\r\n ")
    PENDING=$(echo "$DEPLOYMENT_GET_OUTPUT" | jsonValue "Pending" | tr -d "\r\n ")
    SKIPPED=$(echo "$DEPLOYMENT_GET_OUTPUT" | jsonValue "Skipped" | tr -d "\r\n ")
    SUCCEEDED=$(echo "$DEPLOYMENT_GET_OUTPUT" | jsonValue "Succeeded" | tr -d "\r\n ")
    FAILED=$(echo "$DEPLOYMENT_GET_OUTPUT" | jsonValue "Failed" | tr -d "\r\n ")

    # Deployment Status
    STATUS=$(echo "$DEPLOYMENT_GET_OUTPUT" | jsonValue "status" | tr -d "\r\n" | tr -d " ")
    ERROR_MESSAGE=$(echo "$DEPLOYMENT_GET_OUTPUT" | jsonValue "message")

    # Check if containers are being stoped
    LAST_TASK_ARN=$(aws ecs list-tasks --cluster $CLUSTER_NAME --desired-status STOPPED --started-by $TASK_SET_ID --query taskArns[0] --output text)
    if [ "${LAST_TASK_ARN}" != "None" ]; then
      LAST_TASK_INFO=$(aws ecs describe-tasks --cluster $CLUSTER_NAME --tasks $LAST_TASK_ARN --query tasks[0])
      LAST_TASK_STATUS=$(echo $LAST_TASK_INFO | jq -r .lastStatus)
      LAST_TASK_REASON=$(echo $LAST_TASK_INFO | jq -r .stoppedReason)

      if [ "${LAST_TASK_STATUS}" == "STOPPED" ]; then
        runCommand "aws deploy stop-deployment --deployment-id $DEPLOYMENT_ID --auto-rollback-enabled" \
                   "Rollback deployment failed" \
                   "Rollback deployment success"
        STATUS=Failed
        ERROR_MESSAGE=$LAST_TASK_REASON
      fi
    fi


    # Rechead limit
    if [ "$DEPLOY_TIMEOUT_PERIOD" -ge "${DEPLOY_TIMEOUT:-900}" ]; then
      warnNotice "Timeout reached. Rolling back deployment..."
      runCommand "aws deploy stop-deployment --deployment-id $DEPLOYMENT_ID --auto-rollback-enabled" \
                  "Rollback deployment failed" \
                  "Rollback deployment success"
      exit 1
    fi

    # Print Status
    if [ "$STATUS" == "Failed" ]; then
      error "Deployment failed: $ERROR_MESSAGE"
      exit 1
    fi

    if [ "$STATUS" == "Stopped" ]; then
      warnNotice "Deployment stopped by user"
      info "$ERROR_MESSAGE"
      exit 1
    fi

    if [ "$STATUS" == "Ready" ]; then
      success "Deployment of application \"$APPLICATION_NAME\" on deployment group \"$DEPLOYMENT_GROUP\" ready and waiting for cutover"
      break
    fi

    if [ "$STATUS" == "Succeeded" ]; then
      success "Deployment of application \"$APPLICATION_NAME\" on deployment group \"$DEPLOYMENT_GROUP\" succeeded"
      break
    fi

    # Increment timeout limit
    ((DEPLOY_TIMEOUT_PERIOD=DEPLOY_TIMEOUT_PERIOD+1))
    sleep 1
  done

# Kill PID from tail ecs events
kill $TAIL_ECS_EVENTS_PID