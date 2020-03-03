# gsm-controller - experimental

[![Documentation](https://godoc.org/github.com/jenkins-x-labs/gsm-controller?status.svg)](https://pkg.go.dev/mod/github.com/jenkins-x-labs/gsm-controller)
[![Go Report Card](https://goreportcard.com/badge/github.com/jenkins-x-labs/gsm-controller)](https://goreportcard.com/report/github.com/jenkins-x-labs/gsm-controller)
[![Releases](https://img.shields.io/github/release-pre/jenkins-x-labs/gsm-controller.svg)](https://github.com/jenkins-x-labs/gsm-controller/releases)
[![LICENSE](https://img.shields.io/github/license/jenkins-x-labs/gsm-controller.svg)](https://github.com/jenkins-x-labs/gsm-controller/blob/master/LICENSE)
[![Slack Status](https://img.shields.io/badge/slack-join_chat-white.svg?logo=slack&style=social)](https://slack.k8s.io/)

# Overview

gsm-controller is a Kubernetes controller that copies secrets from Google Secrets Manager into Kubernetes secrets.  The controller
watches Kubernetes secrets looking for an annotation, if the annotation is not found on the secret nothing more is done.

If the secret does have the annotation then the controller will query Google Secrets Manager, access the matching
secret and copy the value into the Kubernetes secret and save it in the cluster.

# Setup

_Note_ in this example we are creating secrets and running the Kubernetes cluster in the same Google Cloud Project, the same
approach will work if Secrets Manager is enabled in a different project to store your secrets.


First enable Google Secrets Manager

```bash
gcloud services enable secretmanager.googleapis.com
```

Create a secret
- Using a file:
```bash
gcloud beta secrets create foo --replication-policy automatic --project my-cool-project --data-file=-=my_secrets.yaml
```
- or for a single key=value secret:
```bash
echo -n bar | gcloud beta secrets create foo --replication-policy automatic --project my-cool-project --data-file=-
```


## Access

So that `gsm-controller` can access secrets in Google Secrets Manager so it can populate Kubernetes secrets in a namespace, it
requires a GCP service account with a role to access the secrets in a given GCP project.

Set some environment variables:
```bash
export NAMESPACE=jx
export CLUSTER_NAME=test-cluster-foo
export PROJECT_ID=jx-development
```

### Setup
```bash
kubectl create serviceaccount gsm-sa
kubectl annotate sa gsm-sa jenkins-x.io/gsm-secret-id='foo'

gcloud iam service-accounts create $CLUSTER_NAME-sm

gcloud iam service-accounts add-iam-policy-binding \
  --role roles/iam.workloadIdentityUser \
  --member "serviceAccount:$PROJECT_ID.svc.id.goog[$NAMESPACE/gsm-sa]" \
  $CLUSTER_NAME-sm@$PROJECT_ID.iam.gserviceaccount.com

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --role roles/secretmanager.secretAccessor \
  --member "serviceAccount:$CLUSTER_NAME-sm@$PROJECT_ID.iam.gserviceaccount.com"
```

It can take a little while for permissions to propagate when using workload identity so it's a good idea to validate
auth is working before continuing to the next step.

run a temporary pod with our kubernetes service accounts

```bash
kubectl run --rm -it \
  --generator=run-pod/v1 \
  --image google/cloud-sdk:slim \
  --serviceaccount gsm-sa \
  --namespace $NAMESPACE \
  workload-identity-test
```
use gcloud to verify you can auth, it make take a few tries over a few minutes
```bash
gcloud auth list
```

install the gsm controller chart
```bash
helm install gsm-controller \
  --set boot.namespace=$NAMESPACE \
  --set boot.projectID=$PROJECT_ID \
  .
```

### Annotate secrets
Now that the controller is running we can create a Kubernetes secret and annotate it with the id we stored the secret
with above.

```bash
kubectl create secret generic my-secret
kubectl annotate secret my-secret jenkins-x.io/gsm-secret-id=foo
```  
After a short wait you should be able to see the base64 encoded data in the secret
```bash
kubectl get secret foo -oyaml
```

If not check the logs of the controller
```bash
kubectl logs deployment/gsm-controller
```
### Run locally


```bash
gcloud iam service-accounts create $CLUSTER_NAME-sm --project $SECRETS_PROJECT_ID

gcloud iam service-accounts keys create ~/.secret/key.json \
  --iam-account $CLUSTER_NAME-sm@$PROJECT_ID.iam.gserviceaccount.com

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --role roles/secretmanager.secretAccessor \
  --member "serviceAccount:$CLUSTER_NAME-sm@$PROJECT_ID.iam.gserviceaccount.com"

```

Create a GCP secret in the project your secrets are stored, assign the accessor role, download the key.json and...
```bash
export GOOGLE_APPLICATION_CREDENTIALS=~/.secret/key.json
make build
./build/gsm-controller my-cool-project
```



