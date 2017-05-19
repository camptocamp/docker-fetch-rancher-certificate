#!/bin/bash -e

CATTLE_CONFIG_URL_V2=${CATTLE_CONFIG_URL/v1/v2-beta}
CERT_NAME="$1"
CERT_DIR=${2:-/usr/src/certs}

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

  SOURCE="/usr/src/certs"
  DEST="/usr/local/etc/haproxy/"
  
  rsync -av --delete "$SOURCE" "$DEST"
  
  PID="$(pidof haproxy-systemd-wrapper)"
  if [ -z "$PID" ]; then
      echo "empty \$PID: '$PID'"
      exit 1
  fi
  
  if [ "$PID" -le 1 ]; then
      echo "invalid \$PID: '$PID'"
      exit 1
  fi
  
  echo "About to reload process '$PID'"
  
  kill -HUP "$PID"
  
  sysctl -w net.ipv4.tcp_max_syn_backlog=60000
  sysctl -w net.core.somaxconn=60000
  sysctl -w net.ipv4.tcp_tw_reuse=1
  sysctl -w net.ipv4.tcp_mem="786432 1697152 1945728"
fi
