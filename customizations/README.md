# Customizations

The default Guidance is **TLS-only**: the proxy exposes only port `443` and performs
TLS passthrough (reading the SNI without decrypting), keeping traffic encrypted
end-to-end from the external client to the VPC Lattice service. Port `80` is **not**
exposed by default.

This folder contains opt-in customizations that change the default proxy behavior. The
snippets below are for users who need an HTTP listener. Both
re-introduce a plaintext port-`80` surface on the internet-facing NLB, so apply them
only if you understand the tradeoff.

| Snippet | What it does | When to use | Security note |
| ------- | ------------ | ----------- | ------------- |
| [`https-redirect/`](./https-redirect/) | Adds a port-`80` listener that only returns an HTTP `301` to `https://` and proxies no data | Browser-facing convenience so `http://` callers are bounced to TLS | The first request line + `Host` header still arrive in cleartext before the redirect. Not useful for SigV4-signed / API clients, which generally won't re-sign and replay on redirect. |
| [`http-passthrough/`](./http-passthrough/) | Restores the original port-`80` cleartext HTTP proxy to VPC Lattice | A VPC Lattice service that only has an HTTP listener and cannot be changed, or internal/test scenarios | **Plaintext across the internet.** The full request and response are exposed on the wire. Not recommended for external exposure. |

Each snippet contains the proxy config block and the CloudFormation delta you need to
add back to `guidance-stack.yml` (NLB listener, target group, security-group rule, and
container port mapping).

> The CloudFormation deltas below are written for the **NGINX** engine (resource names
> match `guidance-stack.yml`). The proxy config blocks are provided for both NGINX and
> Envoy where applicable.
