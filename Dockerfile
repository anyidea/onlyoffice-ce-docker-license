ARG product_version=7.5.1
ARG build_number=1
ARG oo_root='/var/www/onlyoffice/documentserver'

## Setup
FROM onlyoffice/documentserver:${product_version}.${build_number} as setup-stage
ARG product_version
ARG build_number
ARG oo_root

ENV PRODUCT_VERSION=${product_version}
ENV BUILD_NUMBER=${build_number}

ARG build_deps="git make g++ curl dirmngr apt-transport-https lsb-release ca-certificates"
RUN apt-get update && apt-get install -y ${build_deps} && \
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource.gpg.key | gpg --dearmor -o /usr/share/keyrings/nodesource-archive-keyring.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/nodesource-archive-keyring.gpg] https://deb.nodesource.com/node_16.x $(lsb_release -c -s) main" | tee /etc/apt/sources.list.d/nodesource.list && \
    apt-get update
RUN npm install -g pkg grunt grunt-cli

WORKDIR /build



## Clone
FROM setup-stage as clone-stage
ARG tag=v${PRODUCT_VERSION}.${BUILD_NUMBER}

RUN git clone --quiet --branch $tag --depth 1 https://github.com/ONLYOFFICE/build_tools.git /build/build_tools
RUN git clone --quiet --branch $tag --depth 1 https://github.com/ONLYOFFICE/server.git      /build/server

# Working mobile editor
RUN git clone --quiet --depth 1 https://github.com/ONLYOFFICE/sdkjs.git       /build/sdkjs
RUN git clone --quiet --depth 1 https://github.com/ONLYOFFICE/web-apps.git    /build/web-apps

## Build
FROM clone-stage as path-stage

# Patch
COPY web-apps.patch /build/web-apps.patch
RUN cd /build/web-apps   && git apply /build/web-apps.patch


COPY server.patch /build/server.patch
RUN cd /build/server   && git apply --ignore-space-change --ignore-whitespace /build/server.patch


## Build
FROM path-stage as build-stage

# build server with license checks patched
WORKDIR /build/server
RUN make
RUN pkg /build/build_tools/out/linux_64/onlyoffice/documentserver/server/FileConverter --targets=node14-linux -o /build/converter
RUN pkg /build/build_tools/out/linux_64/onlyoffice/documentserver/server/DocService --targets=node14-linux --options max_old_space_size=4096 -o /build/docservice

# build web-apps with mobile editing
WORKDIR /build/web-apps/build
RUN ./sprites.sh
RUN npm install
RUN grunt

## Final image
FROM onlyoffice/documentserver:${product_version}.${build_number}
ARG oo_root

#server
COPY --from=build-stage /build/converter  ${oo_root}/server/FileConverter/converter
COPY --from=build-stage /build/docservice ${oo_root}/server/DocService/docservice

# Restore mobile editing using an old version of mobile editor
COPY --from=build-stage /build/web-apps/deploy/web-apps/apps/documenteditor/mobile     ${oo_root}/web-apps/apps/documenteditor/mobile
COPY --from=build-stage /build/web-apps/deploy/web-apps/apps/presentationeditor/mobile ${oo_root}/web-apps/apps/presentationeditor/mobile
COPY --from=build-stage /build/web-apps/deploy/web-apps/apps/spreadsheeteditor/mobile  ${oo_root}/web-apps/apps/spreadsheeteditor/mobile
