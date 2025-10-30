# Pre-requisites
mkdir -p certs
docker compose run --rm --entrypoint sh mkcert -lc \
'mkcert -install && cp "$(mkcert -CAROOT)/rootCA.pem" /certs/rootCA.pem'

# Take ownership of all certs created by containers
sudo chown -R "$(id -u)":"$(id -g)" certs


# 1) mkcert root + one shared leaf for all names
docker compose run --rm --entrypoint sh mkcert -lc '
  mkcert -install &&
  mkcert -cert-file /certs/shared.pem -key-file /certs/shared-key.pem \
         am.local is.local wso2am wso2is localhost 127.0.0.1 &&
  cp "$(mkcert -CAROOT)/rootCA.pem" /certs/rootCA.pem
'

# 2) Make a single PKCS12 from the shared PEMs
docker run --rm -v "$PWD:/work" -w /work alpine:3.20 sh -lc '
  apk add --no-cache openssl &&
  openssl pkcs12 -export \
    -in certs/shared.pem -inkey certs/shared-key.pem \
    -certfile certs/rootCA.pem \
    -name wso2carbon \
    -out certs/shared.p12 \
    -passout pass:wso2carbon
'

# 3) IS keystore (PKCS12) -> place as file (MUST exist before up)
cp -f certs/shared.p12 wso2is/repository/resources/security/wso2carbon.p12

# if permissions barked earlier, take ownership first
sudo chown -R "$(id -u)":"$(id -g)" wso2am/repository/resources/security

# remove the existing files
rm -f wso2am/repository/resources/security/wso2carbon.jks
rm -f wso2am/repository/resources/security/client-truststore.jks
rm -f wso2is/repository/resources/security/wso2carbon.p12
rm -f wso2is/repository/resources/security/client-truststore.p12

# 4) APIM keystore (convert PKCS12 -> JKS)
docker run --rm -v "$PWD:/work" -w /work eclipse-temurin:17-jdk bash -lc '
  keytool -importkeystore \
    -srckeystore certs/shared.p12 -srcstoretype PKCS12 -srcstorepass wso2carbon \
    -destkeystore wso2am/repository/resources/security/wso2carbon.jks \
    -deststoretype JKS -deststorepass wso2carbon -destkeypass wso2carbon \
    -srcalias wso2carbon -destalias wso2carbon
'

# 5) Truststores (create if absent) and import mkcert root
# APIM truststore (JKS)
if [ ! -f wso2am/repository/resources/security/client-truststore.jks ]; then
  docker run --rm -v "$PWD:/work" -w /work eclipse-temurin:17-jdk bash -lc '
    keytool -importcert -noprompt -alias mkcert-local-root \
      -file certs/rootCA.pem \
      -keystore wso2am/repository/resources/security/client-truststore.jks \
      -storepass wso2carbon -storetype JKS
  '
else
  docker run --rm -v "$PWD:/work" -w /work eclipse-temurin:17-jdk bash -lc '
    keytool -importcert -noprompt -alias mkcert-local-root \
      -file certs/rootCA.pem \
      -keystore wso2am/repository/resources/security/client-truststore.jks \
      -storepass wso2carbon
  '
fi

# IS truststore (PKCS12)
if [ ! -f wso2is/repository/resources/security/client-truststore.p12 ]; then
  docker run --rm -v "$PWD:/work" -w /work eclipse-temurin:17-jdk bash -lc '
    keytool -importcert -noprompt -alias mkcert-local-root \
      -file certs/rootCA.pem \
      -keystore wso2is/repository/resources/security/client-truststore.p12 \
      -storepass wso2carbon -storetype PKCS12
  '
else
  docker run --rm -v "$PWD:/work" -w /work eclipse-temurin:17-jdk bash -lc '
    keytool -importcert -noprompt -alias mkcert-local-root \
      -file certs/rootCA.pem \
      -keystore wso2is/repository/resources/security/client-truststore.p12 \
      -storepass wso2carbon -storetype PKCS12
  '
fi

# 6) Sanity: confirm files are FILES
file wso2am/repository/resources/security/wso2carbon.jks
file wso2am/repository/resources/security/client-truststore.jks
file wso2is/repository/resources/security/wso2carbon.p12
file wso2is/repository/resources/security/client-truststore.p12

echo "Preflight OK."
▶️ Bring up & verify
bash
Copy code
docker compose up -d --build

# Listeners up?
docker exec wso2am bash -lc 'ss -ltn | grep :9443 || echo NOT-LISTENING'
docker exec wso2is  bash -lc 'ss -ltn | grep :9443 || echo NOT-LISTENING'

# Host → containers (trusted by mkcert CA)
curl --cacert certs/rootCA.pem https://localhost:9443/services/ | head
curl --cacert certs/rootCA.pem https://localhost:9444/oauth2/jwks | head

# Container → container (names match SANs)
docker exec -it wso2am bash -lc 'curl -s https://is.local:9443/oauth2/jwks | head'
docker exec -it wso2is bash -lc 'curl -s https://am.local:9443/services/ | head'
If anything fails, check logs for keystore/transport errors:

bash
Copy code
docker logs wso2am | tail -n 200
docker logs wso2is  | tail -n 200
---------------------