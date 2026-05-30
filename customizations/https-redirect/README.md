# Customization: HTTP → HTTPS redirect (port 80)

> ⚠️ **Reintroduces a port-`80` surface.** This adds a port-`80` listener whose only job
> is to return an HTTP `301` redirect to `https://`. It proxies **no** application data
> to VPC Lattice. However, the client's first request line and `Host` header still arrive
> in **cleartext** before the redirect is returned, so the hostname/path leak on that
> first hop (the body usually isn't sent until the client follows to HTTPS).
>
> A redirect only helps clients that start in cleartext **and** automatically follow
> redirects (browsers, `curl -L`). It does **not** help SigV4-signed / API clients - a
> signed request bounced to a new scheme generally won't be re-signed and replayed, so
> you'll see a confusing failure rather than a smooth upgrade. For the API-centric
> consumer profile this Guidance targets, prefer the default (no port `80` at all).

This snippet adds a redirect-only listener so `http://your.service` callers are sent to
`https://your.service`. Unlike [`http-passthrough/`](../http-passthrough/), it never
forwards cleartext data to the backend.

## 1. Proxy configuration

### NGINX (`proxies/nginx/nginx.conf`)

The default config does TLS passthrough on `443` via the `stream {}` block, which cannot
speak HTTP. The redirect must therefore be a separate plaintext HTTP listener. Add this
`http {}` block alongside the existing `stream {}` block:

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

Also restore the HTTP log symlinks in `proxies/nginx/Dockerfile`:

```dockerfile
RUN ln -sf /dev/stdout /var/log/nginx/http_access.log \
    && ln -sf /dev/stderr /var/log/nginx/http_error.log \
    && ln -sf /dev/stdout /var/log/nginx/stream_access.log \
    && ln -sf /dev/stderr /var/log/nginx/stream_error.log
```

### Envoy

Add a port-`80` listener that ingests PROXY protocol v2
(`envoy.filters.listener.proxy_protocol`) with an HTTP connection manager whose route
performs a scheme redirect:

```yaml
route:
  # ...
redirect:
  https_redirect: true
```

## 2. CloudFormation delta (`guidance-stack.yml`)

This is the **same delta** as [`http-passthrough/`](../http-passthrough/) - you still
need the port-`80` NLB listener, target group, security-group rule, and container port
mapping. The only difference is the proxy config above (redirect instead of proxy).

Apply steps **a** through **e** from
[`../http-passthrough/README.md`](../http-passthrough/README.md#2-cloudformation-delta-guidance-stackyml).

## 3. VPC Lattice service

No HTTP listener is required on the VPC Lattice service - this snippet only bounces
clients to HTTPS, and the actual request is served over the default TLS-passthrough path
on `443`. Keep the Lattice service **HTTPS-only**.
