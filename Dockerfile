ARG VERSION="stable"
ARG FLUTTER_HOME="/opt/flutter"
ARG FLUTTER_PUB_CACHE="/var/tmp/.pub_cache"
ARG FLUTTER_URL="https://github.com/flutter/flutter"

FROM alpine:3.18.5 as build

USER root
WORKDIR /

ARG VERSION
ARG FLUTTER_HOME
ARG FLUTTER_PUB_CACHE
ARG FLUTTER_URL

ENV VERSION=$VERSION \
    FLUTTER_HOME=$FLUTTER_HOME \
    FLUTTER_ROOT=$FLUTTER_HOME \
    FLUTTER_PUB_CACHE=$FLUTTER_PUB_CACHE \
    PATH="${PATH}:${FLUTTER_HOME}/bin:${FLUTTER_PUB_CACHE}/bin"

# Install linux dependency and utils
RUN set -eux; mkdir -p /usr/lib /tmp/glibc $FLUTTER_PUB_CACHE \
    && apk --no-cache add bash curl git ca-certificates wget unzip \
    && rm -rf /var/lib/apt/lists/* /var/cache/apk/* /opt/flutter/bin/cache

# https://security.snyk.io/vuln/SNYK-ALPINE316-EXPAT-3062883
RUN apk upgrade expat

# Install & config Flutter
RUN set -eux; git clone -b ${VERSION} --depth 1 "${FLUTTER_URL}.git" "${FLUTTER_ROOT}" \
    && cd "${FLUTTER_ROOT}" \
    && git gc --prune=all

# Get glibc for current architecure
RUN arch=$(uname -m); \
    if [[ $arch == x86_64* ]] || [[ $arch == i*86 ]]; then \
        echo "x86_64 Architecture"; \
        export GLIBC_URL="https://github.com/sgerrand/alpine-pkg-glibc"; \
        export GLIBC_VERSION="2.29-r0"; \
        wget -q -O /etc/apk/keys/sgerrand.rsa.pub https://alpine-pkgs.sgerrand.com/sgerrand.rsa.pub; \
        wget -O /tmp/glibc/glibc.apk ${GLIBC_URL}/releases/download/${GLIBC_VERSION}/glibc-${GLIBC_VERSION}.apk; \
        wget -O /tmp/glibc/glibc-bin.apk ${GLIBC_URL}/releases/download/${GLIBC_VERSION}/glibc-bin-${GLIBC_VERSION}.apk; \
#    elif  [[ $arch == arm* ]] || [[ $arch == aarch* ]]; then \
#        echo "ARM Architecture"; \
#        export GLIBC_URL="https://github.com/Rjerk/alpine-pkg-glibc"; \
#        export GLIBC_VERSION="2.30-r0"; \
#        wget -q -O /etc/apk/keys/rjerk.rsa.pub https://raw.githubusercontent.com/Rjerk/alpine-pkg-glibc/2.30-r0-aarch64/rjerk.rsa.pub; \
#        wget -O /tmp/glibc/glibc.apk ${GLIBC_URL}/releases/download/${GLIBC_VERSION}-arm64/glibc-${GLIBC_VERSION}.apk; \
#        wget -O /tmp/glibc/glibc-bin.apk ${GLIBC_URL}/releases/download/${GLIBC_VERSION}-arm64/glibc-bin-${GLIBC_VERSION}.apk; \
#        else \
#        >&2 echo "Unsupported Architecture"; \
#        exit 1; \
    fi

#RUN find / -xdev | sort > /tmp/after.txt

# Create dependencies
RUN set -eux; for f in \
    /etc/ssl/certs \
    /usr/share/ca-certificates \
    /etc/apk/keys \
    #/etc/group \
    #/etc/passwd \
    ${FLUTTER_HOME} \
    ${FLUTTER_PUB_CACHE} \
    /root \
    /tmp/glibc \
    ; do \
    dir="$(dirname "$f")"; \
    mkdir -p "/build_dependencies$dir"; \
    cp --archive --link --dereference --no-target-directory "$f" "/build_dependencies$f"; \
    done

# Create new clear layer
FROM alpine:3.18.5 as production

ARG VERSION
ARG FLUTTER_HOME
ARG FLUTTER_PUB_CACHE
ARG FLUTTER_URL
ARG GLIBC_VERSION
ARG GLIBC_URL

# Add enviroment variables
ENV FLUTTER_HOME=$FLUTTER_HOME \
    FLUTTER_PUB_CACHE=$PUB_CACHE \
    FLUTTER_ROOT=$FLUTTER_HOME \
    PATH="${PATH}:${FLUTTER_HOME}/bin:${FLUTTER_PUB_CACHE}/bin"

# Copy dependencies
COPY --from=build /build_dependencies/ /

# Install linux dependency and utils
RUN set -eux; mkdir -p /build; apk --no-cache add bash git curl unzip  \
    /tmp/glibc/glibc.apk /tmp/glibc/glibc-bin.apk \
    -u alpine-keys --allow-untrusted

RUN rm -rf /tmp/* \
    /var/lib/apt/lists/* \
    /var/cache/apk/* \
    /usr/share/man/* \
    /usr/share/doc \
    /opt/flutter/bin/cache


RUN dart --disable-analytics
RUN flutter config --no-analytics
RUN flutter doctor
RUN flutter precache --universal

RUN set -eux; git config --global user.email "flutter@dart.dev" \
    && git config --global user.name "Flutter" \
    && git config --global --add safe.directory /opt/flutter

ENV BUILD_DATE="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"

# Add lables
LABEL name="plugfox/flutter:${VERSION}" \
    description="flutter dart base image" \
    license="BSD" \
    vcs-type="git" \
    vcs-url="https://github.com/microscaler/flutter-dart-base" \
    github="https://github.com/microscaler/flutter-dart-base" \
    dockerhub="https://hub.docker.com/r/microscaler/flutter-dart-base" \
    maintainer="<spelltasticsoup@gmail.com>" \
    family="microscaler/flutter" \
    flutter.version="${VERSION}" \
    flutter.home="${FLUTTER_HOME}" \
    flutter.cache="${FLUTTER_PUB_CACHE}" \
    flutter.url="${FLUTTER_URL}"

# By default
USER root
WORKDIR /build
SHELL [ "/bin/bash", "-c" ]
CMD [ "flutter", "doctor" ]