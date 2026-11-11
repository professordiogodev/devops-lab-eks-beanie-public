#!/usr/bin/env bash
# Proves the lab left nothing in AWS. Run with: ./verify-teardown.sh
set -u
cd "$(dirname "$0")"
ACCOUNT=$(aws sts get-caller-identity --query Account --output text 2>/dev/null) || { echo "No working AWS credentials." >&2; exit 1; }
R=us-east-1; C=beanie-eks
echo "Checking account $ACCOUNT, region $R"
pass=0; failn=0
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then echo "PASS  $d"; pass=$((pass+1)); else echo "FAIL  $d"; failn=$((failn+1)); fi; }
empty() { local r; r=$(eval "$1" 2>/dev/null); [ -z "$r" ] || [ "$r" = None ]; }
check "no EKS cluster $C" bash -c "! aws eks describe-cluster --name $C --region $R"
check "no CloudFormation stack eksctl-$C-*" empty "aws cloudformation list-stacks --region $R --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE CREATE_IN_PROGRESS DELETE_IN_PROGRESS DELETE_FAILED ROLLBACK_COMPLETE --query \"StackSummaries[?starts_with(StackName, 'eksctl-$C-')].StackName\" --output text"
check "no VPC of the cluster" empty "aws ec2 describe-vpcs --region $R --filters Name=tag:alpha.eksctl.io/cluster-name,Values=$C --query 'Vpcs[].VpcId' --output text"
check "no EC2 instance of the cluster" empty "aws ec2 describe-instances --region $R --filters Name=tag:lab,Values=eks-beanie-public Name=instance-state-name,Values=pending,running,stopping,stopped --query 'Reservations[].Instances[].InstanceId' --output text"
check "no load balancer created for the cluster" bash -c "for a in \$(aws elbv2 describe-load-balancers --region $R --query 'LoadBalancers[].LoadBalancerArn' --output text); do aws elbv2 describe-tags --resource-arns \$a --region $R --query \"TagDescriptions[].Tags[?Key=='kubernetes.io/cluster/$C']\" --output text | grep -q . && exit 1; done; exit 0"
check "no unattached EBS volume of the cluster" empty "aws ec2 describe-volumes --region $R --filters Name=tag-key,Values=kubernetes.io/cluster/$C --query 'Volumes[].VolumeId' --output text"
check "no ECR repository beanie-eks" bash -c "! aws ecr describe-repositories --repository-names beanie-eks --region $R"
echo
if [ "$failn" -eq 0 ]; then echo "TEARDOWN VERIFIED ($pass/$pass) in account $ACCOUNT"; else echo "NOT CLEAN: $failn leftover(s). Remove them and run this again."; fi
exit "$failn"
