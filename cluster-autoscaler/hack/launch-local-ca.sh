#!/usr/bin/env zsh
set -eo pipefail

echoErr() { echo "$@" 1>&2; }


CURRENT_DIR=$(pwd)
PROJECT_ROOT="${CURRENT_DIR}"

if  ! command -v gum &>/dev/null; then
  echoErr "gum not installed. Kindly first install gum (https://github.com/charmbracelet/gum) using relevant procedure for your OS"
  exit 1
fi

devEnvFile="$PROJECT_ROOT/.env"
if [[ ! -f "$devEnvFile" ]]; then
  echoErr  "ERROR: $devEnvFile is not created. Kindly execute ./hack/local_setup.sh before running this script."
  exit 2
fi

source "$devEnvFile"

if [[ ! -f "$CONTROL_KUBECONFIG" ]]; then
  echoErr  "ERROR: Control Cluster kubeconfig is not at expected path $CONTROL_KUBECONFIG. Please ensure that ./hack/local_setup.sh is run correctly."
  exit 3
fi

if [[ -z "$GARDEN_PROJECT" ]]; then
  echoErr  "ERROR: GARDEN_PROJECT env-var not set. Please ensure that ./hack/local_setup.sh is run correctly and check $devEnvFile.."
  exit 4
fi

if [[ -z "$SHOOT" ]]; then
  echoErr  "ERROR: SHOOT env-var not set. Please ensure that ./hack/local_setup.sh is run correctly and check $devEnvFile."
  exit 5
fi

if [[ ! -f "main.go" ]]; then
  echoErr "ERROR: CA main.go missing in current dir. Please ensure you are in the right cluster-autoscaler dir."
  exit 6
fi

echo "NOTE: This script generates a /tmp/local-ca.sh which launches the local CA with the same configuration as that of the remote CA in the configured shoot's control plane"

echo "Targeting control plane of sap-landscape-dev:$GARDEN_PROJECT:$SHOOT"
gardenctl target --garden sap-landscape-dev --project "$GARDEN_PROJECT" --shoot aw --control-plane
caDeploJsonPath="/tmp/ca-deploy.json"
kubectl get deploy cluster-autoscaler -ojson > "$caDeploJsonPath"
echo "Downloaded CA Deployment JSON YAML into $caDeploJsonPath"

commandArgs=$(jq -r '.spec.template.spec.containers[0].command[]' "$caDeploJsonPath" | sed 1d | sed /--kubeconfig/d | tr '\n' ' ')
export CONTROL_KUBECONFIG="$CONTROL_KUBECONFIG"
export CONTROL_NAMESPACE="$CONTROL_NAMESPACE"
export TARGET_KUBECONFIG="$TARGET_KUBECONFIG"
launchCommand="go run main.go --kubeconfig=$TARGET_KUBECONFIG $commandArgs 2>&1 | tee /tmp/ca.log"
gum confirm "Launch local CA using following command: '$launchCommand' ?" && echo "$launchCommand" && eval "$launchCommand"


