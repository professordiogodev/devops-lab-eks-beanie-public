#!/usr/bin/env bash
# Checks your tools and your AWS login, and gets Beanie. Creates nothing in AWS. Run: ./setup.sh
set -u
cd "$(dirname "$0")"
bad=0
for c in aws eksctl kubectl helm docker git curl python3; do command -v "$c" >/dev/null || { echo "MISSING: $c"; bad=1; }; done
[ "$bad" = 0 ] || { echo "Install what is missing and run ./setup.sh again."; exit 1; }
aws sts get-caller-identity >/dev/null 2>&1 || { echo "No working AWS credentials (aws sts get-caller-identity failed)."; exit 1; }
docker info >/dev/null 2>&1 || { echo "Docker is not running."; exit 1; }
ACCT=$(aws sts get-caller-identity --query Account --output text)
if [ ! -d beanie ]; then
  git clone -q -c advice.detachedHead=false --depth 1 --branch v0.1.0 https://github.com/professordiogodev/beanie.git beanie || { echo "could not clone beanie"; exit 1; }
fi
cat <<TXT
Ready. Account $ACCT, region us-east-1.
  Cluster name:      beanie-eks
  ECR repository:    beanie-eks      ($ACCT.dkr.ecr.us-east-1.amazonaws.com/beanie-eks)
  Image to build:    docker build --platform linux/amd64 -t beanie:0.1.0 .      (the nodes are x86; an M-series Mac builds arm64 by default!)
  Cost clock:        starts when you run eksctl create cluster. Plan to finish and tear down in one sitting.
TXT
