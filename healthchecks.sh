#!/bin/bash
curl localhost:4000/liveness 2>/dev/null
printf '::'
curl localhost:4000/readiness 2>/dev/null
printf '::'
curl localhost:8080/check 2>/dev/null
printf '||'
curl localhost:4001/liveness 2>/dev/null
printf '::'
curl localhost:4001/readiness 2>/dev/null
printf '::'
curl localhost:8081/check 2>/dev/null
printf '||'
curl localhost:4002/liveness 2>/dev/null
printf '::'
curl localhost:4002/readiness 2>/dev/null
printf '::'
curl localhost:8082/check 2>/dev/null
printf '||'
curl localhost:4003/liveness 2>/dev/null
printf '::'
curl localhost:4003/readiness 2>/dev/null
printf '::'
curl localhost:8083/check 2>/dev/null
echo
