# 테스트 문제 이미지 (#6 작업 5, ADR 012 "Challenge 이미지")
# 서비스 이미지는 build.sh가 images.tar로 묶어 넣는다. 실습 Pod는 외부 통신이 없어서 시작할 때 pull하지 않는다
FROM docker:27.5.1-dind
COPY app/ /app/
COPY images.tar /hackforge/images.tar
COPY hackforge/entrypoint.sh hackforge/ready.sh /hackforge/
RUN chmod 755 /hackforge/entrypoint.sh /hackforge/ready.sh
ENTRYPOINT ["/hackforge/entrypoint.sh"]
