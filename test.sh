#!/usr/bin/env bash
# Copyright 2020 Red Hat, Inc
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

COLORS_RED=$(tput setab 1)
COLORS_RESET=$(tput sgr0) # No Color
LOG_LEVEL="fatal"
VERBOSE=false

function cleanup() {
    print_descendent_pids() {
        pids=$(pgrep -P "$1")
        echo "$pids"
        for pid in $pids; do
            print_descendent_pids "$pid"
        done
    }

    echo Exiting and killing all children...
    for pid in $(print_descendent_pids $$); do
        if ! kill "$pid" &>/dev/null; then
            # wait for it to stop correctly
            sleep 1
            kill -9 "$pid" &>/dev/null
        fi
    done
    sleep 1
}
trap cleanup EXIT

go clean -testcache

if go build -race; then
    echo "Service build ok"
else
    echo "Build failed"
    exit 1
fi

function start_service() {
    echo "Starting a service"
    INSIGHTS_CONTENT_SERVICE__LOGGING__LOG_LEVEL=$LOG_LEVEL \
    INSIGHTS_CONTENT_SERVICE_CONFIG_FILE=./tests/tests \
      ./insights-content-service ||
      echo -e "${COLORS_RED}service exited with error${COLORS_RESET}" &
    # shellcheck disable=2181
    if [ $? -ne 0 ]; then
        echo "Could not start the service"
        exit 1
    fi
}

function test_rest_api() {
    start_service

    echo "Building REST API tests utility"
    if go build -o rest-api-tests tests/rest_api_tests.go; then
        echo "REST API tests build ok"
    else
        echo "Build failed"
        return 1
    fi
    sleep 1
    curl http://localhost:8080/api/v1/ || {
        echo -e "${COLORS_RED}server is not running(for some reason)${COLORS_RESET}"
        exit 1
    }

    if [ "$VERBOSE" = true ]; then
        ./rest-api-tests 2>&1
    else
        ./rest-api-tests 2>&1 | grep -v -E "^Pass "
    fi

    return $?
}

test_rest_api
EXIT_VALUE=$?

echo -e "------------------------------------------------------------------------------------------------"

exit $EXIT_VALUE
