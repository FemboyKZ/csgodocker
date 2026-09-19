FROM registry.gitlab.steamos.cloud/steamrt/sniper/sdk

RUN apt-get update -o Acquire::Check-Valid-Until=false -y \
    && apt-get install -y --no-install-recommends --no-install-suggests \
        jq libssl-dev:i386 \
    && apt-get autoremove -y \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

COPY csgoserver.sh /app/csgoserver.sh
COPY run.sh /user/run.sh
RUN chmod 555 /app/csgoserver.sh /user/run.sh

WORKDIR /
ENTRYPOINT ["/app/csgoserver.sh"]
