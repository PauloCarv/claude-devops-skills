---
name: k8s-security-policies
description: >
  Kubernetes security hardening specialist. Implements NetworkPolicies,
  Pod Security Standards, granular RBAC, OPA Gatekeeper constraints and
  service mesh mTLS. Use when you need cluster hardening,
  security compliance, RBAC auditing or K8s network policies.
invocation: auto
---

# K8s Security Policies

Kubernetes security specialist. Applies the principle of least privilege
across the entire stack: network, identity, runtime and supply chain.

## Areas of focus

1. **NetworkPolicies** — network segmentation, default-deny, egress control
2. **Pod Security Standards** — Restricted, Baseline, Privileged per namespace
3. **Granular RBAC** — minimal roles, auditing of excessive permissions
4. **OPA Gatekeeper** — policies as code, constraints and templates
5. **Service Mesh mTLS** — Istio/Linkerd, mutual TLS, authorization policies
6. **Supply chain** — image signing, admission webhooks, registry policies

## Hardening process

### 1. Initial audit
```bash
# List all pods running as root
kubectl get pods -A -o json | jq '.items[] | select(.spec.containers[].securityContext.runAsUser == 0) | .metadata.name'

# List service accounts with cluster-admin
kubectl get clusterrolebindings -o json | jq '.items[] | select(.roleRef.name=="cluster-admin") | .subjects'

# Check pods without resource limits
kubectl get pods -A -o json | jq '.items[] | select(.spec.containers[].resources.limits == null) | .metadata.name'

# List NetworkPolicies by namespace
kubectl get networkpolicies -A
```

### 2. Pod Security Standards per namespace

```yaml
# Apply PSS "restricted" to a namespace
apiVersion: v1
kind: Namespace
metadata:
  name: production
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/enforce-version: latest
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

### 3. OPA Gatekeeper — constraint examples

```yaml
# Disallow images with "latest" tag
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sDisallowedTags
metadata:
  name: no-latest-tag
spec:
  match:
    kinds:
      - apiGroups: ["apps"]
        kinds: ["Deployment", "StatefulSet", "DaemonSet"]
  parameters:
    tags: ["latest"]
---
# Require resource limits
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequiredResources
metadata:
  name: require-resource-limits
spec:
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
  parameters:
    limits: ["cpu", "memory"]
    requests: ["cpu", "memory"]
```

### 4. Istio — Authorization Policy (mTLS)

```yaml
# Enable strict mTLS in the namespace
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: production
spec:
  mtls:
    mode: STRICT
---
# Allow only traffic from frontend to backend
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: backend-authz
  namespace: production
spec:
  selector:
    matchLabels:
      app: backend
  rules:
    - from:
        - source:
            principals: ["cluster.local/ns/production/sa/frontend-sa"]
      to:
        - operation:
            methods: ["GET", "POST"]
            paths: ["/api/*"]
```

### 5. Admission Webhook — block privileged containers

```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata:
  name: no-privileged-containers
spec:
  failurePolicy: Fail
  matchConstraints:
    resourceRules:
      - apiGroups: [""]
        apiVersions: ["v1"]
        operations: ["CREATE", "UPDATE"]
        resources: ["pods"]
  validations:
    - expression: >
        object.spec.containers.all(c,
          !has(c.securityContext) ||
          !has(c.securityContext.privileged) ||
          c.securityContext.privileged == false
        )
      message: "Privileged containers are not allowed"
```

## Hardening checklist (production)

```
[ ] Pod Security Standards: "restricted" in production namespaces
[ ] NetworkPolicy default-deny in all namespaces
[ ] RBAC: no unnecessary cluster-admin bindings
[ ] No service accounts with excessive permissions
[ ] Resource limits on all containers
[ ] runAsNonRoot: true on all pods
[ ] readOnlyRootFilesystem: true where possible
[ ] allowPrivilegeEscalation: false
[ ] capabilities: drop: ["ALL"]
[ ] Signed images (cosign/Notary)
[ ] Private registry — no Docker Hub pulls in prod
[ ] Secrets managed externally (Azure Key Vault, Vault)
[ ] Audit logs enabled on the API server
[ ] mTLS enabled (Istio/Linkerd) on critical services
[ ] OPA Gatekeeper with compliance policies
```

## Continuous audit commands

```bash
# kube-bench — CIS Benchmark
kubectl apply -f https://raw.githubusercontent.com/aquasecurity/kube-bench/main/job.yaml
kubectl logs job/kube-bench

# trivy — image and config scan
trivy k8s --report summary cluster

# kubeaudit — security audit
kubeaudit all -n production

# polaris — best practices
polaris audit --kubernetes --format=pretty
```
