# docker-ecs-deploy

![Security](https://github.com/DNXLabs/docker-ecs-deploy/workflows/Security/badge.svg)
![Lint](https://github.com/DNXLabs/docker-ecs-deploy/workflows/Lint/badge.svg)

This container is used to assist deployments to ECS using CodeDeploy.

## Parameters
Variables must be set in the environment system level.

|Variable|Type|Description|Default|
|---|---|---|---|
|DEPLOY_TIMEOUT|Integer|Timeout in seconds for deployment|900|
|AWS_CODE_DEPLOY_OUTPUT_STATUS_LIVE|Boolean|If the environment supports live reloading use carriage returns for a single line|True|
## Usage

Inside your application repository, create the following files:

`docker-compose.yml`

```yaml
  deploy:
    image: dnxsolutions/ecs-deploy:latest
    env_file:
      - .env
    volumes:
      - ./task-definition.tpl.json:/work/task-definition.tpl.json
```

`.env` file with the following variables:
```
# Required variables
APP_NAME=<ecs service name>
CLUSTER_NAME=<ecs cluster name>
IMAGE_NAME=<ecr image arn>
CONTAINER_PORT=80
AWS_DEFAULT_REGION=

# App-specific variables (as used on task-definition below)
DB_HOST=
DB_USER=
DB_PASSWORD=
DB_NAME=
```

If the service type is **Fargate**, and you're using the `run-task.sh` script, please include:
```bash
SERVICE_TYPE=FARGATE
SUBNETS=subnet1231231,subnet123123123,subnter123123123123
```
Default values are: null

`task-definition.tpl.json` (example)
```json
{
  "containerDefinitions": [
    {
      "essential": true,
      "image": "${IMAGE_NAME}",
      "memoryReservation": 512,
      "name": "${APP_NAME}",
      "portMappings": [
        {
          "containerPort": ${CONTAINER_PORT}
        }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "ecs-${CLUSTER_NAME}-${APP_NAME}",
          "awslogs-region": "ap-southeast-2",
          "awslogs-stream-prefix": "web"
        }
      },
      "environment" : [
        { "name" : "DB_HOST", "value" : "${WODB_HOST}" },
        { "name" : "DB_USER", "value" : "${DB_USER}" },
        { "name" : "DB_PASSWORD", "value" : "${DB_PASSWORD}" },
        { "name" : "DB_NAME", "value" : "${DB_NAME}" }
      ]
    }
  ],
  "family": "${APP_NAME}"
}
```

if the the launch type is FARGATE_SPOT you must define `CAPACITY_PROVIDER_STRATEGY` variable in your `.env` file

The Capacity Provider Strategy property specifies the details of the default capacity provider strategy for the cluster. When services or tasks are run in the cluster with no launch type or capacity provider strategy specified, the default capacity provider strategy is used. [more](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-properties-ecs-clustercapacityproviderassociations-capacityproviderstrategy.html)

sample:
```
CAPACITY_PROVIDER_STRATEGY?={'Base':0,'CapacityProvider':'FARGATE_SPOT','Weight':1} 
```

## Run

Run the service to deploy:
```
docker-compose run --rm deploy
```

## Caveats

- Make sure the log group specified in the task definition exists in Cloudwatch Logs
- CodeDeploy Application and Deployment Group should exist and be called `$CLUSTER_NAME-$APP_NAME`

This container is made to be used with our terraform modules:
- <https://github.com/DNXLabs/terraform-aws-ecs>
- <https://github.com/DNXLabs/terraform-aws-ecs-app>

## NOTES - Old Versions

### 1.x.x
The 1.x.x branch is responsible for the old version, if you have any updates or want to fix a bug, please use this branch.
Be aware when creating a new version, if you change something in 1.x.x, make sure the release must be under the same umbrella.