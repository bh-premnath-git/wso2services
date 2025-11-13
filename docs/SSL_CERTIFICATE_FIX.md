# WSO2 API Manager SSL Certificate Error Fix

## Problem

WSO2 API Manager (wso2am) was experiencing SSL certificate validation errors when trying to make internal HTTPS calls. The error logs showed:

```
ERROR - APIUtil Failed to retrieve /internal/data/v1/* from remote endpoint:
PKIX path building failed: sun.security.provider.certpath.SunCertPathBuilderException:
unable to find valid certification path to requested target
```

These errors affected:
- Internal data synchronization endpoints
- Key Manager configuration retrieval
- Subscription data retrieval
- Gateway notifications
- Traffic manager connections (ssl://172.19.0.13:9711)

## Root Cause

The WSO2 API Manager's truststore (`client-truststore.jks`) was missing the mkcert root CA certificate. When WSO2 AM attempted to make HTTPS calls to internal endpoints or other WSO2 services, it could not validate the SSL certificates because the root CA was not trusted.

## Solution

### Automated Fix

Run the provided script to automatically import the mkcert root CA certificate:

```bash
./scripts/fix-wso2am-ssl-certs.sh
```

Then restart the WSO2 AM container:

```bash
docker-compose restart wso2am
```

### Manual Fix

If you prefer to fix this manually, follow these steps:

1. **Import the mkcert root CA certificate into the WSO2 AM truststore:**

   ```bash
   keytool -importcert -noprompt \
     -alias mkcert-local-root \
     -file certs/rootCA.pem \
     -keystore wso2am/repository/resources/security/client-truststore.jks \
     -storepass wso2carbon
   ```

2. **Add truststore configuration to deployment.toml** (if not already present):

   Edit `wso2am/repository/conf/deployment.toml` and add:

   ```toml
   [truststore]
   file_name = "client-truststore.jks"
   type = "JKS"
   password = "wso2carbon"
   ```

3. **Verify the certificate was imported:**

   ```bash
   keytool -list -keystore wso2am/repository/resources/security/client-truststore.jks \
     -storepass wso2carbon -alias mkcert-local-root
   ```

4. **Restart the WSO2 AM container:**

   ```bash
   docker-compose restart wso2am
   ```

## Verification

After applying the fix and restarting the container, verify that the SSL errors are resolved:

```bash
# Wait for the container to start up (30-60 seconds)
sleep 60

# Check for SSL errors in the logs
docker logs wso2am 2>&1 | grep -E "PKIX path building failed" | tail -20
```

If the fix is successful, you should see no new PKIX errors in the logs.

You can also verify the WSO2 AM is functioning correctly by:

1. **Accessing the management console:**
   - URL: https://localhost:9443/carbon
   - Username: admin
   - Password: admin

2. **Checking the gateway health:**
   ```bash
   curl -k https://localhost:9443/services/
   ```

## Prevention

To prevent this issue in future deployments:

1. Always run the complete TLS setup script from `TLS-Setup.md` before starting the containers
2. The updated `TLS-Setup.md` now includes a verification step (step 7) that checks if the mkcert root CA is in the truststores
3. Consider adding this fix to your CI/CD pipeline or initialization scripts

## Technical Details

### Why This Fix Works

WSO2 API Manager uses Java's KeyStore and TrustStore mechanism for SSL/TLS:

- **KeyStore** (`wso2carbon.jks`): Contains the server's private key and certificate for incoming HTTPS connections
- **TrustStore** (`client-truststore.jks`): Contains trusted CA certificates for validating outbound HTTPS connections

When WSO2 AM makes internal HTTPS calls (e.g., to `/internal/data/v1/*` endpoints), it uses the TrustStore to validate the SSL certificate of the target endpoint. Since these endpoints use certificates signed by the mkcert CA, the mkcert root CA certificate must be in the TrustStore.

### Files Modified

1. `wso2am/repository/resources/security/client-truststore.jks` - Added mkcert root CA certificate
2. `wso2am/repository/conf/deployment.toml` - Added explicit truststore configuration
3. `scripts/fix-wso2am-ssl-certs.sh` - New script for automated fix
4. `TLS-Setup.md` - Added verification step
5. `docs/SSL_CERTIFICATE_FIX.md` - This documentation

## Related Issues

- WSO2 AM startup SSL errors
- Internal data synchronization failures
- Key Manager configuration retrieval failures
- Gateway heartbeat notifier errors
- Traffic manager connection errors

## References

- [WSO2 API Manager Documentation - Configuring Keystores](https://apim.docs.wso2.com/en/latest/install-and-setup/setup/security/configuring-keystores/configuring-keystores-in-wso2-api-manager/)
- [mkcert - Simple zero-config tool for making locally-trusted development certificates](https://github.com/FiloSottile/mkcert)
