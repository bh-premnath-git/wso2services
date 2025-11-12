FROM wso2/wso2is:7.2.0

USER root

ENV MYSQL_CONNECTOR_VERSION=8.0.33
ENV WSO2_SERVER_HOME=/home/wso2carbon/wso2is-7.2.0

# Download MySQL Connector (artifact name changed to mysql-connector-j in 8.0.33+)
ADD --chown=wso2carbon:wso2 https://repo1.maven.org/maven2/com/mysql/mysql-connector-j/${MYSQL_CONNECTOR_VERSION}/mysql-connector-j-${MYSQL_CONNECTOR_VERSION}.jar ${WSO2_SERVER_HOME}/repository/components/lib/

USER wso2carbon

EXPOSE 9443 9763 5005

# Health check
HEALTHCHECK --interval=30s --timeout=10s --retries=5 \
  CMD curl -k -f https://localhost:9443/carbon/admin/login.jsp || exit 1
