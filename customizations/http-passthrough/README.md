# Customization: HTTP passthrough (port 80)

> ⚠️ **Not recommended for external exposure.** This restores a plaintext HTTP proxy on
> port `80`. Traffic between the external client and the proxy, and between the proxy and
> the VPC Lattice service, travels **in cleartext across the internet** - the full
> request line, headers, and body are visible on the wire. Even if the VPC Lattice
> service enforces SigV4 auth, the request is authenticated but **not encrypted**.
>
> Use this only when a VPC Lattice service has an HTTP-only listener that cannot be
> changed, or for internal/test scenarios where the network path is trusted.

This snippet reverts the default TLS-only build to also proxy cleartext HTTP, matching
the original behavior of the Guidance.

## 1. Proxy configuration

### NGINX (`proxies/nginx/nginx.conf`)

Add the following `http {}` block alongside the existing `stream {}` block. It reads the
`Host` header and dynamically resolves/forwards to the VPC Lattice service over HTTP.

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

Also restore the HTTP log symlinks in `proxies/nginx/Dockerfile`:

```dockerfile
RUN ln -sf /dev/stdout /var/log/nginx/http_access.log \
    && ln -sf /dev/stderr /var/log/nginx/http_error.log \
    && ln -sf /dev/stdout /var/log/nginx/stream_access.log \
    && ln -sf /dev/stderr /var/log/nginx/stream_error.log
```

### Envoy

In the Envoy configuration, add an HTTP listener on port `80` that ingests PROXY
protocol v2 (`envoy.filters.listener.proxy_protocol`) and forwards via the HTTP dynamic
forward proxy filter (`envoy.filters.http.dynamic_forward_proxy`) using the `Host`
header, alongside the existing SNI-passthrough listener on `443`.

## 2. CloudFormation delta (`guidance-stack.yml`)

The default template exposes only HTTPS. To re-add port `80`, make the following changes.

**a. Re-add `HTTP` to the `Protocol` mapping:**

```yaml
  Protocol:
    Port:
      HTTP: 80
      HTTPS: 443
```

**b. Re-add `HTTP` to the three security-group `Fn::ForEach` port lists** (`NginxNLBSecurityGroup`, `IPv6NginxNLBSecurityGroup`, `NginxECSSecurityGroup`):

```yaml
    - Port
    - [HTTP, HTTPS]
```

**c. Re-add the HTTP target group and listener** (next to `NginxNLBListenerHTTPS`):

```yaml
  # Target Group: 80
  NginxNLBTGroupHTTP:
    Type: 'AWS::ElasticLoadBalancingV2::TargetGroup'
    Properties:
      HealthCheckIntervalSeconds: 5
      HealthCheckTimeoutSeconds: 2
      HealthyThresholdCount: 3
      IpAddressType: ipv4
      Port: 80
      Protocol: TCP
      TargetGroupAttributes:
        - Key: proxy_protocol_v2.enabled
          Value: true
      TargetType: ip
      UnhealthyThresholdCount: 3
      VpcId: !Ref VPC

  # Listener: 80
  NginxNLBListenerHTTP:
    Type: 'AWS::ElasticLoadBalancingV2::Listener'
    Properties:
      DefaultActions:
        - TargetGroupArn: !Ref NginxNLBTGroupHTTP
          Type: forward
      LoadBalancerArn: !Ref NginxNLB
      Port: 80
      Protocol: TCP
```

**d. Re-add the container port mapping** in `NginxTask` → `ContainerDefinitions` → `PortMappings`:

```yaml
            - ContainerPort: 80
              Protocol: tcp
```

**e. Re-add the load balancer binding and dependency** in `NginxService`:

```yaml
    DependsOn:
      - NginxNLBListenerHTTPS
      - NginxNLBListenerHTTP
    Properties:
      ...
      LoadBalancers:
        - ContainerName: Nginx
          ContainerPort: 443
          TargetGroupArn: !Ref NginxNLBTGroupHTTPS
        - ContainerName: Nginx
          ContainerPort: 80
          TargetGroupArn: !Ref NginxNLBTGroupHTTP
```

## 3. VPC Lattice service

For end-to-end HTTP, the target VPC Lattice service must have an HTTP (port `80`)
listener. Add an HTTP listener to the example templates in `vpc-lattice_example/` if you
removed it.
