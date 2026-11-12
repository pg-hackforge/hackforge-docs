#!/bin/sh
# dockerd 시작 → 서비스 이미지 load → compose up. 어느 단계든 실패하면 종료해서 Pod가 Failed가 된다(재시도는 백엔드)
set -eu
log() { echo "hackforge: $(date +%s) $*"; }

log start
# unix socket만 연다. TCP를 열면 docker:dind가 경고를 보여 주려고 15초를 기다린다
dockerd-entrypoint.sh --host=unix:///var/run/docker.sock &
dockerd_pid=$!
until docker info >/dev/null 2>&1; do
	kill -0 "$dockerd_pid" 2>/dev/null || { log "dockerd exited"; exit 1; }
	sleep 0.5
done
log dockerd-ready
docker load -q -i /hackforge/images.tar
log images-loaded
cd /app && docker compose up -d
log compose-up
wait "$dockerd_pid"
