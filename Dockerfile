FROM ubuntu:latest
EXPOSE 9090
ARG CLASH_URL PRIVATE_VMESS PRIVATE_VLESS
ENV CLASH_URL=$CLASH_URL PRIVATE_VMESS=$PRIVATE_VMESS PRIVATE_VLESS=$PRIVATE_VLESS
COPY . /home/clash-for-linux
WORKDIR /home/clash-for-linux
RUN apt-get update && \
    apt-get install -y ca-certificates curl gzip jq && \
    rm -rf /var/lib/apt/lists/*
RUN bash ./install-mihomo.sh && rm -rf .env
CMD ["sh", "-c", "./start.sh && tail -f /dev/null"]
