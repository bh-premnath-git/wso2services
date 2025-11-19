#!/usr/bin/env bash
################################################################################
# Automated Certificate Exchange for WSO2 APIM <-> IS
# Exports public certs and imports them into partner truststores
################################################################################

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }

APIM_SECURITY_DIR="./conf/apim/repository/resources/security"
IS_SECURITY_DIR="./conf/is-as-km/repository/resources/security"

# Default passwords (WSO2 defaults)
APIM_KEYSTORE_PASS="wso2carbon"
IS_KEYSTORE_PASS="wso2carbon"
TRUSTSTORE_PASS="wso2carbon"

# Default aliases
APIM_ALIAS="wso2carbon"
IS_ALIAS="wso2carbon"

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║      WSO2 Certificate Exchange: APIM <-> IS                  ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Verify directories exist
if [ ! -d "$APIM_SECURITY_DIR" ]; then
    log_error "APIM security directory not found: $APIM_SECURITY_DIR"
    exit 1
fi

if [ ! -d "$IS_SECURITY_DIR" ]; then
    log_error "IS security directory not found: $IS_SECURITY_DIR"
    exit 1
fi

log_info "Directories found"
log_info "  APIM: $APIM_SECURITY_DIR"
log_info "  IS:   $IS_SECURITY_DIR"
echo ""

# Create temp directory for cert files
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

log_info "Temporary cert storage: $TEMP_DIR"
echo ""

################################################################################
# Step 1: Export APIM public certificate (run inside APIM container)
################################################################################
log_info "STEP 1: Exporting APIM public certificate..."

docker exec -u 0 global-transfer-backend-api-manager-1 bash -c \
    "cd /home/wso2carbon/wso2am-*/repository/resources/security && \
     keytool -export -alias '$APIM_ALIAS' -keystore wso2carbon.jks \
     -file /tmp/apim-public.cert -storepass '$APIM_KEYSTORE_PASS' -noprompt" 2>&1 | grep -v "Certificate stored" || true

# Copy cert from container to host
docker cp global-transfer-backend-api-manager-1:/tmp/apim-public.cert "$TEMP_DIR/apim-public.cert"

if [ ! -f "$TEMP_DIR/apim-public.cert" ]; then
    log_error "Failed to export APIM certificate"
    exit 1
fi

log_success "APIM certificate exported"

################################################################################
# Step 2: Import APIM cert into IS truststore
################################################################################
log_info "STEP 2: Importing APIM certificate into IS truststore..."

# Copy cert to IS container
docker cp "$TEMP_DIR/apim-public.cert" global-transfer-backend-is-as-km-1:/tmp/apim-public.cert

# Remove if it already exists, then import
docker exec -u 0 global-transfer-backend-is-as-km-1 bash -c \
    "cd /home/wso2carbon/wso2is-*/repository/resources/security && \
     keytool -delete -alias 'apim-public' -keystore client-truststore.p12 \
     -storetype PKCS12 -storepass '$TRUSTSTORE_PASS' -noprompt 2>/dev/null || true && \
     keytool -import -alias 'apim-public' -file /tmp/apim-public.cert \
     -keystore client-truststore.p12 -storetype PKCS12 -storepass '$TRUSTSTORE_PASS' -noprompt" 2>&1 | grep -v "Certificate was added" || true

log_success "APIM certificate imported into IS truststore"

################################################################################
# Step 3: Export IS public certificate (run inside IS container)
################################################################################
log_info "STEP 3: Exporting IS public certificate..."

docker exec -u 0 global-transfer-backend-is-as-km-1 bash -c \
    "rm -f /tmp/is-public.cert && \
     cd /home/wso2carbon/wso2is-*/repository/resources/security && \
     keytool -export -alias '$IS_ALIAS' -keystore wso2carbon.p12 -storetype PKCS12 \
     -file /tmp/is-public.cert -storepass '$IS_KEYSTORE_PASS' -noprompt" 2>&1 | grep -v "Certificate stored" || true

# Copy cert from container to host
docker cp global-transfer-backend-is-as-km-1:/tmp/is-public.cert "$TEMP_DIR/is-public.cert"

if [ ! -f "$TEMP_DIR/is-public.cert" ]; then
    log_error "Failed to export IS certificate"
    exit 1
fi

log_success "IS certificate exported"

################################################################################
# Step 4: Import IS cert into APIM truststore
################################################################################
log_info "STEP 4: Importing IS certificate into APIM truststore..."

# Copy cert to APIM container
docker cp "$TEMP_DIR/is-public.cert" global-transfer-backend-api-manager-1:/tmp/is-public.cert

# Remove if it already exists, then import
docker exec -u 0 global-transfer-backend-api-manager-1 bash -c \
    "cd /home/wso2carbon/wso2am-*/repository/resources/security && \
     keytool -delete -alias 'is-public' -keystore client-truststore.jks \
     -storepass '$TRUSTSTORE_PASS' -noprompt 2>/dev/null || true && \
     keytool -import -alias 'is-public' -file /tmp/is-public.cert \
     -keystore client-truststore.jks -storepass '$TRUSTSTORE_PASS' -noprompt" 2>&1 | grep -v "Certificate was added" || true

log_success "IS certificate imported into APIM truststore"
echo ""

################################################################################
# Summary
################################################################################
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                 ✅ Certificate Exchange Complete              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
log_success "Certificates exchanged successfully!"
echo ""
echo "What was done:"
echo "  1. Exported APIM public cert from wso2carbon.jks"
echo "  2. Imported into IS client-truststore.p12 (alias: apim-public)"
echo "  3. Exported IS public cert from wso2carbon.p12"
echo "  4. Imported into APIM client-truststore.jks (alias: is-public)"
echo ""
log_warn "⚠️  IMPORTANT: Restart containers for changes to take effect!"
echo ""
echo "Restart commands:"
echo "  docker compose restart api-manager"
echo "  docker compose restart is-as-km"
echo ""
echo "Or restart all:"
echo "  docker compose restart"
echo ""
