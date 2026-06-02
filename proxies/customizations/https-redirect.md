# Customization: HTTP to HTTPS redirect (port 80)

> ⚠️ **Reintroduces a port-`80` surface.** This adds a port-`80` listener whose only job is to return an HTTP `301` redirect to `https://`. It proxies **no** application data to VPC Lattice. However, the client's first request line and `Host` header still arrive in **cleartext** before the redirect is returned, so the hostname/path leak on that first hop (the body usually isn't sent until the client follows to HTTPS).
>
> A redirect only helps clients that start in cleartext **and** automatically follow redirects (browsers, `curl -L`). It does **not** help SigV4-signed / API clients, since a signed request bounced to a new scheme generally won't be re-signed and replayed. For the API-centric consumer profile this Guidance targets, prefer the default (no port `80` at all).

This adds a redirect-only listener so `http://your.service` callers are sent to `https://your.service`. Unlike [`http-passthrough.md`](./http-passthrough.md), it never forwards cleartext data to the backend.

## Proxy configuration

### NGINX

The default config does TLS passthrough on `443` via the `stream {}` block, which cannot speak HTTP, so the redirect must be a separate plaintext HTTP listener. Add this `http {}` block alongside the existing `stream {}` block in [`../nginx/nginx.conf`](../nginx/nginx.conf):

```nginx
http {

    server {
        listen 80 proxy_protocol;
        set_real_ip_from 192.168.0.0/16;
        real_ip_header proxy_protocol;

        # Redirect everything to HTTPS, preserving host and path.
        return 301 https://$host$request_uri;
    }

    log_format  basic   '$time_iso8601 $remote_addr $proxy_protocol_addr $proxy_protocol_port $request_uri $server_port $status';
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

Add a port-`80` listener to [`../envoy/envoy.yaml`](../envoy/envoy.yaml) with an HTTP connection manager whose route performs a scheme redirect (no upstream cluster needed):

```yaml
  - name: https_redirect
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
          stat_prefix: https_redirect
          route_config:
            virtual_hosts:
            - name: redirect
              domains: ["*"]
              routes:
              - match: { prefix: "/" }
                redirect: { https_redirect: true }
          http_filters:
          - name: envoy.filters.http.router
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.filters.http.router.v3.Router
```

## CloudFormation delta

Apply the shared port-80 infrastructure change in [`cloudformation-delta.md`](./cloudformation-delta.md).

## VPC Lattice service

No HTTP listener is required on the VPC Lattice service; this only bounces clients to
HTTPS, and the actual request is served over the default TLS-passthrough path on `443`.
Keep the Lattice service **HTTPS-only**.
