# Base image (you can choose another if needed)
FROM mcr.microsoft.com/devcontainers/base:ubuntu

# Install prerequisites
RUN apt-get update && apt-get install -y \
    curl \
    unzip \
    bash \
    git \
    && rm -rf /var/lib/apt/lists/*

# Copy your custom install script
COPY install-tools.sh /usr/local/bin/install-tools.sh

# Make it executable
RUN chmod +x /usr/local/bin/install-tools.sh

# (Optional) Define entrypoint or shell if needed
SHELL ["/bin/bash", "-c"]
