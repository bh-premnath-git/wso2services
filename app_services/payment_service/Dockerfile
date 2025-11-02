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

# Set working directory
WORKDIR /app

# Copy common dependencies first
COPY ./common /app/common

# Copy service requirements and install
COPY ./payment_service/requirements.txt /app/payment_service/requirements.txt
RUN pip install --no-cache-dir -r payment_service/requirements.txt

# Copy application code and adapters
COPY ./payment_service/app /app/app
COPY ./payment_service/adapters /app/adapters

# Expose port
EXPOSE 8003

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD curl -f http://localhost:8003/health || exit 1

# Run the application
CMD ["python", "-m", "app.main"]
