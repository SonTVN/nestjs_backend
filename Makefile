include .env

_PROJECT_ID=$(shell gcloud config get-value project)
_SUBSITUTIONS=$(shell ./keytojson.sh .env)
_PROJECT_NUMBER=$(shell gcloud projects describe ${_PROJECT_ID} --format='value(projectNumber)')
_DB_INSTANCE_ID=${_SERVICE_NAME}-${_ENV}-sql
_TRIGGER_INSTANCE_ID=${_SERVICE_NAME}-${_ENV}-trigger
_INSTANCE_CONNECTION_NAME=${_PROJECT_ID}:${_DB_REGION}:${_DB_INSTANCE_ID}

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
	@gcloud sql instances create ${_DB_INSTANCE_ID} \
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
	@echo "Success created cloudsql: ${_DB_INSTANCE_ID}"
	@gcloud sql databases create ${_DATABASE_NAME} \
		--instance=${_DB_INSTANCE_ID} \
		--charset=${_DB_CHARSET} \
		--collation=${_DB_COLLATION} \
		--async
	@echo "Success created database schema: ${_DATABASE_NAME}"
	@gcloud sql users create ${_DATABASE_USER} \
		--instance=${_DB_INSTANCE_ID} \
		--password=${_DATABASE_PASSWORD} \
		--host=% \
		--async
	@echo "Success created database users: ${_DATABASE_USER}"

trigger-init:
	@rm -f ${_TRIGGER_INSTANCE_ID}.json
	@sed "s/_GITHUB_OWNER/${_GITHUB_OWNER}/g; \
		s/_GITHUB_PROJECT/${_GITHUB_PROJECT}/g; \
		s/_TRIGGER_NAME/${_TRIGGER_INSTANCE_ID}/g; \
		s/_GITHUB_BRANCH/${_GITHUB_BRANCH}/g" \
		branch-trigger.json-tmpl > ${_TRIGGER_INSTANCE_ID}-tmpl.json
	@jq '.substitutions=${_SUBSITUTIONS}' ${_TRIGGER_INSTANCE_ID}-tmpl.json > ${_TRIGGER_INSTANCE_ID}.json
	@sed -i '' "s/_INSTANCE_CONNECTION_NAME_VALUE/${_INSTANCE_CONNECTION_NAME}/g" ${_TRIGGER_INSTANCE_ID}.json
	@rm -f ${_TRIGGER_INSTANCE_ID}-tmpl.json
	@echo "Success init trigger file: ${_TRIGGER_INSTANCE_ID}.json"

trigger-create:
	@gcloud builds triggers create cloud-source-repositories \
		--trigger-config ${_TRIGGER_INSTANCE_ID}.json
	@echo "Success created trigger: ${_TRIGGER_INSTANCE_ID}"

trigger-list:
	@gcloud builds triggers list

trigger-run:
	@gcloud builds triggers run ${_TRIGGER_INSTANCE_ID} \
		--branch=${_GITHUB_BRANCH}
	@echo "Success run trigger: ${_TRIGGER_INSTANCE_ID}"

trigger-delete:
	@gcloud builds triggers delete ${_TRIGGER_INSTANCE_ID} --async
	@echo "Success deleted trigger: ${_TRIGGER_INSTANCE_ID}"

trigger-update:
	@gcloud builds triggers import \
		--source ${_TRIGGER_INSTANCE_ID}.json
	@echo "Success updated trigger: ${_TRIGGER_INSTANCE_ID}"

trigger-describe:
	@gcloud builds triggers describe ${_TRIGGER_INSTANCE_ID}

deploy:
	# @make enable-api
	# @make grant-permission
	# @make cloudsql-create
	# @make trigger-init
	# @make trigger-create
	@make trigger-run
