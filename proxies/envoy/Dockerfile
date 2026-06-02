# Official Envoy image. Unlike NGINX, Envoy does not publish an Amazon ECR Public
# mirror, so this pulls from Docker Hub. CodeBuild can hit Docker Hub anonymous
# pull-rate limits; if you see "toomanyrequests", authenticate the build to Docker
# Hub (e.g. via Secrets Manager creds in the buildspec) or mirror the image to your
# own ECR. Pin to a current stable Envoy; bump ENVOY_VERSION to update.
ARG ENVOY_VERSION=v1.34.1
FROM envoyproxy/envoy:${ENVOY_VERSION}

COPY envoy.yaml /etc/envoy/envoy.yaml

# The official Envoy image's entrypoint drops privileges to the non-root "envoy"
# user unless ENVOY_UID=0, which leaves the process running as root. Root is
# required to bind port 443 (a privileged port); Fargate does not allow adding the
# NET_BIND_SERVICE capability, so running as root is the supported approach (and
# matches the NGINX container, whose master also runs as root to bind 443). No TLS
# is terminated here, so no private keys are present in the image.
ENV ENVOY_UID=0

EXPOSE 443

# -c config; send Envoy's own logs to stderr (access logs go to stdout via the
# config's StdoutAccessLog) so both reach the awslogs driver / CloudWatch.
CMD ["envoy", "-c", "/etc/envoy/envoy.yaml", "--log-level", "info"]
