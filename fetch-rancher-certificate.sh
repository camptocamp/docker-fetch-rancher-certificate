#!/bin/bash -ex

CATTLE_CONFIG_URL_V2=${CATTLE_CONFIG_URL/v1/v2-beta}
CERT_NAME="$1"
CERT_DIR=${2:-/usr/local/etc/haproxy/certs}

function get_cert_val() {
  local name="$1" k="$2"
  json=$(curl -s  -H "Authorization: ${CATTLE_AGENT_INSTANCE_AUTH}" "${CATTLE_CONFIG_URL_V2}/certificates")
  if test $? -ne 0; then
    echo "Can't fetch ${name} certificate." >&2
    exit 1
  fi
  jq -r ".data[] | select(.name == \"${name}\").${k}" <<<"${json}"
}

if test -z "$CERT_NAME"; then
  echo "Please specify certname" >&2
  exit 1
fi

mkdir -p "$CERT_DIR"

TEMP_DIR=$(mktemp -d -p /tmp)
get_cert_val "$CERT_NAME" "key" > "${TEMP_DIR}/${CERT_NAME}.pem"
get_cert_val "$CERT_NAME" "cert" >> "${TEMP_DIR}/${CERT_NAME}.pem"
get_cert_val "$CERT_NAME" "certchain" > "${TEMP_DIR}/${CERT_NAME}.certchain"

if [[ $(< "${TEMP_DIR}/${CERT_NAME}.certchain") != "null" ]]; then
  cat "${TEMP_DIR}/${CERT_NAME}.certchain" >> "${TEMP_DIR}/${CERT_NAME}.pem"
fi
rm "${TEMP_DIR}/${CERT_NAME}.certchain"

if diff -N -q -r "$CERT_DIR" "$TEMP_DIR" > /dev/null; then
  rm -rf "$TEMP_DIR"
else
  cp "$TEMP_DIR"/* "$CERT_DIR"
  rm -rf "$TEMP_DIR"

  pkill -HUP -f haproxy-systemd-wrapper
fi
