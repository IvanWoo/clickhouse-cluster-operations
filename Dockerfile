ARG CLICKHOUSE_VERSION="22.6"
FROM clickhouse/clickhouse-server:$CLICKHOUSE_VERSION

ARG DBMATE_VERSION="v1.13.0"
ARG DBMATE_USER_HOME=/app
ARG DBMATE_USER="dbmate"
ARG DBMATE_UID="1000"
ARG DBMATE_GID="100"

RUN mkdir $DBMATE_USER_HOME && \
    useradd -ms /bin/bash -u $DBMATE_UID $DBMATE_USER && \
    chown $DBMATE_USER:$DBMATE_GID $DBMATE_USER_HOME && \
    buildDeps='curl' && \
    apt-get update && \
    apt-get install -y --no-install-recommends $buildDeps && \
    # install dbmate
    curl -fsSL -o /usr/local/bin/dbmate https://github.com/amacneil/dbmate/releases/download/$DBMATE_VERSION/dbmate-linux-amd64 && \
    chmod +x /usr/local/bin/dbmate && \
    apt-get purge --auto-remove -yqq $buildDeps && \
    apt-get autoremove -yqq --purge && \
    rm -rf /var/lib/apt/lists/*

# install python for entrypoint
RUN apt-get update && \
    apt-get install -y --no-install-recommends python3.9

USER $DBMATE_USER

WORKDIR $DBMATE_USER_HOME

COPY databases ./databases

COPY entrypoint.py ./entrypoint.py
ENTRYPOINT [ "python3.9", "./entrypoint.py" ]
