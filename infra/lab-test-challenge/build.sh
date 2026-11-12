#!/bin/sh
# 테스트 문제 이미지 빌드. 서비스 이미지를 images.tar로 묶은 뒤 Challenge 이미지를 만들고, 노드에 import할 파일로 저장한다
# 사용: sh build.sh [tag]   (기본 0.1.0)
set -eu
cd "$(dirname "$0")"
tag=${1:-0.1.0}
images=$(grep -E '^\s+image:' app/compose.yaml | awk '{print $2}')
for i in $images; do docker pull -q --platform linux/amd64 "$i"; done
docker save -o images.tar $images
docker build --platform linux/amd64 -t "hackforge/lab-test-challenge:$tag" .
docker save -o "lab-test-challenge-$tag.tar" "hackforge/lab-test-challenge:$tag"
ls -l images.tar "lab-test-challenge-$tag.tar"
