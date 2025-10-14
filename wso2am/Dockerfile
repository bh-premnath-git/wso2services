FROM wso2/wso2am:4.5.0

# Copy PostgreSQL JDBC driver
COPY --chown=wso2carbon:wso2 lib/postgresql-42.7.4.jar /home/wso2carbon/wso2am-4.5.0/repository/components/lib/

# Copy custom configuration
COPY --chown=wso2carbon:wso2 conf/ /home/wso2carbon/wso2am-4.5.0/repository/conf/

# Expose required ports
# 9443: Management Console, Publisher, Developer Portal (HTTPS)
# 8280: API Gateway HTTP
# 8243: API Gateway HTTPS
# 9999: JMX RMI Registry Port
# 11111: JMX RMI Server Port
# 5005: Debug Port
EXPOSE 9443 8280 8243 9999 11111 5005

# Health check
HEALTHCHECK --interval=30s --timeout=10s --retries=5 \
  CMD curl -k -f https://localhost:9443/carbon/admin/login.jsp || exit 1
