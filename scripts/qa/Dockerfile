FROM ubuntu:26.04@sha256:6a06111c3b0a8600feadb270aec771dc239bf407b25625f93f44ab00e11f4d3c

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       ca-certificates libstdc++6 libtinfo6 libssl3t64 zlib1g libzstd1 \
    && rm -rf /var/lib/apt/lists/*

ARG APP_UID=1000
ARG APP_GID=1000
WORKDIR /app
COPY --chown=${APP_UID}:${APP_GID} . .
USER ${APP_UID}:${APP_GID}
ENV LANG=C.UTF-8
CMD ["/app/bin/vxpipe", "start"]
