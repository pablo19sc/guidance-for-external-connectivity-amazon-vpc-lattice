# Proxy customizations

The default Guidance is **TLS-only**: the proxy exposes only port `443` and performs TLS passthrough (reading the SNI without decrypting), keeping traffic encrypted end-to-end from the external client to the VPC Lattice service. Port `80` is **not** exposed.

This folder contains opt-in customizations that change that default. Each one combines a **proxy config change** (per engine) with a shared **CloudFormation delta**. Both customizations here add an HTTP listener on port `80`, which re-introduces a plaintext surface on the internet-facing NLB, so apply them only if you understand the tradeoff.

| Customization | What it does | When to use |
|---|---|---|
| [`https-redirect.md`](./https-redirect.md) | Port `80` listener that returns an HTTP `301` to `https://` and proxies no data | Browser-facing convenience so `http://` callers are bounced to TLS |
| [`http-passthrough.md`](./http-passthrough.md) | Restores a port `80` cleartext HTTP proxy to VPC Lattice | A VPC Lattice service that only has an HTTP listener and cannot be changed, or internal/test scenarios |

Each customization page covers both the **NGINX** and **Envoy** config changes. They
share the same infrastructure change, documented once in [`cloudformation-delta.md`](./cloudformation-delta.md).

> Both customizations expose plaintext HTTP and are **not recommended for external
> exposure**. See the security note on each page.
