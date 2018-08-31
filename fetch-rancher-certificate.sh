#!/bin/bash -e

CATTLE_CONFIG_URL_V2=${CATTLE_CONFIG_URL/v1/v2-beta}
CERT_NAME="$1"
CERT_DIR=${2:-/usr/local/etc/haproxy/certs}

ALL_CERTS_JSON=$(curl -s  -H "Authorization: ${CATTLE_AGENT_INSTANCE_AUTH}" "${CATTLE_CONFIG_URL_V2}/certificates")
TEMP_DIR=$(mktemp -d -p /tmp)

function get_cert_val() {
  local name="$1" k="$2"
  if test $? -ne 0; then
    echo "Can't fetch '${name}' certificate." >&2
    exit 1
  fi
  jq -r ".data[] | select(.name == \"${name}\").${k}" <<<"${ALL_CERTS_JSON}"
}

function get_cert() {
  local name="$1"

  echo -n "Fetching '${name}' cert... "

  get_cert_val "$name" "key" > "${TEMP_DIR}/${name}.pem"
  get_cert_val "$name" "cert" >> "${TEMP_DIR}/${name}.pem"
  get_cert_val "$name" "certchain" > "${TEMP_DIR}/${name}.certchain"

  if [[ $(< "${TEMP_DIR}/${name}.certchain") != "null" ]]; then
    cat "${TEMP_DIR}/${name}.certchain" >> "${TEMP_DIR}/${name}.pem"
  fi
  rm "${TEMP_DIR}/${name}.certchain"
  echo "done."
}

function get_all_certs() {
  jq -r ".data[].name" <<<"${ALL_CERTS_JSON}" | while read c; do
    get_cert "$c"
  done
}

mkdir -p "$CERT_DIR"

if test -z "$CERT_NAME" -o "$CERT_NAME" = "ALL" ; then
  get_all_certs
else
  get_cert "$CERT_NAME"
fi

if diff -N -q -r "$CERT_DIR" "$TEMP_DIR" > /dev/null; then
  echo "No updates found, cleaning up."
  rm -rf "$TEMP_DIR"
else
  echo -n "Updates found, about to reload HAProxy... "
  rm -f "$CERT_DIR"/*
  mv "$TEMP_DIR"/* "$CERT_DIR"
  rm -rf "$TEMP_DIR"

  pkill -USR2 -o -e -f '^haproxy\s.*-f\s+/usr/local/etc/haproxy/reverse-proxy.cfg'
  if [ $? -gt 0 ]; then echo 'failed!'; else echo 'done.'; fi
fi
