#!/bin/sh
# readinessProbe. compose 서비스가 모두 running이고, healthcheck가 있는 서비스는 healthy일 때 성공
cd /app || exit 1
expected=$(docker compose config --services 2>/dev/null | wc -l)
ok=$(docker compose ps -a --format '{{.State}} {{.Health}}' 2>/dev/null \
	| awk '$1 == "running" && ($2 == "" || $2 == "healthy")' | wc -l)
[ "$expected" -gt 0 ] && [ "$ok" -eq "$expected" ]
