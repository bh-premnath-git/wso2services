FROM wso2/wso2is:7.1.0

# Copy PostgreSQL JDBC driver
COPY --chown=wso2carbon:wso2 lib/postgresql-42.7.4.jar /home/wso2carbon/wso2is-7.1.0/repository/components/lib/

# Copy APIM notification event handler for token revocation
COPY --chown=wso2carbon:wso2 repository/components/dropins/wso2is.notification.event.handlers-2.0.8.jar /home/wso2carbon/wso2is-7.1.0/repository/components/dropins/

# Copy deployment.toml with hardcoded values
COPY --chown=wso2carbon:wso2 repository/conf/deployment.toml /home/wso2carbon/wso2is-7.1.0/repository/conf/deployment.toml

# Copy security artifacts
COPY --chown=wso2carbon:wso2 repository/resources/security/client-truststore.p12 /home/wso2carbon/wso2is-7.1.0/repository/resources/security/client-truststore.p12
COPY --chown=wso2carbon:wso2 repository/resources/security/wso2carbon.p12 /home/wso2carbon/wso2is-7.1.0/repository/resources/security/wso2carbon.p12

EXPOSE 9443 9763 5005

# Health check
HEALTHCHECK --interval=30s --timeout=10s --retries=5 \
  CMD curl -k -f https://localhost:9443/carbon/admin/login.jsp || exit 1
