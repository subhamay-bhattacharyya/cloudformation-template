#!/usr/bin/env bash
set -euo pipefail

LOG_FILE="install-tools.log"
SUMMARY_FILE="${SUMMARY_FILE:-install-summary.json}"
VERSIONS_FILE="${VERSIONS_FILE:-.tool-versions.json}"
DRY_RUN=false
INSTALL_TOOLS=(all)

for arg in "$@"; do
  case $arg in
    --dry-run)
      DRY_RUN=true
      echo "[Dry Run] No changes will be made. Commands will be printed only."
      ;;
    --tools=*)
      IFS=',' read -ra INSTALL_TOOLS <<< "${arg#*=}"
      ;;
    --summary-path=*)
      SUMMARY_FILE="${arg#*=}"
      ;;
  esac
done

exec > >(tee -a "$LOG_FILE") 2>&1

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SUMMARY_JSON="{}"
EXPECTED_JSON="{}"

if [[ -f "$VERSIONS_FILE" ]]; then
  EXPECTED_JSON=$(<"$VERSIONS_FILE")
fi

log_step() {
  echo -e "\n${YELLOW}🔧 $(date '+%Y-%m-%d %H:%M:%S') - $1${NC}"
}

run_cmd() {
  log_step "$1"
  shift
  if $DRY_RUN; then
    echo "[Dry Run] $*"
  else
    if "$@"; then
      echo -e "${GREEN}✅ Success: $1${NC}"
    else
      echo -e "${RED}❌ Failed: $1${NC}"
      exit 1
    fi
  fi
}

add_summary() {
  local name=$1
  local version=$2
  SUMMARY_JSON=$(echo "$SUMMARY_JSON" | jq --arg name "$name" --arg ver "$version" '. + {($name): $ver}')

  local expected_version
  expected_version=$(echo "$EXPECTED_JSON" | jq -r --arg name "$name" '.[$name] // empty')

  if [[ -n "$expected_version" && "$version" != "$expected_version" ]]; then
    echo -e "${RED}⚠️ Version mismatch for $name: expected $expected_version, got $version${NC}"
  fi
}

get_expected_version() {
  local name=$1
  echo "$EXPECTED_JSON" | jq -r --arg name "$name" '.[$name] // empty'
}

should_run() {
  [[ " ${INSTALL_TOOLS[*]} " =~ " all " || " ${INSTALL_TOOLS[*]} " =~ " $1 " ]]
}

# OS dependencies
log_step "Installing OS dependencies"
run_cmd "Install OS dependencies" sudo apt-get update -y && sudo apt-get install -y \
  curl unzip git jq gnupg software-properties-common ca-certificates lsb-release tar build-essential python3-pip

# AWS CLI
if should_run awscli; then
  log_step "Installing AWS CLI"
  run_cmd "Download AWS CLI" curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
  run_cmd "Unzip AWS CLI" unzip awscliv2.zip
  run_cmd "Install AWS CLI" sudo ./aws/install
  rm -rf awscliv2.zip aws
  AWS_VERSION=$(aws --version 2>&1 | awk '{print $1}' | cut -d/ -f2)
  add_summary awscli "$AWS_VERSION"
fi

# cfn-lint
if should_run cfn-lint; then
  log_step "Installing cfn-lint"
  run_cmd "Install cfn-lint" pip3 install --upgrade cfn-lint
  CFNLINT_VERSION=$(cfn-lint --version)
  add_summary cfn-lint "$CFNLINT_VERSION"
fi

# taskcat
if should_run taskcat; then
  log_step "Installing taskcat"
  run_cmd "Install taskcat" pip3 install --upgrade taskcat
  TASKCAT_VERSION=$(taskcat --version | awk '{print $2}')
  add_summary taskcat "$TASKCAT_VERSION"
fi

# cfn-guard
if should_run cfn-guard; then
  version=$(get_expected_version cfn-guard)
  version="${version:-2.1.0}"
  log_step "Installing cfn-guard"
  run_cmd "Download cfn-guard" curl -sLo cfn-guard.zip "https://github.com/aws-cloudformation/cloudformation-guard/releases/download/v${version}/cfn-guard-linux.zip"
  run_cmd "Unzip cfn-guard" unzip -o cfn-guard.zip -d cfn-guard-bin
  run_cmd "Move cfn-guard" sudo mv cfn-guard-bin/cfn-guard /usr/local/bin/
  rm -rf cfn-guard.zip cfn-guard-bin
  CFGUARD_VERSION=$(cfn-guard --version | awk '{print $2}')
  add_summary cfn-guard "$CFGUARD_VERSION"
fi

# SAM CLI
if should_run samcli; then
  log_step "Installing AWS SAM CLI"
  run_cmd "Install SAM CLI dependencies" sudo apt-get install -y python3-distutils
  run_cmd "Install AWS SAM CLI" pip3 install --upgrade aws-sam-cli
  SAM_VERSION=$(sam --version | awk '{print $4}')
  add_summary samcli "$SAM_VERSION"
fi

# jq (optional but useful)
if should_run jq; then
  log_step "Installing jq"
  run_cmd "Install jq" sudo apt-get install -y jq
  JQ_VERSION=$(jq --version)
  add_summary jq "$JQ_VERSION"
fi

# Write summary
if ! $DRY_RUN; then
  echo "$SUMMARY_JSON" | jq . > "$SUMMARY_FILE"
  echo -e "\n${GREEN}📦 Tool summary written to $SUMMARY_FILE${NC}"
fi

echo -e "\n${GREEN}✅ All CloudFormation tools installed successfully at $(date '+%Y-%m-%d %H:%M:%S')${NC}"
