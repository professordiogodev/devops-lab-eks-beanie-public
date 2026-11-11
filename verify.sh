#!/usr/bin/env bash
# Reads the cluster, the registry, the load balancer and uses the public URL. Run with: ./verify.sh
cd "$(dirname "$0")" || exit 1
for c in aws kubectl python3; do command -v $c >/dev/null || { echo "$c is not installed." >&2; exit 1; }; done
aws sts get-caller-identity >/dev/null 2>&1 || { echo "No working AWS credentials." >&2; exit 1; }
exec python3 .lab/ekscheck.py
