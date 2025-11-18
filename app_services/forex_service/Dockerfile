FROM ubuntu:noble

# Set environment variables
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    DEBIAN_FRONTEND=noninteractive \
    PATH="/root/.cargo/bin:${PATH}"

# Install system dependencies and add deadsnakes PPA
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    wget \
    git \
    build-essential \
    libssl-dev \
    libffi-dev \
    pkg-config \
    zlib1g-dev \
    software-properties-common \
    && add-apt-repository ppa:deadsnakes/ppa -y \
    && rm -rf /var/lib/apt/lists/*

# Install Python 3.12 from deadsnakes PPA (stable, boto3-compatible)
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.12 \
    python3.12-venv \
    python3.12-dev \
    python3-pip \
    && update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.12 1 \
    && update-alternatives --install /usr/bin/python python /usr/bin/python3.12 1 \
    && rm -rf /var/lib/apt/lists/*

# Update CA certificates and upgrade pip with latest certificates
RUN update-ca-certificates && \
    pip install --break-system-packages --ignore-installed --upgrade pip setuptools wheel certifi && \
    pip config set global.trusted-host "pypi.org files.pythonhosted.org pypi.python.org"

# Set working directory
WORKDIR /app

# Copy common dependencies first
COPY ./common /app/common

# Copy service requirements and install
COPY ./forex_service/requirements.txt /app/forex_service/requirements.txt
RUN pip install --break-system-packages --no-cache-dir --trusted-host pypi.org --trusted-host files.pythonhosted.org -r forex_service/requirements.txt

# Copy application code
COPY ./forex_service/app /app/app

# Expose port
EXPOSE 8001

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD curl -f http://localhost:8001/health || exit 1

# Run the application
CMD ["python", "-m", "app.main"]
