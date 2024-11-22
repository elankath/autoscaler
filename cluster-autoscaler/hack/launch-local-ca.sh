#!/usr/bin/env zsh
# /*
# Copyright (c) 2022 SAP SE or an SAP affiliate company. All rights reserved. This file is licensed under the Apache Software License, v. 2 except as noted otherwise in the LICENSE file

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at

#      http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# */
#
set -eo pipefail

echoErr() { echo "$@" 1>&2; }


CURRENT_DIR=$(pwd)
PROJECT_ROOT="${CURRENT_DIR}"

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

echo "NOTE: This script launches the local CA with the same configuration as that of the remote CA in the configured shoot's control plane"

echo "Targeting control plane of sap-landscape-dev:$GARDEN_PROJECT:$SHOOT"
gardenctl target --garden sap-landscape-dev --project "$GARDEN_PROJECT" --shoot aw --control-plane
caDeploJsonPath="/tmp/ca-deploy.json"
kubectl get deploy cluster-autoscaler -ojson > "$caDeploJsonPath"
echo "Downloaded CA Deployment JSON YAML into $caDeploJsonPath"

commandArgs=$(jq -r '.spec.template.spec.containers[0].command[]' "$caDeploJsonPath" | sed 1d | sed /--kubeconfig/d | tr '\n' ' ')
export CONTROL_KUBECONFIG="$CONTROL_KUBECONFIG"
export CONTROL_NAMESPACE="$CONTROL_NAMESPACE"
export TARGET_KUBECONFIG="$TARGET_KUBECONFIG"
launchCommand="go run main.go --kubeconfig=$TARGET_KUBECONFIG $commandArgs 2>&1 | tee /tmp/ca-local.log"
fastLaunchScript="/tmp/fast-launch-ca.sh"
echo


echo "Creating fast launch script at $fastLaunchScript"
cat << EOF >"$fastLaunchScript"
cd "$PROJECT_ROOT"
export CONTROL_KUBECONFIG="$CONTROL_KUBECONFIG"
export CONTROL_NAMESPACE="$CONTROL_NAMESPACE"
export TARGET_KUBECONFIG="$TARGET_KUBECONFIG"
echo "$launchCommand"
$launchCommand
EOF
chmod +x "$fastLaunchScript"


pauseSecs="5"
echo "Launching local CA using following command in $pauseSecs secs. You may also launch using generated fast launch script at: $fastLaunchScript "
echo "$launchCommand"
sleep "$pauseSecs"
eval "$launchCommand"

