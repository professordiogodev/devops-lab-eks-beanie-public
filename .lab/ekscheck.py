#!/usr/bin/env python3
import json, os, socket, subprocess, sys, tempfile, time, urllib.request, urllib.error
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
os.chdir(ROOT)
C, R, LAB = "beanie-eks", "us-east-1", "eks-beanie-public"
passed = failed = 0


def check(desc, ok, hint=""):
    global passed, failed
    if ok:
        passed += 1; print("PASS  " + desc)
    else:
        failed += 1; print("FAIL  " + desc + (("   -> " + hint) if hint else ""))


def aws(*a):
    try:
        return json.loads(subprocess.check_output(("aws", "--region", R) + a + ("--output", "json"), stderr=subprocess.DEVNULL, timeout=90) or "null")
    except Exception:
        return None


def finish():
    print()
    print(("ALL CHECKS PASSED (%d/%d)" % (passed, passed)) if failed == 0 else ("%d check(s) failed, %d passed" % (failed, passed)))
    sys.exit(1 if failed else 0)


def http(url, data=None, timeout=10):
    try:
        req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"} if data else {})
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, r.read().decode()
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()
    except Exception:
        return 0, ""


acct = aws("sts", "get-caller-identity")["Account"]
print("Account %s" % acct)
print("== The cluster ==")
cl = (aws("eks", "describe-cluster", "--name", C) or {}).get("cluster")
check("EKS cluster %s is ACTIVE" % C, bool(cl) and cl["status"] == "ACTIVE", "eksctl create cluster -f cluster.yaml")
if not cl:
    finish()
check("the cluster is tagged lab=%s" % LAB, cl.get("tags", {}).get("lab") == LAB)
ngs = aws("eks", "list-nodegroups", "--cluster-name", C)["nodegroups"]
check("one managed node group", len(ngs) == 1)
ng = (aws("eks", "describe-nodegroup", "--cluster-name", C, "--nodegroup-name", ngs[0]) or {}).get("nodegroup", {}) if ngs else {}
check("t3.medium, 2 nodes desired, at most 3", ng.get("instanceTypes") == ["t3.medium"] and ng.get("scalingConfig", {}).get("desiredSize") == 2 and ng.get("scalingConfig", {}).get("maxSize", 9) <= 3)
vpc = cl["resourcesVpcConfig"]["vpcId"]
nats = (aws("ec2", "describe-nat-gateways", "--filter", "Name=vpc-id,Values=" + vpc, "Name=state,Values=available,pending") or {}).get("NatGateways", [])
check("no NAT gateway in the cluster's VPC (it would bill every hour)", len(nats) == 0)

print("== The registry ==")
rp = (aws("ecr", "describe-repositories", "--repository-names", "beanie-eks") or {}).get("repositories", [])
check("ECR repository beanie-eks exists with scan on push", bool(rp) and rp[0]["imageScanningConfiguration"]["scanOnPush"])
tags = (aws("ecr", "list-tags-for-resource", "--resource-arn", rp[0]["repositoryArn"]) or {}).get("tags", []) if rp else []
check("the repository is tagged lab=%s" % LAB, any(t["Key"] == "lab" and t["Value"] == LAB for t in tags))
imgs = (aws("ecr", "describe-images", "--repository-name", "beanie-eks") or {}).get("imageDetails", []) if rp else []
check("image tag 0.1.0 is in it", any("0.1.0" in i.get("imageTags", []) for i in imgs), "docker build --platform linux/amd64 ... && docker push")

print("== Beanie in the cluster ==")
kc = tempfile.NamedTemporaryFile(suffix=".kubeconfig", delete=False).name
subprocess.run(["aws", "eks", "update-kubeconfig", "--name", C, "--region", R, "--kubeconfig", kc], capture_output=True)
env = dict(os.environ, KUBECONFIG=kc)


def k(*a):
    r = subprocess.run(("kubectl",) + a, capture_output=True, text=True, env=env, timeout=120)
    return r.returncode, r.stdout


