include .env

_PROJECT_ID=$(shell gcloud config get-value project)
_SUBSITUTIONS=$(shell ./keytojson.sh .env)
_PROJECT_NUMBER=$(shell gcloud projects describe ${_PROJECT_ID} --format='value(projectNumber)')

enable-api:
	gcloud services enable \
		cloudresourcemanager.googleapis.com \
		container.googleapis.com \
		sourcerepo.googleapis.com \
		cloudbuild.googleapis.com \
		containerregistry.googleapis.com \
		run.googleapis.com

grant-permission:
	gcloud projects add-iam-policy-binding ${PROJECT_ID} \
		--member=serviceAccount:${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com \
		--role=roles/run.admin
	gcloud iam service-accounts add-iam-policy-binding \
		${PROJECT_NUMBER}-compute@developer.gserviceaccount.com \
		--member=serviceAccount:${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com \
		--role=roles/iam.serviceAccountUser

trigger-init:
	@rm -f ${_GITHUB_BRANCH}-trigger.json
	@sed "s/_GITHUB_OWNER/${_GITHUB_OWNER}/g; \
		s/_GITHUB_PROJECT/${_GITHUB_PROJECT}/g; \
		s/_TRIGGER_NAME/${_SERVICE_NAME}-${_ENV}-trigger/g; \
		s/_GITHUB_BRANCH/${_GITHUB_BRANCH}/g" \
		branch-trigger.json-tmpl > ${_SERVICE_NAME}-${_ENV}-trigger-tmpl.json
	@jq '.substitutions=${_SUBSITUTIONS}' ${_SERVICE_NAME}-${_ENV}-trigger-tmpl.json > ${_SERVICE_NAME}-${_ENV}-trigger.json
	@rm -f ${_SERVICE_NAME}-${_ENV}-trigger-tmpl.json
	@echo "Success init trigger file: ${_SERVICE_NAME}-${_ENV}-trigger.json"

trigger-create:
	gcloud builds triggers create cloud-source-repositories \
		--trigger-config ${_SERVICE_NAME}-${_ENV}-trigger.json

trigger-list:
	gcloud builds triggers list

trigger-run:
	gcloud builds triggers run ${_SERVICE_NAME}-${_ENV}-trigger --branch=${_GITHUB_BRANCH}

trigger-delete:
	gcloud builds triggers delete ${_SERVICE_NAME}-${_ENV}-trigger

trigger-update:
	gcloud builds triggers import --source ${_SERVICE_NAME}-${_ENV}-trigger.json

trigger-describe:
	gcloud builds triggers describe ${_SERVICE_NAME}-${_ENV}-trigger


