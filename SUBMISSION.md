# Submission

Fork URL: <!-- paste the URL of your fork here -->

## Files to commit

- [ ] `cluster.yaml`: your eksctl cluster definition
- [ ] `k8s/kustomization.yaml` and `k8s/ingress.yaml`
- [ ] `notes.md` with your commands and what you saw (optional)

## Questions

Answer in your own words. Where a question asks for output, paste it in a code block.

### Q1. Paste your `cluster.yaml`. Which two decisions in it cost money, and why did you disable the NAT gateway (and what do you give up by putting the nodes in public subnets)?

**Your answer:**

<!-- replace this line with your answer -->

### Q2. What did `eksctl create cluster` build for you? List the CloudFormation stacks it created and the AWS resources inside the first one. Who runs the control plane, and who patches the nodes?

**Your answer:**

<!-- replace this line with your answer -->

### Q3. Paste `docker push` output or `aws ecr describe-images`. How do the nodes get permission to pull from ECR, and what would break if the repository were in another account?

**Your answer:**

<!-- replace this line with your answer -->

### Q4. Paste `kubectl kustomize k8s/`. Why use `images:` in kustomize instead of editing the image name in five files?

**Your answer:**

<!-- replace this line with your answer -->

### Q5. Paste `kubectl get ingress,svc -n ingress-nginx` and `curl -i http://<load balancer>/api/menu`. Count the hops from the internet to a gateway pod, and say which of them is a real AWS load balancer.

**Your answer:**

<!-- replace this line with your answer -->

### Q6. Why is the `gateway` Service of type ClusterIP while the ingress controller has a LoadBalancer? What does it cost to give every service its own load balancer?

**Your answer:**

<!-- replace this line with your answer -->

### Q7. Teardown order matters: what happens if you delete the cluster before the ingress controller? Paste the output of `./verify-teardown.sh`.

**Your answer:**

<!-- replace this line with your answer -->

### Q8. Paste the output of `./verify.sh`. It must end with **ALL CHECKS PASSED**.

**Your answer:**

<!-- replace this line with your answer -->

### Q9. **Tear down.** Paste the output of `./verify-teardown.sh`. It must end with **TEARDOWN VERIFIED**.

**Your answer:**

<!-- replace this line with your answer -->
