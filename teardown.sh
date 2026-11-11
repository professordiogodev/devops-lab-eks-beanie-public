#!/usr/bin/env bash
# Removes everything, in the right order. Takes 10-15 minutes. Run with: ./teardown.sh
set -u
cd "$(dirname "$0")"
aws sts get-caller-identity >/dev/null 2>&1 || { echo "No working AWS credentials." >&2; exit 1; }
C=beanie-eks; R=us-east-1
if aws eks describe-cluster --name $C --region $R >/dev/null 2>&1; then
  KC=$(mktemp)
  aws eks update-kubeconfig --name $C --region $R --kubeconfig "$KC" >/dev/null
  export KUBECONFIG=$KC
  # 1. things that own a load balancer or a volume must go while the cluster can still delete them
  helm uninstall ingress-nginx -n ingress-nginx --wait >/dev/null 2>&1 && echo "removed the ingress controller (and its load balancer)"
  kubectl delete namespace beanie ingress-nginx --ignore-not-found --wait=true --timeout=300s >/dev/null 2>&1
  for _ in $(seq 1 30); do
    n=$(aws elbv2 describe-load-balancers --region $R --query 'LoadBalancers[].LoadBalancerArn' --output text | tr '\t' '\n' | while read a; do [ -n "$a" ] && aws elbv2 describe-tags --resource-arns "$a" --region $R --query "TagDescriptions[].Tags[?Key=='kubernetes.io/cluster/$C']" --output text; done | wc -l)
    [ "$n" -eq 0 ] && break; echo "waiting for the load balancer to disappear..."; sleep 10
  done
  rm -f "$KC"
fi
# 2. the cluster, its node group, its VPC (eksctl removes the CloudFormation stacks)
VPC=$(aws eks describe-cluster --name $C --region $R --query cluster.resourcesVpcConfig.vpcId --output text 2>/dev/null)
for attempt in 1 2 3; do
  eksctl delete cluster --name $C --region $R --wait 2>&1 | tail -3
  failed=$(aws cloudformation list-stacks --region $R --stack-status-filter DELETE_FAILED --query "StackSummaries[?starts_with(StackName, 'eksctl-$C-')].StackName" --output text)
  if ! aws eks describe-cluster --name $C --region $R >/dev/null 2>&1 && [ -z "$failed" ]; then break; fi
  # some accounts have GuardDuty runtime monitoring: it adds a VPC endpoint to the cluster VPC, which blocks the VPC delete
  [ -z "$VPC" ] && VPC=$(aws ec2 describe-vpcs --region $R --filters Name=tag:alpha.eksctl.io/cluster-name,Values=$C --query 'Vpcs[0].VpcId' --output text)
  E=$(aws ec2 describe-vpc-endpoints --region $R --filters Name=vpc-id,Values=$VPC --query 'VpcEndpoints[].VpcEndpointId' --output text)
  [ -n "$E" ] && { echo "deleting VPC endpoint(s) $E and trying again"; aws ec2 delete-vpc-endpoints --region $R --vpc-endpoint-ids $E >/dev/null
    for _ in $(seq 1 40); do [ -z "$(aws ec2 describe-vpc-endpoints --region $R --filters Name=vpc-id,Values=$VPC --query 'VpcEndpoints[?State!=`deleted`].VpcEndpointId' --output text)" ] && break; sleep 10; done; }
  for st in $failed; do aws cloudformation delete-stack --region $R --stack-name $st; aws cloudformation wait stack-delete-complete --region $R --stack-name $st; done
done
# 3. the registry
aws ecr delete-repository --repository-name beanie-eks --region $R --force >/dev/null 2>&1 && echo "deleted the ECR repository"
rm -rf beanie
echo "Now run ./verify-teardown.sh"
