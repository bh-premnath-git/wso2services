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

# Install Python 3.14 from deadsnakes PPA
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.14 \
    python3.14-venv \
    python3.14-dev \
    python3-pip \
    && update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.14 1 \
    && update-alternatives --install /usr/bin/python python /usr/bin/python3.14 1 \
    && rm -rf /var/lib/apt/lists/*

# Update CA certificates and upgrade pip with latest certificates
RUN update-ca-certificates && \
    pip install --ignore-installed --upgrade pip setuptools wheel certifi && \
    pip config set global.trusted-host "pypi.org files.pythonhosted.org pypi.python.org"

# Set working directory
WORKDIR /app

# Copy common dependencies first
COPY ./common /app/common

# Copy service requirements and install
COPY ./profile_service/requirements.txt /app/profile_service/requirements.txt
RUN pip install --no-cache-dir --trusted-host pypi.org --trusted-host files.pythonhosted.org --ignore-installed cryptography -r profile_service/requirements.txt

# Copy application code
COPY ./profile_service/app /app/app

# Expose port
EXPOSE 8004

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD curl -f http://localhost:8004/health || exit 1

# Run the application
CMD ["python", "-m", "app.main"]
