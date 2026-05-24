FROM debian:bookworm-slim

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    coreutils \
    findutils \
    gawk \
    grep \
    sed \
  && rm -rf /var/lib/apt/lists/*

COPY run-scenarios.sh /usr/local/bin/run-scenarios
RUN chmod +x /usr/local/bin/run-scenarios

WORKDIR /repo
ENTRYPOINT ["/usr/local/bin/run-scenarios"]
