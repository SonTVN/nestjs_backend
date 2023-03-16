include .env

_SUBSITUTIONS=$(shell ./keytojson.sh .env)

_COMMON_NAME=${_PROJECT}-${_ENV}
_DB_INSTANCE_NAME=${_COMMON_NAME}-${_FLAG}

env:
	@sed -i '' "s/^_PROJECT_ID=.*$$/_PROJECT_ID=$(shell gcloud config get-value project)/g" .env
	@sed -i '' "s/^_PROJECT_NUMBER=.*$$/_PROJECT_NUMBER=$(shell gcloud projects describe ${shell gcloud config get-value project} --format='value(projectNumber)')/g" .env
	@sed -i '' "s/^_INSTANCE_CONNECTION_NAME=.*$$/_INSTANCE_CONNECTION_NAME=${_PROJECT_ID}:${_DB_REGION}:${_DB_INSTANCE_NAME}/g" .env
	@sed -i '' "s/^_DATABASE_URL=.*$$/_DATABASE_URL=${_DATABASE_TYPE}:\/\/${_DATABASE_USER}:${_DATABASE_PASSWORD}@${_DATABASE_HOST}:${_DATABASE_PORT}\/${_DATABASE_NAME}/g" .env
	@sed -i '' "s/^_IMAGE=.*$$/_IMAGE=${_GCR_HOSTNAME}\/${_PROJECT_ID}\/${_GITHUB_PROJECT}\/${_COMMON_NAME}-${_SERVICE}:${_FLAG}/g" .env
	@sed -i '' "s/^_CLOUDRUN_NAME=.*$$/_CLOUDRUN_NAME=${_COMMON_NAME}-${_SERVICE}-${_FLAG}/g" .env
	@sed -i '' "s/^_TRIGGER_NAME=.*$$/_TRIGGER_NAME=${_COMMON_NAME}-${_SERVICE}-trigger-${_FLAG}/g" .env

enable-api:
	@gcloud services enable \
		cloudresourcemanager.googleapis.com \
		container.googleapis.com \
		sourcerepo.googleapis.com \
		cloudbuild.googleapis.com \
		containerregistry.googleapis.com \
		run.googleapis.com \
		--async
	@echo "Success enabled api service"

grant-permission:
	@gcloud projects add-iam-policy-binding ${_PROJECT_ID} \
		--member=serviceAccount:${_PROJECT_NUMBER}@cloudbuild.gserviceaccount.com \
		--role=roles/run.admin
	@gcloud iam service-accounts add-iam-policy-binding \
		${_PROJECT_NUMBER}-compute@developer.gserviceaccount.com \
		--member=serviceAccount:${_PROJECT_NUMBER}@cloudbuild.gserviceaccount.com \
		--role=roles/iam.serviceAccountUser
	@echo "Success grant permission for cloudbuild"

cloudsql-create:
	@gcloud sql instances create ${_DB_INSTANCE_NAME} \
		--database-version=${_DB_VERSION} \
		--root-password=${_DB_ROOT_PASS} \
		--availability-type=${_DB_AVAILABILITY} \
		--region=${_DB_REGION} \
		--tier=${_DB_TIER} \
		# --cpu=${_DB_CPU} \
		# --memory=${_DB_MEMORY} \
		--storage-type=${_DB_STORAGE_TYPE} \
		--storage-size=${_DB_STORAGE_SIZE} \
		--${_DB_STORAGE_AUTO_INCREASE} \
		--${_DB_ASSIGN_IP} \
		--${_DB_BACKUP} \
		--backup-location=${_DB_BACKUP_LOCATION} \
		--backup-start-time=${_DB_BACKUP_START_TIME} \
		--retained-backups-count=${_DB_RETAINED_BACKUPS_COUNT} \
		--${_DB_DELETION_PROTECTION} \
		--async
	@echo "Success created cloudsql: ${_DB_INSTANCE_NAME}"
	@gcloud sql databases create ${_DATABASE_NAME} \
		--instance=${_DB_INSTANCE_NAME} \
		--charset=${_DB_CHARSET} \
		--collation=${_DB_COLLATION} \
		--async
	@echo "Success created database schema: ${_DATABASE_NAME}"
	@gcloud sql users create ${_DATABASE_USER} \
		--instance=${_DB_INSTANCE_NAME} \
		--password=${_DATABASE_PASSWORD} \
		--host=% \
		--async
	@echo "Success created database users: ${_DATABASE_USER}"

cloudsql-proxy:
	@./cloud-sql-proxy ${_INSTANCE_CONNECTION_NAME}

image:
	@cd ./backend; \
		rm -f .env; \
		echo DATABASE_URL="'${_DATABASE_URL}?socket=/cloudsql/${_INSTANCE_CONNECTION_NAME}'" >> .env;
	@docker build --no-cache -t ${_IMAGE} . -f .infra/Dockerfile
	@echo "Success build image: ${_IMAGE}"

migrate:
	@cd ./backend; \
		rm -f .env; \
		echo DATABASE_URL="'${_DATABASE_URL}'" >> .env; \
		npm install; \
		npx prisma generate; \
		npx prisma migrate deploy;
	@echo "Success run migrate database"

seed:
	@cd ./backend; \
		rm -f .env; \
		echo DATABASE_URL="'${_DATABASE_URL}'" >> .env; \
		npm install; \
		npx prisma generate; \
		npx prisma db seed;
	@echo "Success run seed database"

login:
	@gcloud auth print-access-token | docker login -u oauth2accesstoken \
		--password-stdin https://${_GCR_HOSTNAME}
	@echo "Success login to https://${_GCR_HOSTNAME}"

