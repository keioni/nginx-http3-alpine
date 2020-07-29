FROM alpine:3 as download

RUN set -eux; \
    apk update && apk add --no-cache --virtual .build-deps \
        curl \
        git \
        patch \
        tar \
    ; \
    \
    curl -O https://nginx.org/download/nginx-1.16.1.tar.gz; \
    tar zxvf nginx-1.16.1.tar.gz; \
    git clone --depth 1 --recursive https://github.com/cloudflare/quiche; \
    cd nginx-1.16.1; \
    patch -p01 < ../quiche/extras/nginx/nginx-1.16.patch; \
    \
    cd ..; \
    mv nginx-1.16.1 nginx; \
    \
    apk del --no-network .build-deps


FROM alpine:3 AS build

ENV prefix="/usr/local/nginx"

COPY --from=download /nginx /nginx/
COPY --from=download /quiche /quiche/

RUN set -eux; \
    apk update && apk add --no-cache --virtual .build-deps \
        binutils \
        cargo \
        cmake \
        curl \
        gcc \
        g++ \
        make \
        nghttp2-dev \
        pcre-dev \
        rust \
        tar \
        zlib-dev \
    ; \
    \
    cd /nginx; \
    ./configure --prefix=$prefix --build=quiche-alpine --with-http_ssl_module --with-http_v2_module --with-http_v3_module --with-openssl=../quiche/deps/boringssl --with-quiche=../quiche; \
    make; \
    make install; \
    strip $prefix/sbin/nginx; \
    \
    cd ..; \
    rm -rf /nginx /quiche; \
    apk del --no-network .build-deps


FROM alpine:3 as makecert

RUN set -eux; \
    apk update && apk add --no-cache openssl; \
    mkdir /conf; \
    openssl genrsa 2048 > /conf/cert.key; \
    openssl req -new -subj "/CN=localhost" -key /conf/cert.key > /conf/cert.csr; \
    openssl x509 -days 3650 -req -signkey /conf/cert.key < /conf/cert.csr > /conf/cert.crt; \
    rm /conf/cert.csr; \
    apk del --no-network openssl


FROM alpine:3

ENV prefix="/usr/local/nginx"
WORKDIR $prefix

COPY --from=build $prefix $prefix
COPY --from=makecert /conf/ $prefix/conf/

COPY nginx.conf $prefix/conf/
COPY nginx-foreground.conf $prefix/conf/
COPY nginx-runner /usr/local/sbin/

RUN set -eux; \
    apk update && apk add --virtual .nginx-rundeps pcre libgcc

EXPOSE 443/udp
EXPOSE 443/tcp

CMD ["nginx-runner"]

