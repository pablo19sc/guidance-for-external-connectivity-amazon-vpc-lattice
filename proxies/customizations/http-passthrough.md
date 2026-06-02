# Customization: HTTP passthrough (port 80)

> ⚠️ **Not recommended for external exposure.** This restores a plaintext HTTP proxy on port `80`. Traffic between the external client and the proxy, and between the proxy and the VPC Lattice service, travels **in cleartext across the internet**: the full request line, headers, and body are visible on the wire. Even if the VPC Lattice service enforces SigV4 auth, the request is authenticated but **not encrypted**.
>
> Use this only when a VPC Lattice service has an HTTP-only listener that cannot be changed, or for internal/test scenarios where the network path is trusted.

This reverts the default TLS-only build to also proxy cleartext HTTP, reading the `Host`
header and dynamically resolving/forwarding to the VPC Lattice service over HTTP.

## Proxy configuration

### NGINX

Add this `http {}` block alongside the existing `stream {}` block in [`../nginx/nginx.conf`](../nginx/nginx.conf):

```nginx
http {

    resolver 169.254.169.253 ipv6=off;

    server {
        listen 80 proxy_protocol;
        location / {
            proxy_set_header Host $host;
            proxy_pass  http://$host:80;
            proxy_http_version 1.1;
        }
        set_real_ip_from 192.168.0.0/16;
        real_ip_header proxy_protocol;
    }

    log_format  basic   '$time_iso8601 $remote_addr $proxy_protocol_addr $proxy_protocol_port $request_uri $server_port '
                        '$status $upstream_addr $upstream_bytes_sent $upstream_bytes_received $upstream_connect_time';

    access_log  /var/log/nginx/http_access.log basic;
    error_log   /var/log/nginx/http_error.log crit;

}
```

Also restore the HTTP log symlinks in [`../nginx/Dockerfile`](../nginx/Dockerfile):

```dockerfile
RUN ln -sf /dev/stdout /var/log/nginx/http_access.log \
    && ln -sf /dev/stderr /var/log/nginx/http_error.log \
    && ln -sf /dev/stdout /var/log/nginx/stream_access.log \
    && ln -sf /dev/stderr /var/log/nginx/stream_error.log
```

### Envoy

Add a second listener on port `80` to [`../envoy/envoy.yaml`](../envoy/envoy.yaml), alongside the existing `443` SNI-passthrough listener. It ingests PROXY protocol v2 and forwards over HTTP using the `Host` header via the HTTP dynamic forward proxy filter:

```yaml
  - name: http_passthrough
    address:
      socket_address: { protocol: TCP, address: 0.0.0.0, port_value: 80 }
    listener_filters:
    - name: envoy.filters.listener.proxy_protocol
      typed_config:
        "@type": type.googleapis.com/envoy.extensions.filters.listener.proxy_protocol.v3.ProxyProtocol
    filter_chains:
    - filters:
      - name: envoy.filters.network.http_connection_manager
        typed_config:
          "@type": type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager
          stat_prefix: http_passthrough
          route_config:
            virtual_hosts:
            - name: dynamic
              domains: ["*"]
              routes:
              - match: { prefix: "/" }
                route:
                  cluster: dynamic_forward_proxy_cluster
          http_filters:
          - name: envoy.filters.http.dynamic_forward_proxy
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.filters.http.dynamic_forward_proxy.v3.FilterConfig
              dns_cache_config:
                name: dynamic_forward_proxy_cache_config
                dns_lookup_family: V4_ONLY
          - name: envoy.filters.http.router
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.filters.http.router.v3.Router
```

This reuses the same `dynamic_forward_proxy_cluster` already defined for the `443` path. Add the container port and EXPOSE 80 in [`../envoy/Dockerfile`](../envoy/Dockerfile) if you want it documented there.

## CloudFormation delta

Apply the shared port-80 infrastructure change in [`cloudformation-delta.md`](./cloudformation-delta.md).

## VPC Lattice service

For end-to-end HTTP, the target VPC Lattice service must have an HTTP (port `80`) listener. Add one to the test templates in [`../../testing/`](../../testing/) if you removed it.
