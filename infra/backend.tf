terraform {
  cloud {
    organization = "wiktor9196667"

    workspaces {
      name = "k8s-hetzner"
    }
  }
}
