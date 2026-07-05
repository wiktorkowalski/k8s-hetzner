#!/usr/bin/env bash
# Query cluster Prometheus through the API service proxy (works in every access mode,
# no port-forward). Usage: bash promq.sh 'up{job="apiserver"}' [--raw]
# Default output: one "labels<TAB>value" line per series. --raw prints the JSON.
set -euo pipefail
Q="$1"
ENC=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$Q")
RES=$(kubectl get --raw "/api/v1/namespaces/monitoring/services/kube-prometheus-stack-prometheus:9090/proxy/api/v1/query?query=${ENC}")
if [ "${2:-}" = "--raw" ]; then
  echo "$RES"
else
  echo "$RES" | python3 -c "
import json, sys
d = json.load(sys.stdin)
for r in d['data']['result']:
    m = r['metric']
    labels = ','.join(f'{k}={v}' for k, v in sorted(m.items()) if k != '__name__')
    print(f\"{m.get('__name__','')}{{{labels}}}\t{r['value'][1]}\")
"
fi
