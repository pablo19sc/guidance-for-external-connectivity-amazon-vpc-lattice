# Official NGINX image, pulled from Amazon ECR Public to avoid Docker Hub rate
# limits during CodeBuild. The Alpine variant is small and is compiled with the
# stream module built in (--with-stream / --with-stream_ssl_module), so there is
# no package to install and NO load_module directive in nginx.conf.
#
# Pin to a current, patched stable NGINX. Bump NGINX_VERSION to update.
# (F5 OOB advisory, Mar 2026: use a release >= 1.29.7 / >= 1.28.3.)
ARG NGINX_VERSION=1.30.2
FROM public.ecr.aws/nginx/nginx:${NGINX_VERSION}-alpine

COPY nginx.conf /etc/nginx/nginx.conf

# Route the custom stream logs to the container stdout/stderr so they reach
# the awslogs driver / CloudWatch Logs.
RUN ln -sf /dev/stdout /var/log/nginx/stream_access.log \
    && ln -sf /dev/stderr /var/log/nginx/stream_error.log

EXPOSE 443

CMD ["nginx", "-g", "daemon off;"]
