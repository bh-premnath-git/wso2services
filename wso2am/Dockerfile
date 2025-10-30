FROM wso2/wso2am:4.5.0

EXPOSE 9443 8280 8243 9999 11111 5005

# Health check
HEALTHCHECK --interval=30s --timeout=10s --retries=5 \
  CMD curl -k -f https://localhost:9443/carbon/admin/login.jsp || exit 1
