apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: dev-pool
  namespace: metallb-system
spec:
  addresses:
  - 192.168.40.150-192.168.40.179

---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: dev
  namespace: metallb-system
spec:
  ipAddressPools:
  - dev-pool