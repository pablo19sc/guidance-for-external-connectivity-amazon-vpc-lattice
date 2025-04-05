FROM public.ecr.aws/amazonlinux/amazonlinux:2.0.20230404.0-arm64v8

# Install NGINX and required tools in a single layer to reduce image size
RUN yum update -y && \
    amazon-linux-extras install nginx1 -y && \
    yum install nginx-mod-stream net-tools iputils procps htop -y && \
    yum clean all && \
    mv /etc/nginx/nginx.conf /etc/nginx/nginx.conf.orig

# Copy configuration file
COPY nginx.conf /etc/nginx/

# Configure logging to stdout/stderr for container environments
RUN ln -sf /dev/stdout /var/log/nginx/http_access.log && \
    ln -sf /dev/stderr /var/log/nginx/http_error.log && \
    ln -sf /dev/stdout /var/log/nginx/stream_access.log && \
    ln -sf /dev/stderr /var/log/nginx/stream_error.log

# Expose ports
EXPOSE 80 443

# Health check
HEALTHCHECK --interval=30s --timeout=3s CMD curl -f http://localhost/ || exit 1

# Start NGINX
CMD ["nginx", "-g", "daemon off;"]
