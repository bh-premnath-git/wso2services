FROM wso2/wso2is:7.1.0

# Copy Key Manager extensions to the identity server home
COPY dockerfiles/is-as-km/dropins /home/wso2carbon/wso2is-7.1.0/repository/components/dropins/

# Copy Key Manager webapps to the identity server home
COPY dockerfiles/is-as-km/webapps /home/wso2carbon/wso2is-7.1.0/repository/deployment/server/webapps/

# Add MySQL connector for database connectivity
ADD --chown=wso2carbon:wso2 wso2/reposistory/components/lib/mysql-connector-j-8.0.33.jar /home/wso2carbon/wso2is-7.1.0/repository/components/lib/mysql-connector-j-8.0.33.jar