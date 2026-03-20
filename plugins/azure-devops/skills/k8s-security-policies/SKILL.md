---
name: k8s-security-policies
description: >
  Kubernetes security hardening specialist. Implementa NetworkPolicies,
  Pod Security Standards, RBAC granular, OPA Gatekeeper constraints e
  service mesh mTLS. Usa quando precisas de hardening de cluster,
  compliance de segurança, auditoria RBAC ou políticas de rede K8s.
invocation: auto
---

# K8s Security Policies

Especialista em segurança Kubernetes. Aplica o princípio de least privilege
em toda a stack: rede, identidade, runtime e supply chain.

## Áreas de atuação

1. **NetworkPolicies** — segmentação de rede, default-deny, egress control
2. **Pod Security Standards** — Restricted, Baseline, Privileged por namespace
3. **RBAC granular** — roles mínimas, auditoria de permissões excessivas
4. **OPA Gatekeeper** — políticas como código, constraints e templates
5. **Service Mesh mTLS** — Istio/Linkerd, mutual TLS, authorization policies
6. **Supply chain** — image signing, admission webhooks, registry policies

## Processo de hardening

### 1. Auditoria inicial
```bash
# Ver todos os pods a correr como root
kubectl get pods -A -o json | jq '.items[] | select(.spec.containers[].securityContext.runAsUser == 0) | .metadata.name'

# Listar service accounts com cluster-admin
kubectl get clusterrolebindings -o json | jq '.items[] | select(.roleRef.name=="cluster-admin") | .subjects'

# Verificar pods sem resource limits
kubectl get pods -A -o json | jq '.items[] | select(.spec.containers[].resources.limits == null) | .metadata.name'

# Listar NetworkPolicies por namespace
kubectl get networkpolicies -A
```

### 2. Pod Security Standards por namespace

```yaml
# Aplicar PSS "restricted" a um namespace
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

### 3. OPA Gatekeeper — exemplos de constraints

```yaml
# Proibir imagens com tag "latest"
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
# Obrigar resource limits
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
# Ativar mTLS estrito no namespace
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: production
spec:
  mtls:
    mode: STRICT
---
# Permitir apenas tráfego do frontend para o backend
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

### 5. Admission Webhook — bloquear privileged containers

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

## Checklist de hardening (produção)

```
[ ] Pod Security Standards: "restricted" em namespaces de produção
[ ] NetworkPolicy default-deny em todos os namespaces
[ ] RBAC: sem cluster-admin desnecessários
[ ] Sem service accounts com permissões excessivas
[ ] Resource limits em todos os containers
[ ] runAsNonRoot: true em todos os pods
[ ] readOnlyRootFilesystem: true onde possível
[ ] allowPrivilegeEscalation: false
[ ] capabilities: drop: ["ALL"]
[ ] Imagens assinadas (cosign/Notary)
[ ] Registry privado — sem pulls do Docker Hub em prod
[ ] Secrets geridos externamente (Azure Key Vault, Vault)
[ ] Audit logs ativos no API server
[ ] mTLS ativo (Istio/Linkerd) em serviços críticos
[ ] OPA Gatekeeper com políticas de compliance
```

## Comandos de auditoria contínua

```bash
# kube-bench — CIS Benchmark
kubectl apply -f https://raw.githubusercontent.com/aquasecurity/kube-bench/main/job.yaml
kubectl logs job/kube-bench

# trivy — scan de imagens e configs
trivy k8s --report summary cluster

# kubeaudit — auditoria de segurança
kubeaudit all -n production

# polaris — boas práticas
polaris audit --kubernetes --format=pretty
```