def kj(*a):
    rc, out = k(*a, "-o", "json")
    try:
        return json.loads(out) if rc == 0 else None
    except Exception:
        return None


deps = (kj("get", "deployments", "-n", "beanie") or {}).get("items", [])
want = "%s.dkr.ecr.%s.amazonaws.com/beanie-eks:0.1.0" % (acct, R)
check("five Deployments in the namespace beanie, all pulling %s" % want, len(deps) == 5 and all(d["spec"]["template"]["spec"]["containers"][0]["image"] == want for d in deps), "kubectl kustomize k8s/ | grep image:")
end = time.time() + 180
while time.time() < end and not (deps and all(d.get("status", {}).get("readyReplicas", 0) >= d["spec"]["replicas"] for d in (kj("get", "deployments", "-n", "beanie") or {}).get("items", []))):
    time.sleep(5)
dd = (kj("get", "deployments", "-n", "beanie") or {}).get("items", [])
check("all pods Ready", bool(dd) and all(d.get("status", {}).get("readyReplicas", 0) >= d["spec"]["replicas"] for d in dd), "kubectl get pods -n beanie")
svc = {s["metadata"]["name"]: s for s in (kj("get", "svc", "-n", "beanie") or {}).get("items", [])}
check("no Service in beanie is of type LoadBalancer or NodePort (one front door, not five)", bool(svc) and all(s["spec"].get("type", "ClusterIP") == "ClusterIP" for s in svc.values()))

print("== The front door ==")
ing = (kj("get", "ingress", "-n", "beanie") or {}).get("items", [])
check("an Ingress with class nginx exists", len(ing) == 1 and ing[0]["spec"].get("ingressClassName") == "nginx")
paths = [(p["path"], p["backend"]["service"]["name"], p["backend"]["service"]["port"].get("number")) for r in (ing[0]["spec"].get("rules", []) if ing else []) for p in r.get("http", {}).get("paths", [])]
check("it routes /api to gateway:8000 and nothing else (no /metrics, /docs or /chaos on the internet)", paths == [("/api", "gateway", 8000)], str(paths))
lbs = (kj("get", "svc", "-n", "ingress-nginx") or {}).get("items", [])
lb = next((s for s in lbs if s["spec"].get("type") == "LoadBalancer"), None)
host = (((lb or {}).get("status", {}).get("loadBalancer", {}).get("ingress") or [{}])[0]).get("hostname")
check("the ingress controller has a load balancer address", bool(host), "helm install ingress-nginx ... ; wait a minute")
elbs = 0
for a in [x["LoadBalancerArn"] for x in (aws("elbv2", "describe-load-balancers") or {}).get("LoadBalancers", [])]:
    td = (aws("elbv2", "describe-tags", "--resource-arns", a) or {}).get("TagDescriptions", [{}])[0].get("Tags", [])
    if any(t["Key"] == "kubernetes.io/cluster/" + C for t in td):
        elbs += 1
check("exactly one AWS load balancer belongs to the cluster", elbs == 1, "found %d" % elbs)
if host:
    base = "http://" + host
    end = time.time() + 240
    st = 0
    while time.time() < end:
        try:
            socket.gethostbyname(host)
            st, body = http(base + "/api/menu")
            if st == 200:
                break
        except Exception:
            pass
        time.sleep(10)
    check("GET http://<load balancer>/api/menu answers 200 from the internet", st == 200, "DNS and the target group take 2-3 minutes after creation")
    st, body = http(base + "/api/orders", json.dumps({"customer": "Ana", "items": [{"item_id": "flat-white", "quantity": 2}]}).encode())
    check("POST /api/orders is paid (201) through the load balancer", st == 201, "got %s" % st)
    check("/metrics is NOT reachable from the internet (404)", http(base + "/metrics")[0] == 404)
    check("/docs is NOT reachable from the internet (404)", http(base + "/docs")[0] == 404)
os.unlink(kc)
finish()
