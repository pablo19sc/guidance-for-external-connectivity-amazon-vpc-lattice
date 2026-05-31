<!--
Thanks for contributing! Please fill out the sections below.
For significant changes, please open an issue first to discuss (see CONTRIBUTING.md).
Do NOT report security vulnerabilities via a PR or public issue —
use https://aws.amazon.com/security/vulnerability-reporting/ instead.
-->

## Description

<!-- What does this PR change, and why? Keep the change focused and scoped. -->

## Related issue

<!-- Link the issue this addresses, e.g. "Closes #123". Open an issue first for significant work. -->

## Type of change

- [ ] Bug fix
- [ ] New feature / enhancement
- [ ] Documentation only
- [ ] Proxy config / customization (NGINX or Envoy)
- [ ] CI/CD or tooling

## Areas affected

- [ ] Networking (VPC / PrivateLink endpoints)
- [ ] Ingress (NLB / ECS Fargate proxy)
- [ ] Proxy engine (`proxies/`)
- [ ] CI/CD (CodePipeline / CodeBuild / CodeCommit / ECR)
- [ ] Testing (`testing/`)
- [ ] Documentation

## Standards checklist

- [ ] I have read the [CONTRIBUTING](../CONTRIBUTING.md) guidelines and followed the project's standards.
- [ ] I am working against the latest source on the `main` branch.
- [ ] I checked existing open and recently merged PRs to avoid duplicating work.
- [ ] My change is focused on a single concern (no unrelated reformatting).

## Pre-commit / validation checklist

> These mirror the CI checks in [`.github/workflows/validation.yml`](workflows/validation.yml).
> Run them locally first: `pip install pre-commit && pre-commit install`, then `pre-commit run --all-files`.

- [ ] I ran `pre-commit run --all-files` and all hooks pass.
- [ ] `cfn-lint` passes (`guidance-stack.yml` and `testing/*.yml`).
- [ ] `checkov` passes for the `testing/` templates.
- [ ] `hadolint` passes for any changed `proxies/*/Dockerfile`.
- [ ] `shellcheck` passes for any changed `*.sh` scripts.
- [ ] Proxy config validation passes for changes to `nginx.conf` / `envoy.yaml` (`nginx -t` / `envoy --mode validate`, requires Docker).
- [ ] Markdown links resolve for any changed docs.

> Note: `cfn-nag` runs in CI only (not in local pre-commit).

## Testing

<!-- How did you validate this change? Include Region, ProxyEngine, and any deploy/validation steps from testing/. -->

## Licensing

- [ ] I confirm my contribution is made under the terms of the project's [MIT-0 license](../LICENSE).
