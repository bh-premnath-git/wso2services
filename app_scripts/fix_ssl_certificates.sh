#!/usr/bin/env bash

################################################################################
# Fix SSL Certificate Trust Between WSO2 AM and WSO2 IS
#
# Imports WSO2 IS certificate into WSO2 AM's truststore
#
# Usage: ./fix_ssl_certificates.sh
################################################################################

set -eo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Fix SSL Certificates - WSO2 AM ↔ WSO2 IS                 ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

log_info "Step 1: Exporting WSO2 IS certificate from P12 keystore..."

# Export IS certificate (WSO2 IS 7.x uses P12 format)
EXPORT_OUTPUT=$(docker compose exec -T wso2is keytool -export \
  -alias wso2carbon \
  -file /tmp/wso2is-cert.pem \
  -keystore /home/wso2carbon/wso2is-7.1.0/repository/resources/security/wso2carbon.p12 \
  -storetype PKCS12 \
  -storepass wso2carbon \
  -noprompt 2>&1)

if echo "$EXPORT_OUTPUT" | grep -q "Certificate stored"; then
  log_success "Certificate exported from P12 keystore"
else
  log_error "Failed to export certificate"
  echo "$EXPORT_OUTPUT"
  exit 1
fi
echo ""

log_info "Step 2: Copying certificate to WSO2 AM container..."

# Copy cert from IS to host
docker compose cp wso2is:/tmp/wso2is-cert.pem /tmp/wso2is-cert.pem

# Copy cert from host to AM
docker compose cp /tmp/wso2is-cert.pem wso2am:/tmp/wso2is-cert.pem

log_success "Certificate copied to AM container"
echo ""

log_info "Step 3: Importing certificate into WSO2 AM truststore..."

# Import into AM's client-truststore
IMPORT_OUTPUT=$(docker compose exec -T wso2am keytool -import \
  -alias wso2is \
  -file /tmp/wso2is-cert.pem \
  -keystore /home/wso2carbon/wso2am-4.5.0/repository/resources/security/client-truststore.jks \
  -storepass wso2carbon \
  -noprompt 2>&1)

if echo "$IMPORT_OUTPUT" | grep -qE "Certificate (was added|already exists)"; then
  if echo "$IMPORT_OUTPUT" | grep -q "already exists"; then
    log_success "Certificate already exists in truststore"
  else
    log_success "Certificate imported into client-truststore.jks"
  fi
else
  log_error "Failed to import certificate"
  echo "$IMPORT_OUTPUT"
  exit 1
fi
echo ""

log_info "Step 4: Restarting WSO2 API Manager..."

docker compose restart wso2am

log_info "Waiting for WSO2 AM to restart..."
sleep 30

until curl -sk https://localhost:9443/carbon/ -o /dev/null 2>&1; do
  echo "   Waiting..."
  sleep 5
done

log_success "WSO2 AM restarted and ready"
echo ""

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  ✅ SSL Certificates Fixed                                 ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "Next step: Generate application keys"
echo "  Run: ./app_scripts/test_keymanager_key_generation.sh"
echo ""
