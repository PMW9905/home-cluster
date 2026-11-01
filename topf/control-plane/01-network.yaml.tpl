# Static addressing, identical for all control planes except the IP (from topf.yaml).
# All three minis expose the same onboard NIC as `eno1` (Intel I219-LM, e1000e).
apiVersion: v1alpha1
kind: LinkConfig
name: eno1
addresses:
  - address: {{ .Node.IP }}/{{ .Data.prefix }}
routes:
  - gateway: {{ .Data.gateway }}
---
apiVersion: v1alpha1
kind: Layer2VIPConfig
name: {{ .Data.vip }}
link: eno1
---
apiVersion: v1alpha1
kind: ResolverConfig
nameservers:
  - address: {{ .Data.nameserver }}
