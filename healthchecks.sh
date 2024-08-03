#!/bin/bash
curl localhost:4000/liveness 2>/dev/null
printf '::'
curl localhost:4000/readiness 2>/dev/null
printf '::'
curl localhost:8080/check 2>/dev/null
echo
