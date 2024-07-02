IMAGE_NAME ?= dnxsolutions/ecs-deploy:lucas-0.0.3

.env:
	cp .env.template .env
	echo >> .env

build:
	docker build -t $(IMAGE_NAME) .

shell: .env
	docker run --rm -it  --env-file=.env \
	--entrypoint=/bin/bash -v ~/.aws:/root/.aws \
	-v $(PWD)/src:/work $(IMAGE_NAME)

scan: build
	docker run --rm \
	--volume /var/run/docker.sock:/var/run/docker.sock \
	--name Grype anchore/grype:v0.59.1 \
	$(IMAGE_NAME)

lint:
	docker run --rm -i \
	-v $(PWD)/hadolint.yaml:/.config/hadolint.yaml \
	hadolint/hadolint < Dockerfile

deploy: .env
	@echo "make deploy"
	docker-compose -f docker-compose.yml run --rm deploy

cutover: .env
	@echo "make cutover"
	docker-compose -f docker-compose.yml run --rm cutover

run-task: .env
	@echo "make run-task"
	docker-compose -f docker-compose.yml run --rm run-task

worker-deploy:
	@echo "make worker-deploy"
	docker-compose -f docker-compose.yml run --rm worker-deploy

ecr-scan:
	@echo "make ecr-scan"
	docker-compose -f docker-compose.yml run --rm ecr-scan
	