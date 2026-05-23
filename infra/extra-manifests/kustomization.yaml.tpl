apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
# The module runs `kubectl apply -k` client-side, which can't handle ArgoCD's CRDs
# (annotations exceed kubectl's 256KB limit). So this kustomization only creates the
# argocd namespace; the real install runs from extra_kustomize_deployment_commands
# with --server-side. See kube.tf.
resources:
  - argocd-namespace.yaml
