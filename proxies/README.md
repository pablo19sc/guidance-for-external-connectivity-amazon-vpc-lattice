# Proxy engines

Each subdirectory is a self-contained proxy implementation. At stack creation, the directory matching the `ProxyEngine` parameter is seeded into the CodeCommit repository, which becomes the editable source of truth; commits there trigger the pipeline to build and deploy a new image.

| Directory | Engine | Notes |
|---|---|---|
| [`nginx/`](./nginx/) | NGINX (default) | Official `nginx` Alpine image (Amazon ECR Public); `stream` module passthrough. |
| [`envoy/`](./envoy/) | Envoy | Official `envoyproxy/envoy` image (Docker Hub); SNI dynamic forward proxy. |

Each directory contains the `Dockerfile` (engine version pinned via a build arg), the proxy config (`nginx.conf` / `envoy.yaml`), and a `buildspec.yml` that builds the image with an immutable commit-based tag and emits `imagedefinitions.json` for the CodePipeline ECS deploy action.

For the engine comparison and how to choose, see the repository [README](../README.md#proxy-engines). For optional HTTP listeners, see [customizations/](./customizations/).

## Editing the proxy

The selected engine's directory is seeded into the CodeCommit repository at stack creation (clone URL is in the `ProxySourceRepoCloneUrlHttp` stack output). **To change the proxy, commit to the CodeCommit repository.** A commit automatically triggers the pipeline to build a new immutable image and roll it out to ECS. You can also point the `SourceRepoUrl` stack parameter at your own fork to bootstrap from custom code.

## What both engines do

Both perform the same TLS passthrough: read the SNI (or `Host`) to learn the destination, resolve the VPC Lattice domain dynamically via the VPC resolver (`169.254.169.253`), and forward the still-encrypted bytes. No TLS is terminated, so no certificates are managed on the proxy. The NLB sends a **PROXY protocol v2** header (on data and health-check connections), which the proxy consumes to recover the real client IP. Each engine listens on **443 only** (TLS-only by default) and writes logs to the per-task CloudWatch Logs group.

## NGINX

Based on the official `nginx` Alpine image (from Amazon ECR Public), pinned via the `NGINX_VERSION` build arg in the [Dockerfile](./nginx/Dockerfile). The Alpine image has the stream module compiled in, so there is **no `load_module` directive** in [`nginx.conf`](./nginx/nginx.conf). The `stream` listener does the passthrough:

```
server {
    listen 443 proxy_protocol;
    proxy_pass $ssl_preread_server_name:$server_port;
    ssl_preread on;
    set_real_ip_from 192.168.0.0/16;
}
```

`listen 443 proxy_protocol` trusts the NLB to pass the true source IP (`set_real_ip_from 192.168.0.0/16`), and a `map` on `$bytes_received` keeps health-check noise out of the access log.

## Envoy

Based on the official `envoyproxy/envoy` image, pinned via the `ENVOY_VERSION` build arg in the [Dockerfile](./envoy/Dockerfile). The [`envoy.yaml`](./envoy/envoy.yaml) listener chains two listener filters (`proxy_protocol` to consume the PROXY v2 header, then `tls_inspector` to read SNI without decrypting) and forwards with the **SNI dynamic forward proxy** network filter into a dynamic forward proxy cluster:

```yaml
filters:
- name: envoy.filters.network.sni_dynamic_forward_proxy
  typed_config:
    "@type": type.googleapis.com/envoy.extensions.filters.network.sni_dynamic_forward_proxy.v3.FilterConfig
    port_value: 443
    dns_cache_config: { name: dynamic_forward_proxy_cache_config, dns_lookup_family: V4_ONLY }
- name: envoy.tcp_proxy
  typed_config:
    "@type": type.googleapis.com/envoy.extensions.filters.network.tcp_proxy.v3.TcpProxy
    stat_prefix: lattice_tcp
    cluster: dynamic_forward_proxy_cluster
```

Access logs go to stdout (and on to CloudWatch); the admin interface is bound to localhost for debugging via ECS Exec.

> The SNI dynamic forward proxy filter is currently labelled *alpha* by Envoy. The base image is pulled from Docker Hub, so a heavily-throttled build may need Docker Hub authentication or an ECR mirror.
