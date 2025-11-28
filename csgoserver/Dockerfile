FROM registry.gitlab.steamos.cloud/steamrt/sniper/sdk

RUN apt-get update \
    && apt-get install -y --no-install-recommends --no-install-suggests \
        jq \
    && apt-get autoremove -y \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

COPY csgoserver.sh /app/csgoserver.sh
COPY run.sh /user/run.sh
RUN chmod 555 /app/csgoserver.sh /user/run.sh

WORKDIR /
ENTRYPOINT ["/app/csgoserver.sh"]
