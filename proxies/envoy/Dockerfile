# Official Envoy image. Unlike NGINX, Envoy does not publish an Amazon ECR Public
# mirror, so this pulls from Docker Hub. CodeBuild can hit Docker Hub anonymous
# pull-rate limits; if you see "toomanyrequests", authenticate the build to Docker
# Hub (e.g. via Secrets Manager creds in the buildspec) or mirror the image to your
# own ECR. Pin to a current stable Envoy; bump ENVOY_VERSION to update.
ARG ENVOY_VERSION=v1.34.1
FROM envoyproxy/envoy:${ENVOY_VERSION}

COPY envoy.yaml /etc/envoy/envoy.yaml

# Envoy in the official image runs as the non-root "envoy" user (uid 101) by
# default. Binding 443 (a privileged port) requires the NET_BIND_SERVICE
# capability or root; run as root here to match the NGINX task, which also
# listens on 443. (The proxy does no TLS termination, so no keys are present.)
USER root

EXPOSE 443

# -c config, and send Envoy's own logs to stderr (access logs go to stdout via
# the config's StdoutAccessLog) so both reach the awslogs driver / CloudWatch.
CMD ["envoy", "-c", "/etc/envoy/envoy.yaml", "--log-level", "info"]
