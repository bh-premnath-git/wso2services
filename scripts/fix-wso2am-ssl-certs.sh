#!/bin/bash
#
# Script to fix WSO2 SSL certificate errors
# This script imports the mkcert root CA certificate into the WSO2 AM and WSO2 IS truststores
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=== WSO2 SSL Certificate Fix ==="
echo ""

# Check if rootCA.pem exists
if [ ! -f "$PROJECT_ROOT/certs/rootCA.pem" ]; then
    echo "ERROR: Root CA certificate not found at $PROJECT_ROOT/certs/rootCA.pem"
    echo "Please run the TLS setup script first to generate certificates."
    exit 1
fi

# Define truststore paths
WSO2AM_TRUSTSTORE="$PROJECT_ROOT/wso2am/repository/resources/security/client-truststore.jks"
WSO2IS_TRUSTSTORE="$PROJECT_ROOT/wso2is/repository/resources/security/client-truststore.p12"

# Function to import certificate into a truststore
import_cert() {
    local truststore_path=$1
    local truststore_type=$2
    local service_name=$3

    if [ ! -f "$truststore_path" ]; then
        echo "⚠ Truststore not found: $truststore_path (skipping $service_name)"
        return 1
    fi

    # Check if certificate is already imported
    if keytool -list -keystore "$truststore_path" -storepass wso2carbon -storetype "$truststore_type" -alias mkcert-local-root &> /dev/null; then
        echo "✓ mkcert root CA already imported in $service_name truststore"
        return 0
    fi

    # Import the certificate
    echo "Importing mkcert root CA certificate into $service_name truststore..."
    if keytool -importcert -noprompt \
        -alias mkcert-local-root \
        -file "$PROJECT_ROOT/certs/rootCA.pem" \
        -keystore "$truststore_path" \
        -storepass wso2carbon \
        -storetype "$truststore_type"; then
        echo "✓ Successfully imported mkcert root CA into $service_name"
        return 0
    else
        echo "✗ Failed to import certificate into $service_name"
        return 1
    fi
}

# Import into WSO2 AM truststore (JKS)
echo "--- WSO2 API Manager ---"
import_cert "$WSO2AM_TRUSTSTORE" "JKS" "WSO2 AM"
AM_RESULT=$?

echo ""

# Import into WSO2 IS truststore (PKCS12)
echo "--- WSO2 Identity Server ---"
import_cert "$WSO2IS_TRUSTSTORE" "PKCS12" "WSO2 IS"
IS_RESULT=$?

echo ""

# Verify the certificates were imported
if [ $AM_RESULT -eq 0 ]; then
    echo "Verifying WSO2 AM certificate..."
    keytool -list -keystore "$WSO2AM_TRUSTSTORE" -storepass wso2carbon -alias mkcert-local-root 2>&1 | head -3
fi

if [ $IS_RESULT -eq 0 ]; then
    echo "Verifying WSO2 IS certificate..."
    keytool -list -keystore "$WSO2IS_TRUSTSTORE" -storepass wso2carbon -storetype PKCS12 -alias mkcert-local-root 2>&1 | head -3
fi

echo ""
echo "=== SSL Certificate Fix Complete ==="
echo ""
echo "Next steps:"
echo "1. Restart the WSO2 containers:"
echo "   docker-compose restart wso2am wso2is"
echo ""
echo "2. Check WSO2 AM logs for SSL errors:"
echo "   docker logs wso2am 2>&1 | grep -E 'PKIX path building failed'"
echo ""
echo "3. Check WSO2 IS logs for SSL errors:"
echo "   docker logs wso2is 2>&1 | grep -E 'PKIX path building failed'"
echo ""
echo "4. Verify SSL errors are resolved (no new errors should appear)"
echo ""
