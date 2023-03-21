# docker-ecs-deploy

![Security](https://github.com/DNXLabs/docker-ecs-deploy/workflows/Security/badge.svg)
![Lint](https://github.com/DNXLabs/docker-ecs-deploy/workflows/Lint/badge.svg)

This container is used to assist deployments to ECS using CodeDeploy.

Repository URL: https://github.com/DNXLabs/docker-ecs-deploy

## Parameters
Variables must be set in the environment system level.

|Variable|Type|Description|Default|
|---|---|---|---|
|DEPLOY_TIMEOUT|Integer|Timeout in seconds for deployment|900|
|TPL_FILE_NAME|Sring|Task definitions template json file name|task-definition.tpl.json|
|APPSPEC_FILE_NAME|String|CodeDeploy App Spec|app-spec.tpl.json|
|SEVERITY|List(space separated)|List of container vulnerability severity|CRITICAL HIGH|
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
AWS_DEFAULT_REGION=<aws region>

#ECR Scanning
BUILD_VERSION=<image tag>
APP_NAME=<repo name>
AWS_DEFAULT_REGION=<aws region>
ECR_ACCOUNT=<aws ecr account number>

# App-specific variables (as used on task-definition below)
IMAGE_NAME=<image name and tag>
CPU=<cpu amount>
MEMORY=<memory amount>
CONTAINER_PORT=<container port>
DEFAULT_COMMAND=<container command e.g. ["echo", "test"]>
AWS_ACCOUNT_ID=<aws account number>
```

If the service type is **Fargate** please include:
```bash
SERVICE_TYPE=FARGATE
SUBNETS=subnet-12345abcd,subnet-a1b2c3d4,subnet-abcd12345
SECURITY_GROUPS=sg-a1b2c3d4e5,sg-12345abcd
```

`task-definition.tpl.json` (see [templates](./templates/))
```yaml
{
  "containerDefinitions": [
    {
      "essential": true,
      "image": "${IMAGE_NAME}",
      "command": ${DEFAULT_COMMAND},
      "cpu": ${CPU},
      "memory": ${MEMORY},
      "memoryReservation": ${MEMORY},
      "name": "${APP_NAME}",
      "portMappings": [
        {
          "containerPort": ${CONTAINER_PORT}
        }
      ],
      "environment": [],
      "mountPoints": [],
      "volumesFrom": [],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
            "awslogs-group": "/ecs/${CLUSTER_NAME}/${APP_NAME}",
            "awslogs-region": "${AWS_DEFAULT_REGION}",
            "awslogs-stream-prefix": "${APP_NAME}"
        }
      }
    }
  ],
  "family": "${CLUSTER_NAME}-${APP_NAME}",
  "executionRoleArn": "arn:aws:iam::${AWS_ACCOUNT_ID}:role/ecs-task-${CLUSTER_NAME}-${AWS_DEFAULT_REGION}",
  "taskRoleArn": "arn:aws:iam::${AWS_ACCOUNT_ID}:role/ecs-task-${CLUSTER_NAME}-${AWS_DEFAULT_REGION}"
}
```

if the the launch type is FARGATE_SPOT you must define `CAPACITY_PROVIDER_STRATEGY` variable in your `.env` file

The Capacity Provider Strategy property specifies the details of the default capacity provider strategy for the cluster. When services or tasks are run in the cluster with no launch type or capacity provider strategy specified, the default capacity provider strategy is used. [more](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-properties-ecs-clustercapacityproviderassociations-capacityproviderstrategy.html)

sample:
```
CAPACITY_PROVIDER_STRATEGY={'Base':0,'CapacityProvider':'FARGATE_SPOT','Weight':1} 
```

## Run

[docker-compose.yml](./docker-compose.yml) examples

Deploy a service: 
```
docker-compose run --rm deploy
docker-compose run --rm cutover
```
Run one time task such as db migration:
```
docker-compose run --rm run-task
```
Run a worker service (ECS deployment):
```
docker-compose run --rm worker-deploy
```
Get ECR Enhanced Scan report:
```
docker-compose run --rm ecr-scan
```

## Caveats

- Make sure the log group specified in the task definition exists in Cloudwatch Logs
- CodeDeploy Application name and Deployment Group should exist and be called `$CLUSTER_NAME-$APP_NAME`

This container is made to be used with our terraform modules:
- <https://github.com/DNXLabs/terraform-aws-ecs>
- <https://github.com/DNXLabs/terraform-aws-ecs-app>

## NOTES - Old Versions

### 1.x.x
The 1.x.x branch is responsible for the old version, if you have any updates or want to fix a bug, please use this branch.
Be aware when creating a new version, if you change something in 1.x.x, make sure the release must be under the same umbrella.
