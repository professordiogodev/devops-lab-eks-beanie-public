#!/usr/bin/env bash
rc=0
grep -qE '^\s*kind:\s*ClusterConfig' cluster.yaml && echo "- ✅ cluster.yaml is an eksctl ClusterConfig" || { echo "- ❌ cluster.yaml is not an eksctl ClusterConfig yet"; rc=1; }
grep -qE '^\s*-?\s*kind:\s*Ingress' k8s/ingress.yaml && echo "- ✅ k8s/ingress.yaml has an Ingress" || { echo "- ❌ k8s/ingress.yaml has no Ingress yet"; rc=1; }
grep -qE '^\s*images:' k8s/kustomization.yaml && echo "- ✅ k8s/kustomization.yaml rewrites the image" || { echo "- ❌ k8s/kustomization.yaml has no images: section"; rc=1; }
grep -rEq 'AKIA[0-9A-Z]{16}' . --exclude-dir=.git --exclude=ekscheck.py && { echo "- ❌ an AWS access key is committed"; rc=1; } || echo "- ✅ no AWS access key committed"
grep -qE '^ALL CHECKS PASSED \(' SUBMISSION.md && echo "- ✅ SUBMISSION.md shows ALL CHECKS PASSED" || { echo "- ❌ paste the verify.sh output ('ALL CHECKS PASSED') into SUBMISSION.md"; rc=1; }
exit $rc