push:
	@docker push ${_IMAGE}
	@echo "Success push image: ${_IMAGE}"

cloudrun-create:
	@gcloud beta run deploy ${_CLOUDRUN_NAME} \
		--platform=managed \
		--image=${_IMAGE} \
		--port=${_CLOUDRUN_PORT} \
		--${_CLOUDRUN_USE_HTTP2} \
		--region=${_DEPLOY_REGION} \
		--min-instances=${_CLOUDRUN_MIN_INSTANCE} \
		--max-instances=${_CLOUDRUN_MAX_INSTANCE} \
		--cpu=${_CLOUDRUN_CPU} \
		--${_CLOUDRUN_CPU_ALLOCATED} \
		--${_CLOUDRUN_CPU_BOOST} \
		--memory=${_CLOUDRUN_MEMORY} \
		--add-cloudsql-instances=${_INSTANCE_CONNECTION_NAME} \
		--allow-unauthenticated \
		--async
	@echo "Success created cloudrun: ${_CLOUDRUN_NAME}"

cloudrun-describe:
	gcloud run services describe ${_CLOUDRUN_NAME} \
		--region=${_DEPLOY_REGION}

cloudrun-update:
	@gcloud beta run services update ${_CLOUDRUN_NAME} \
		--platform=managed \
		--image=${_IMAGE} \
		--port=${_CLOUDRUN_PORT} \
		--${_CLOUDRUN_USE_HTTP2} \
		--region=${_DEPLOY_REGION} \
		--min-instances=${_CLOUDRUN_MIN_INSTANCE} \
		--max-instances=${_CLOUDRUN_MAX_INSTANCE} \
		--cpu=${_CLOUDRUN_CPU} \
		--${_CLOUDRUN_CPU_ALLOCATED} \
		--${_CLOUDRUN_CPU_BOOST} \
		--memory=${_CLOUDRUN_MEMORY} \
		--add-cloudsql-instances=${_INSTANCE_CONNECTION_NAME} \
		--async
	@echo "Success update cloudrun: ${_CLOUDRUN_NAME}"

trigger-init:
	@rm -f ${_TRIGGER_NAME}.json
	@sed "s/_GITHUB_OWNER/${_GITHUB_OWNER}/g; \
		s/_GITHUB_PROJECT/${_GITHUB_PROJECT}/g; \
		s/_TRIGGER_NAME/${_TRIGGER_NAME}/g; \
		s/_GITHUB_BRANCH/${_GITHUB_BRANCH}/g" \
		branch-trigger.json-tmpl > ${_TRIGGER_NAME}-tmpl.json
	@jq '.substitutions=${_SUBSITUTIONS}' ${_TRIGGER_NAME}-tmpl.json > ${_TRIGGER_NAME}.json
	@rm -f ${_TRIGGER_NAME}-tmpl.json
	@echo "Success init trigger file: ${_TRIGGER_NAME}.json"

trigger-create:
	@gcloud builds triggers create cloud-source-repositories \
		--trigger-config ${_TRIGGER_NAME}.json
	@echo "Success created trigger: ${_TRIGGER_NAME}"

trigger-list:
	@gcloud builds triggers list

trigger-run:
	@gcloud builds triggers run ${_TRIGGER_NAME} \
		--branch=${_GITHUB_BRANCH}
	@echo "Success run trigger: ${_TRIGGER_NAME}"

trigger-delete:
	@gcloud builds triggers delete ${_TRIGGER_NAME} --async
	@echo "Success deleted trigger: ${_TRIGGER_NAME}"

trigger-update:
	@gcloud builds triggers import \
		--source ${_TRIGGER_NAME}.json
	@echo "Success updated trigger: ${_TRIGGER_NAME}"

trigger-describe:
	@gcloud builds triggers describe ${_TRIGGER_NAME}

deploy:
	# @make enable-api
	# @make grant-permission
	# @make cloudsql-create
	# @make trigger-init
	# @make trigger-create
	# @make trigger-run

ssl:
	gcloud compute ssl-certificates create ${_SSL_CERTIFICATE} \
		--description="SSL Cetificate for domain ${_DOMAIN_FE_PAGE}" \
		--domains=${_DOMAIN_LIST} \
		--global

ssl-status:
	gcloud compute ssl-certificates describe ${_SSL_CERTIFICATE} \
		--global \
		--format="get(name,managed.status, managed.domainStatus)"

reserve-ip:
	gcloud compute addresses create ${_RESERVE_IP} \
		--ip-version=IPV4 \
		--network-tier=PREMIUM \
		--global

reserve-ip-status:
	gcloud compute addresses describe ${_RESERVE_IP} \
		--format="get(address)" \
		--global
	
health-check:
	gcloud compute health-checks create http http-basic-check \
		--port 80

backend-services:
	gcloud compute network-endpoint-groups create ${_SERVERLESS_NEG_NAME} \
		--region=${_DEPLOY_REGION} \
		--network-endpoint-type=serverless  \
		--cloud-run-service=${_CLOUDRUN_NAME}
	gcloud compute backend-services create ${_BACKEND_SERVICES_NAME} \
		--load-balancing-scheme=EXTERNAL \
		--global
	gcloud compute backend-services add-backend ${_BACKEND_SERVICES_NAME} \
		--global \
		--network-endpoint-group=${_SERVERLESS_NEG_NAME} \
		--network-endpoint-group-region=${_DEPLOY_REGION}
	gcloud compute url-maps create ${_URL_MAP_NAME} \
		--default-service ${_BACKEND_SERVICES_NAME}