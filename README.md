# Guidance for External Connectivity to Amazon VPC Lattice

This Guidance builds a [serverless](https://aws.amazon.com/serverless/) proxy that lets clients **outside AWS** reach your [Amazon VPC Lattice](https://aws.amazon.com/vpc/lattice/) services.

![image](./img/guidance-diagram-v2.png)

## Table of Content

- [Guidance for External Connectivity to Amazon VPC Lattice](#guidance-for-external-connectivity-to-amazon-vpc-lattice)
  - [Table of Content](#table-of-content)
  - [Overview](#overview)
    - [Cost](#cost)
  - [Prerequisites](#prerequisites)
    - [Operating System](#operating-system)
    - [Supported AWS Regions](#supported-aws-regions)
    - [VPC Lattice infrastructure](#vpc-lattice-infrastructure)
    - [DNS resolution configuration](#dns-resolution-configuration)
  - [Deployment Steps](#deployment-steps)
  - [Deployment Validation](#deployment-validation)
  - [Running the Guidance](#running-the-guidance)
  - [Next Steps](#next-steps)
    - [Security](#security)
    - [Proxy Configuration](#proxy-configuration)
    - [Scaling](#scaling)
    - [Logging](#logging)
    - [Performance](#performance)
  - [Cleanup](#cleanup)
  - [FAQ, known issues, additional considerations, and limitations](#faq-known-issues-additional-considerations-and-limitations)
    - [Considerations](#considerations)
  - [License](#license)
  - [Contributing](#contributing)
  - [Authors](#authors)

## Overview

A VPC Lattice service gets a globally resolvable DNS name, but outside its VPC that name resolves to **link-local IPs** (`169.254.171.x/24` within the IPv4 link-local range of [RFC3927](https://datatracker.ietf.org/doc/html/rfc3927), and `fd00:ec2:80::/64` within the IPv6 link-local range of [RFC4291](https://datatracker.ietf.org/doc/html/rfc4291)). Link-local addresses aren't routable. When a consumer inside an associated VPC resolves the service, the [Nitro](https://aws.amazon.com/ec2/nitro/) card intercepts the packets and routes them to the [VPC Lattice service network](https://docs.aws.amazon.com/vpc-lattice/latest/ug/service-networks.html) ingress. So a client **outside** such a VPC can't connect directly.

![image](./img/vpc-lattice-diagram.png)

[Service network endpoints](https://docs.aws.amazon.com/vpc/latest/privatelink/access-with-service-network-endpoint.html) let you place ENIs in a VPC and reach service networks from outside it. They behave differently from *Interface* endpoints:

1. Each endpoint consumes multiple /28 IPv4 and /80 IPv6 ranges per Availability Zone (subnet).
2. Several VPC Lattice services can share a single IP from those ranges.

So you can't assume a service's IP is stable or unique. To handle this, each service associated to the network gets its own globally unique, externally resolvable domain name (resolving to a routable endpoint IP). **For hybrid and cross-Region access**, service network endpoints are the recommended approach — you only configure the matching DNS resolution (hybrid or in the consumer VPC) to target the endpoint.

![image](./img/vpc-lattice-diagram-crossRegion.png)

![image](./img/vpc-lattice-diagram-hybrid.png)

**For clients outside AWS with no private connectivity**, the IPs used to reach services can change as services are added. This Guidance front-ends VPC Lattice with a proxy layer that resolves services dynamically on each request — so a changing backend IP never breaks your clients, and you avoid discovering endpoint IPs and updating static configuration yourself.

### Cost

You are responsible for the cost of the AWS services used while running this Guidance. As of May 2026, running it with default settings in US East (N. Virginia) costs approximately **$185.20 per month**, broken down below. This is an estimate of the steady-state (idle) cost; verify for your Region and usage with the [AWS Pricing Calculator](https://calculator.aws/).

| AWS service  | Dimensions | Cost [USD] |
| ----------- | ------------ | ------------ |
| [AWS Fargate](https://aws.amazon.com/fargate/pricing/) | 3x2vCPUs & 3x4GBRAM | $ 30.08 month |
| [Network Load Balancer](https://aws.amazon.com/elasticloadbalancing/pricing/) | 1 NLCU & 1 NLB | $ 21.20 month |
| [VPC endpoints](https://aws.amazon.com/privatelink/pricing/) | 6 endpoint types in 3 Availability Zones | $ 133.92 month |

You can reduce cost by using fewer Availability Zones (default is 3). We recommend at least 2 for high availability.

The CI/CD services typically stay within the [AWS Free Tier](https://aws.amazon.com/free/) at this Guidance's scale; review each pricing page for usage beyond it:

* [Amazon ECR](https://aws.amazon.com/ecr/pricing/) and [AWS CodeBuild](https://aws.amazon.com/codebuild/pricing/): pay-as-you-go for image storage and build minutes.
* [AWS CodePipeline](https://aws.amazon.com/codepipeline/pricing/): one V1 active pipeline is free; the pipeline's S3 artifacts cost a few cents per month.
* [AWS CodeCommit](https://aws.amazon.com/codecommit/pricing/): 5 active users per month are free. Note that the CodePipeline and CodeBuild service roles count as active users, so large teams editing the proxy could exceed the free allowance ($1.00 per additional active user per month).

We recommend creating a [Budget](https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-managing-costs.html) via [AWS Cost Explorer](https://aws.amazon.com/aws-cost-management/aws-cost-explorer/) to manage costs. Prices are subject to change; see each service's pricing page for details.

## Prerequisites

### Operating System

These instructions are optimized for Linux ARM64. Because the proxy runs on AWS Fargate (serverless), you don't manage any instance infrastructure.

### Supported AWS Regions

Deploy this Guidance in any Region where **Amazon VPC Lattice** is available — it's the gating service. The other services have broader Region support.

| Service | Region availability |
|---|---|
| Amazon VPC Lattice | [endpoints & quotas](https://docs.aws.amazon.com/general/latest/gr/vpc-lattice-service.html) |
| Amazon ECS on AWS Fargate | [supported Regions](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/AWS_Fargate-Regions.html) |
| Amazon ECR | [supported Regions](https://docs.aws.amazon.com/general/latest/gr/ecr.html) |
| AWS CodeBuild | [supported Regions](https://docs.aws.amazon.com/general/latest/gr/codebuild.html) |
| AWS CodePipeline | [supported Regions](https://docs.aws.amazon.com/general/latest/gr/codepipeline.html) |
| AWS CodeCommit | [supported Regions](https://docs.aws.amazon.com/general/latest/gr/codecommit.html) |

### VPC Lattice infrastructure

This Guidance provides *access* to VPC Lattice services but **does not create any VPC Lattice assets**. You connect the ingress VPC to one or more service networks using either:

* a [service network VPC association](https://docs.aws.amazon.com/vpc-lattice/latest/ug/service-network-associations.html) (1 per VPC), or
* one or more [service network VPC endpoints](https://docs.aws.amazon.com/vpc/latest/privatelink/access-with-service-network-endpoint.html) (check the subnet prerequisites carefully, mainly for IPv4).

To test end-to-end consumption, use the templates in the [vpc-lattice_example](/vpc-lattice_example/) folder.

### DNS resolution configuration

After the ingress VPC and proxy are created and the VPC is associated (or an endpoint created) to a service network, configure DNS so external clients reach the proxy and the proxy reaches VPC Lattice. You need two records:

* A **public** Route 53 record mapping the [VPC Lattice custom domain name](https://docs.aws.amazon.com/vpc-lattice/latest/ug/service-custom-domain-name.html) to the proxy's [NLB](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/introduction.html) DNS name.
* A **private** Route 53 record (in a hosted zone associated to the ingress VPC) mapping the custom domain name to the VPC Lattice-generated domain name. Services sharing a domain name under the same private hosted zone name don't need new zones.

For both records, we recommend an [ALIAS record](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/resource-record-sets-choosing-alias-non-alias.html).

**NOTE** This Guidance does not create hosted zones or configure DNS. See [dns-resolution.yml](/vpc-lattice_example/dns-resolution.yml) in the [vpc-lattice_example](/vpc-lattice_example/) folder for an example.

## Deployment Steps

1. Deploy the [stack template](/guidance-stack.yml). Key parameters:
   * `AllowedIPv4Block` (required) and `AllowedIPv6Block` (optional) — CIDR blocks allowed to reach the public NLB.
   * `VpcCidr` — VPC IPv4 CIDR, defaults to `192.168.1.0/16`.
   * `ProxyEngine` — proxy engine to deploy (`nginx`).

```
aws cloudformation deploy --template-file ./guidance-stack.yml --stack-name guidance-vpclattice-external --parameter-overrides AllowedIPv4Block={YOUR_IPV4_BLOCK} AllowedIPv6Block={YOUR_IPV6_BLOCK} ProxyEngine=nginx --capabilities CAPABILITY_IAM
```

The stack deploys:

**Networking**
* An [Amazon VPC](https://docs.aws.amazon.com/vpc/latest/userguide/what-is-amazon-vpc.html) across three [Availability Zones](https://aws.amazon.com/about-aws/global-infrastructure/regions_az/) with public, private, and endpoint subnets, plus [route tables](https://docs.aws.amazon.com/vpc/latest/userguide/VPC_Route_Tables.html) and an [Internet Gateway](https://docs.aws.amazon.com/vpc/latest/userguide/VPC_Internet_Gateway.html).
* [PrivateLink VPC endpoints](https://docs.aws.amazon.com/whitepapers/latest/aws-privatelink/what-are-vpc-endpoints.html) (interface and gateway) so Fargate reaches AWS services privately — no NAT gateways needed.

**Ingress**
* An internet-facing, dualstack [Network Load Balancer](https://aws.amazon.com/elasticloadbalancing/network-load-balancer/) and a [target group](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/load-balancer-target-groups.html) bound to a single TCP listener on **port 443**. The Guidance is **TLS-only by default** — port 80 is not exposed. To add an HTTP listener (cleartext passthrough or HTTP→HTTPS redirect), see [customizations/](/customizations/).
* An [ECS](https://aws.amazon.com/ecs/) cluster, [task definition](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definitions.html), and [service](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs_services.html) on [AWS Fargate](https://aws.amazon.com/fargate/) running the proxy, with autoscaling.

**CI/CD** (so you can iterate on the proxy from within your account)
* An [Amazon ECR](https://aws.amazon.com/ecr/) repository (scan-on-push) for container images.
* An [AWS CodeCommit](https://docs.aws.amazon.com/codecommit/latest/userguide/welcome.html) repository holding the proxy source (`Dockerfile`, proxy config, `buildspec.yml`), **seeded once at stack creation** from `SourceRepoUrl` with the engine chosen in `ProxyEngine`.
* An [AWS CodePipeline](https://aws.amazon.com/codepipeline/) pipeline (Source → Build → Deploy) using [AWS CodeBuild](https://aws.amazon.com/codebuild/). A commit to the CodeCommit repository automatically builds a new image and deploys it.

**NOTE** On first-time ECS use, a service-linked role is created for you. If the stack fails because the role wasn't created in time, delete the failed stack and redeploy.

2. Configure DNS resolution so clients can consume the VPC Lattice services (see above).

## Deployment Validation

* In the AWS CloudFormation console, confirm the stack deployed without errors.
* In the Amazon ECS console, confirm the cluster **{STACK_NAME}-NginxCluster-%random%** has 3 running tasks.

## Running the Guidance

Once deployed, curl your NLB's DNS name (or your own alias record):

```
curl https://yourvpclatticeservice.name
```

If your VPC Lattice service or service network has authorization enabled, sign requests in the **same Region** you deployed the stack. This example uses curl's **--aws-sigv4** flag:

```
curl https://yourvpclatticeservice.name \
    --aws-sigv4 "aws:amz:%region%:vpc-lattice-svcs" \
    --user "$AWS_ACCESS_KEY_ID:$AWS_SECRET_ACCESS_KEY" \
    --header "x-amz-security-token:$AWS_SESSION_TOKEN" \
    --header "x-amz-content-sha256:UNSIGNED-PAYLOAD"
```

You can test this with the [setcredentials.sh](./scripts/setcredentials.sh) and [callendpoint.sh](./scripts/callendpoint.sh) scripts in this repo.

## Next Steps

### Security

The proxy runs in private subnets and reaches AWS services through [PrivateLink interface endpoints](https://docs.aws.amazon.com/vpc/latest/privatelink/create-interface-endpoint.html), so no [NAT gateways](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-nat-gateway.html) are needed. A [security group](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/load-balancer-security-groups.html) on the NLB restricts inbound traffic to your allowed CIDR blocks.

Because this is **external** connectivity over the public internet, the Guidance is **TLS-only by default**: the proxy exposes only port 443 and does TLS passthrough (reading the SNI without decrypting), keeping traffic encrypted end-to-end to the VPC Lattice service. Enforce HTTPS on your VPC Lattice services accordingly (an HTTPS listener with a certificate and custom domain). Port 80 is intentionally not exposed; if you need it, [customizations/](/customizations/) shows how to add it back with the relevant caveats.

### Proxy Configuration

The proxy source lives in this repo under [`proxies/<engine>/`](/proxies/) (for the default engine, [`proxies/nginx/`](/proxies/nginx/)): the `Dockerfile`, the proxy configuration, and the `buildspec.yml`. At stack creation this directory is seeded into the CodeCommit repository, which becomes the editable source of truth. **To change the proxy, commit to the CodeCommit repository** (clone URL is in the `ProxySourceRepoCloneUrlHttp` stack output) - a commit automatically triggers the pipeline to build a new immutable image and roll it out to ECS. You can also point `SourceRepoUrl` at your own fork to bootstrap from custom code.

The NGINX image is based on the official, maintained `nginx` image (Alpine variant) pulled from Amazon ECR Public, pinned via the `NGINX_VERSION` build argument in the [Dockerfile](/proxies/nginx/Dockerfile). The Alpine image is compiled with the stream module built in, so - unlike a package-based install - there is **no `load_module` directive** in `nginx.conf`.

The stream listener reads the SNI header to understand where the traffic is destined to, it uses the Amazon provided DNS endpoint at `169.254.169.253` for resolution which supplies a zonal response for the VPC Lattice service. The downstream endpoint is reached using the following directive `proxy_pass $ssl_preread_server_name:$server_port`

```
server {
    listen 443 proxy_protocol;
    proxy_pass $ssl_preread_server_name:$server_port;
    ssl_preread on;
    set_real_ip_from 192.168.0.0/16;
}
```
Proxy protocol is configured thus `listen 443 proxy_protocol`. This configuration trusts the NLB to pass **true** source IP information to the NGINX proxy `set_real_ip_from 192.168.0.0/16`.

Logs go straight to the per-task CloudWatch Logs group:

```
log_format  basic   '$time_iso8601 $remote_addr $proxy_protocol_addr $proxy_protocol_port $protocol $server_port '
                '$status $upstream_addr $upstream_bytes_sent $upstream_bytes_received $session_time  $upstream_connect_time';

access_log  /var/log/nginx/stream_access.log basic if=$notAHealthCheck;
error_log   /var/log/nginx/stream_error.log crit;

```

This `map` keeps health-check noise out of the logs:

```
map $bytes_received $notAHealthCheck {
    "~0"            0;
    default         1;
}
```

Only the `stream` listener on port 443 is configured by default (TLS-only — see [Security](#security)). To add an HTTP listener, see [customizations/](/customizations/).

### Scaling

The ECS service autoscales on average CPU — under load testing the proxy was CPU-bound at the chosen task sizes (see these [independent measurements](https://www.stormforge.io/blog/aws-fargate-network-performance/)). Adjust the metric to fit your workload by editing [guidance-stack.yml](/guidance-stack.yml).

This Guidance uses [Application Auto Scaling](https://docs.aws.amazon.com/autoscaling/application/userguide/services-that-can-integrate-ecs.html) target tracking with the `ECSServiceAverageCPUUtilization` predefined metric. You can swap in your own metric via a [`CustomizedMetricSpecification`](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-properties-applicationautoscaling-scalingpolicy-targettrackingscalingpolicyconfiguration.html#cfn-applicationautoscaling-scalingpolicy-targettrackingscalingpolicyconfiguration-customizedmetricspecification). The default target is **70%** CPU — adjust in the template:

```
  NginxScalableTarget:
    Type: AWS::ApplicationAutoScaling::ScalableTarget
    Properties: 
      MaxCapacity: 9
      MinCapacity: 3
```

```
  NginxScalingPolicy:
    Type: AWS::ApplicationAutoScaling::ScalingPolicy
    Properties: 
      .....
      TargetTrackingScalingPolicyConfiguration:
        TargetValue: 70.0
        ScaleInCooldown: 60
        ScaleOutCooldown: 60
```

### Logging

The ECS service uses [Container Insights](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/ContainerInsights.html) to capture performance data, written to CloudWatch Logs and viewable from the ECS or CloudWatch console.

![img](/img/logging-container-insights.png)

### Performance

We load-tested the Guidance with the following setup:

* Region: us-west-2
* Published VPC Lattice service: [AWS Lambda](https://aws.amazon.com/lambda/) (a simple function with concurrency raised to 3000 from the 1000 base)
* External access via a three-zone NLB using DNS round-robin
* Cross-zone load balancing **off** on the NLB (it performed worse in tests)
* Three zonal Fargate tasks bound to the NLB, each 2048 CPU units / 4096 MB RAM

The harness is the [Distributed Load Testing on AWS](https://aws.amazon.com/solutions/implementations/distributed-load-testing-on-aws/) solution; its template is also [in this repo](/load-test/distributed-load-testing-on-aws.template).

Results below cover harness, NLB, VPC Lattice, and Lambda performance for 5000 remote users generating ~3000 requests/second, sustained for 20 minutes with a 5-minute ramp-up.

**Harness Performance**

![image](/img/perf-testing-harness.png)

![image](/img/perf-testing-percentiles.png)

**ECS Performance**

![image](/img/perf-testing-ecs.png)

**LAMBDA Performance**

![image](/img/perf-testing-lambda.png)

**VPC Lattice Performance**

![image](/img/perf-testing-lattice.png)

## Cleanup

1. Remove the stack created at deployment.

**NOTE** A few resources are intentionally retained (`DeletionPolicy: Retain`) so you don't lose data or customizations when the stack is deleted, and must be removed manually if you no longer need them:
* The Amazon ECR repository (and its images).
* The CodeCommit repository holding your proxy source (including any edits you committed).
* The S3 artifact bucket used by the pipeline.

## FAQ, known issues, additional considerations, and limitations

### Considerations

Key design choices and constraints:

* The proxy provides **layer 4 connectivity and layer 3 security**; all layer 7 management stays with VPC Lattice.
* **Authentication and authorization stay with VPC Lattice** — keep your service network and/or service authN/Z policies in place.
* The proxy is a fleet of lightweight open-source NGINX tasks on ECS, fronted by an external NLB.
* TLS connections are TCP-proxied (passthrough) using the SNI for dynamic endpoint lookup, so no certificates are managed between provider and proxy. HTTP proxying is opt-in via [customizations/](/customizations/) and not recommended for external exposure.
* VPC Lattice services commonly use custom domains, which lets you use separate Route 53 hosted zones for different consumers (external users vs. the proxy).

## License

This library is licensed under the MIT-0 License. See the [LICENSE](LICENSE) file.

## Contributing

See [CONTRIBUTING](CONTRIBUTING.md) for more information.

## Authors

* Pablo Sánchez Carmona, Senior Network Specialist Solutions Architect, AWS
* Adam Palmer, Principal TPM, Kuiper
