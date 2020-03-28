#!/bin/bash

set -e

build_pebble() {
    local pebble_dir="${TRAVIS_BUILD_DIR}/src/github.com/letsencrypt/pebble"
    if [[ ! -d "$pebble_dir" ]]; then
        git clone https://github.com/letsencrypt/pebble.git "$pebble_dir"
    fi
    pushd "$pebble_dir"
    git checkout v2.1.0
    docker build --force-rm --file ./docker/pebble/linux.Dockerfile --tag letsencrypt/pebble:v2.1.0 .
    docker build --force-rm --file ./docker/pebble-challtestsrv/linux.Dockerfile --tag letsencrypt/pebble-challtestsrv:v2.1.0 .
    popd
}

setup_pebble() {
    docker network create --driver=bridge --subnet=10.30.50.0/24 acme_net
    curl https://raw.githubusercontent.com/letsencrypt/pebble/v2.1.0/test/certs/pebble.minica.pem > "${TRAVIS_BUILD_DIR}/pebble.minica.pem"
    cat "${TRAVIS_BUILD_DIR}/pebble.minica.pem"

    docker run -d \
        --name pebble \
        --volume "${TRAVIS_BUILD_DIR}/test/setup/pebble-config.json:/test/config/pebble-config.json" \
        --env PEBBLE_WFE_NONCEREJECT=0 \
        --network acme_net \
        --ip="10.30.50.2" \
        --publish 14000:14000 \
        letsencrypt/pebble:v2.1.0 \
        pebble -config /test/config/pebble-config.json -dnsserver 10.30.50.3:8053

    docker run -d \
        --name challtestserv \
        --network acme_net \
        --ip="10.30.50.3" \
        --publish 8055:8055 \
        letsencrypt/pebble-challtestsrv:v2.1.0 \
        pebble-challtestsrv -tlsalpn01 ""
}

wait_for_pebble() {
    for endpoint in 'https://pebble:14000/dir' 'http://pebble-challtestsrv:8055'; do
        while ! curl -k "$endpoint" >/dev/null 2>&1; do
            if [ $((i * 5)) -gt $((5 * 60)) ]; then
                echo "$endpoint was not available under 5 minutes, timing out."
                exit 1
            fi
            i=$((i + 1))
            sleep 5
        done
    done
}

setup_pebble_challtestserv() {
    curl -X POST -d '{"ip":"10.30.50.1"}' http://pebble-challtestsrv:8055/set-default-ipv4
    curl -X POST -d '{"ip":""}' http://pebble-challtestsrv:8055/set-default-ipv6
    curl -X POST -d '{"host":"lim.it", "addresses":["10.0.0.0"]}' http://pebble-challtestsrv:8055/add-a
}

build_pebble
setup_pebble
wait_for_pebble
setup_pebble_challtestserv
