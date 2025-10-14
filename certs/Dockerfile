FROM alpine/mkcert

# Set working directory for certificate output
WORKDIR /root/certs

# Create volume mount point for certificate output
VOLUME ["/root/certs"]

# Default command - generate certs for common localhost names
# Override with custom domains when running the container
CMD ["mkcert", "-help"]