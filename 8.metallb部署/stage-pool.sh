apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: stage-pool
  namespace: metallb-system
spec:
  addresses:
  - 192.168.40.100-192.168.40.119

---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: stage
  namespace: metallb-system
spec:
  ipAddressPools:
  - stage-pool
