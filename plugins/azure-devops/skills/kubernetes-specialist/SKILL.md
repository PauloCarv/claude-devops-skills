---
name: kubernetes-specialist
description: >
  Senior Kubernetes specialist with deep expertise in production cluster
  management, security hardening, and cloud-native architectures.
  Use when deploying workloads, configuring networking, managing storage,
  creating Helm charts, troubleshooting clusters, or implementing K8s security.
invocation: auto
---

# Kubernetes Specialist

## When to Use This Skill

* Deploying workloads (Deployments, StatefulSets, DaemonSets, Jobs)
* Configuring networking (Services, Ingress, NetworkPolicies)
* Managing configuration (ConfigMaps, Secrets, environment variables)
* Setting up persistent storage (PV, PVC, StorageClasses)
* Creating Helm charts for application packaging
* Troubleshooting cluster and workload issues
* Implementing security best practices

## Core Workflow

1. **Analyze requirements** — Understand workload characteristics, scaling needs, security requirements
2. **Design architecture** — Choose workload types, networking patterns, storage solutions
3. **Implement manifests** — Create declarative YAML with proper resource limits, health checks
4. **Secure** — Apply RBAC, NetworkPolicies, Pod Security Standards, least privilege
5. **Validate** — Run `kubectl rollout status`, `kubectl get pods -w`, and `kubectl describe pod <n>` to confirm health; roll back with `kubectl rollout undo` if needed

## Reference Guide

Load detailed guidance based on context:

| Topic | Reference | Load When |
|---|---|---|
| Workloads | `references/workloads.md` | Deployments, StatefulSets, DaemonSets, Jobs, CronJobs |
| Networking | `references/networking.md` | Services, Ingress, NetworkPolicies, DNS |
| GitOps | `references/gitops.md` | ArgoCD, Flux, progressive delivery, sealed secrets |
| Helm Charts | `references/helm-charts.md` | Chart structure, values, templates, hooks |
| Troubleshooting | `references/troubleshooting.md` | kubectl debug, logs, events, common issues |

## Constraints

### MUST DO

* Use declarative YAML manifests (avoid imperative kubectl commands)
* Set resource requests and limits on all containers
* Include liveness and readiness probes
* Use secrets for sensitive data (never hardcode credentials)
* Apply least privilege RBAC permissions
* Implement NetworkPolicies for network segmentation
* Use namespaces for logical isolation
* Label resources consistently
* Document configuration decisions in annotations

### MUST NOT DO

* Deploy to production without resource limits
* Store secrets in ConfigMaps or as plain environment variables
* Use default ServiceAccount for application pods
* Allow unrestricted network access (default allow-all)
* Run containers as root without justification
* Skip health checks (liveness/readiness probes)
* Use `latest` tag for production images
* Expose unnecessary ports or services

## Common YAML Patterns

### Deployment com resource limits, probes e security context

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
  namespace: my-namespace
  labels:
    app: my-app
    version: "1.2.3"
spec:
  replicas: 3
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
        version: "1.2.3"
    spec:
      serviceAccountName: my-app-sa   # nunca usar a SA default
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        fsGroup: 2000
      containers:
        - name: my-app
          image: my-registry/my-app:1.2.3   # nunca usar latest
          ports:
            - containerPort: 8080
          resources:
            requests:
              cpu: "100m"
              memory: "128Mi"
            limits:
              cpu: "500m"
              memory: "512Mi"
          livenessProbe:
            httpGet:
              path: /healthz
              port: 8080
            initialDelaySeconds: 15
            periodSeconds: 20
          readinessProbe:
            httpGet:
              path: /ready
              port: 8080
            initialDelaySeconds: 5
            periodSeconds: 10
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop: ["ALL"]
          envFrom:
            - secretRef:
                name: my-app-secret
```

### RBAC mínimo (least privilege)

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: my-app-sa
  namespace: my-namespace
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: my-app-role
  namespace: my-namespace
rules:
  - apiGroups: [""]
    resources: ["configmaps"]
    verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: my-app-rolebinding
  namespace: my-namespace
subjects:
  - kind: ServiceAccount
    name: my-app-sa
    namespace: my-namespace
roleRef:
  kind: Role
  name: my-app-role
  apiGroup: rbac.authorization.k8s.io
```

### NetworkPolicy (default-deny + allow explícito)

```yaml
# Negar todo o tráfego por defeito
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: my-namespace
spec:
  podSelector: {}
  policyTypes: ["Ingress", "Egress"]
---
# Permitir apenas tráfego específico
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-my-app
  namespace: my-namespace
spec:
  podSelector:
    matchLabels:
      app: my-app
  policyTypes: ["Ingress"]
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: frontend
      ports:
        - protocol: TCP
          port: 8080
```

## Comandos de Validação

```bash
# Confirmar rollout completo
kubectl rollout status deployment/my-app -n my-namespace

# Observar pods em tempo real
kubectl get pods -n my-namespace -w

# Inspecionar pod com falhas
kubectl describe pod <pod-name> -n my-namespace

# Ver logs (incluindo container anterior após crash)
kubectl logs <pod-name> -n my-namespace --previous

# Verificar consumo de recursos vs limites
kubectl top pods -n my-namespace

# Auditar permissões RBAC de uma service account
kubectl auth can-i --list --as=system:serviceaccount:my-namespace:my-app-sa

# Reverter deployment
kubectl rollout undo deployment/my-app -n my-namespace
```

## Output Esperado

Quando implementas recursos Kubernetes, fornece sempre:

1. Manifests YAML completos e estruturados
2. Configuração RBAC (ServiceAccount, Role, RoleBinding)
3. NetworkPolicy para isolamento de rede
4. Breve explicação das decisões de design e considerações de segurança
