# Testing the Guidance

This folder helps you validate end-to-end reachability to a VPC Lattice service through the deployed proxy. There are two ways to use it:

* **Option A (you already have a VPC Lattice setup).** Your service network is connected to the ingress VPC and DNS resolution is configured. You only need the [`test-endpoint.sh`](./test-endpoint.sh) script to send requests.
* **Option B (you want a self-contained test environment).** Use the provided CloudFormation templates to create a test VPC Lattice service and the DNS records, then validate with the script.

| File | Purpose |
|---|---|
| `test-endpoint.sh` | Sends an unsigned or SigV4-signed request to your endpoint. |
| `vpc-lattice_service_association.yml` | Test service network + service + Lambda target, connected to the ingress VPC via a **VPC association**. |
| `vpc-lattice_service_endpoint.yml` | Same, but connected via a **service network VPC endpoint**. |
| `dns-resolution.yml` | Route 53 records: public (custom domain to the NLB) and private (custom domain to the VPC Lattice domain in the ingress VPC). |

The test service network templates enable **access logging to CloudWatch** in a log group named `/vpc-lattice/<stack-name>-service-network`, so you can inspect requests.

---

## Option A: Validate an existing setup

Use this if your VPC Lattice service network is already associated to (or has an endpoint in) the ingress VPC, and the custom domain already resolves publicly to the proxy NLB.

Send an **unsigned** request (works when the auth policy allows anonymous access):

```
./test-endpoint.sh https://your-service.example.com
```

Send a **signed (SigV4)** request (required when the auth policy demands authenticated callers):

```
./test-endpoint.sh https://your-service.example.com --sign --region <region>
```

A `200` with your service's response confirms the full path: external client to the NLB, through the proxy (TLS passthrough), to the VPC Lattice service.

See [Credentials for signed requests](#credentials-for-signed-requests) below.

---

## Option B: Deploy a self-contained test environment

Use this if you don't have a VPC Lattice service to test against yet.

### Prerequisites

* The Guidance stack is already deployed (see the root [README](../README.md)).
* A **public Route 53 hosted zone** you control and a **custom domain name** under it.
* An **ACM certificate** in the same Region covering that custom domain, for the VPC Lattice HTTPS listener.

### Steps

1. Capture the ingress VPC and NLB details from the proxy stack (adjust the stack name):

```
export STACK=guidance-vpclattice-external
export REGION=eu-west-1

export VPC_ID=$(aws cloudformation describe-stacks --stack-name $STACK --region $REGION --query 'Stacks[0].Outputs[?OutputKey==`VpcId`].OutputValue' --output text)
export NLB_DOMAIN_NAME=$(aws cloudformation describe-stacks --stack-name $STACK --region $REGION --query 'Stacks[0].Outputs[?OutputKey==`NLBDomainName`].OutputValue' --output text)
export NLB_HOSTED_ZONE_ID=$(aws cloudformation describe-stacks --stack-name $STACK --region $REGION --query 'Stacks[0].Outputs[?OutputKey==`NLBHostedZoneId`].OutputValue' --output text)
```

2. Set the values you bring:

```
export CUSTOM_DOMAIN_NAME=service.example.com
export CERTIFICATE_ARN=arn:aws:acm:<region>:<account-id>:certificate/<certificate-id>
export PUBLIC_HZ=ZXXXXXXXXXXXXX
```

3. Create the test VPC Lattice service. Use the **association** template (simplest):

```
aws cloudformation deploy --template-file vpc-lattice_service_association.yml \
  --stack-name vpclattice-test-association --region $REGION \
  --parameter-overrides CustomDomainName="$CUSTOM_DOMAIN_NAME" CertificateArn="$CERTIFICATE_ARN" VpcId="$VPC_ID" \
  --capabilities CAPABILITY_IAM
```

  Or the **endpoint** template (also pass three ingress-VPC subnets; mind the IPv4 /28 subnet prerequisites for service network endpoints):

```
aws cloudformation deploy --template-file vpc-lattice_service_endpoint.yml \
  --stack-name vpclattice-test-endpoint --region $REGION \
  --parameter-overrides CustomDomainName="$CUSTOM_DOMAIN_NAME" CertificateArn="$CERTIFICATE_ARN" VpcId="$VPC_ID" \
  VpcSubnetId1="$SUBNET1" VpcSubnetId2="$SUBNET2" VpcSubnetId3="$SUBNET3" \
  --capabilities CAPABILITY_IAM
```

4. Capture the VPC Lattice generated domain (association example shown):

```
export VPCLATTICE_SERVICE_DOMAIN_NAME=$(aws cloudformation describe-stacks --stack-name vpclattice-test-association --region $REGION --query 'Stacks[0].Outputs[?OutputKey==`VPCLatticeServiceDomainName`].OutputValue' --output text)
export VPCLATTICE_SERVICE_HOSTED_ZONE_ID=$(aws cloudformation describe-stacks --stack-name vpclattice-test-association --region $REGION --query 'Stacks[0].Outputs[?OutputKey==`VPCLatticeServiceHostedZoneId`].OutputValue' --output text)
```

5. Configure DNS. Use `PrivateHostedZoneName` to create the private zone the first time, or `PrivateHostedZoneId` to reuse an existing one:

```
aws cloudformation deploy --template-file dns-resolution.yml \
  --stack-name vpclattice-test-dns --region $REGION \
  --parameter-overrides PrivateHostedZoneName="$PRIVATE_HZ_NAME" CustomDomainName="$CUSTOM_DOMAIN_NAME" \
  VPCLatticeDomainName="$VPCLATTICE_SERVICE_DOMAIN_NAME" VPCLatticeHostedZoneId="$VPCLATTICE_SERVICE_HOSTED_ZONE_ID" \
  NLBDomainName="$NLB_DOMAIN_NAME" NLBHostedZoneId="$NLB_HOSTED_ZONE_ID" VpcId="$VPC_ID" PublicHostedZone="$PUBLIC_HZ" \
  --capabilities CAPABILITY_IAM
```

6. Validate, exactly as in Option A:

```
./test-endpoint.sh https://$CUSTOM_DOMAIN_NAME
./test-endpoint.sh https://$CUSTOM_DOMAIN_NAME --sign --region $REGION
```

### Cleanup

Delete the test stacks you created (`vpclattice-test-dns`, then `vpclattice-test-association` / `vpclattice-test-endpoint`).

---

## Credentials for signed requests

`--sign` resolves credentials in this order:

1. **The AWS credential chain (recommended).** Add `--profile <profile>` to pick a named profile, or rely on your default profile / active session. This uses `aws configure export-credentials`, which works with IAM roles and IAM Identity Center (SSO), handles temporary credentials automatically, and keeps secrets off the command line.
2. **Environment variables**, if you prefer to set them yourself: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, and `AWS_SESSION_TOKEN` (for temporary credentials).

The script never accepts secret keys as command-line arguments, because arguments are visible in process listings and shell history. Prefer option 1.

## Inspect logs

* **VPC Lattice service network access logs**: CloudWatch log group `/vpc-lattice/<service-stack-name>-service-network` (created by the test templates).
* **Proxy logs**: the per-task CloudWatch log group for the ECS cluster, showing the real client IP and the VPC Lattice link-local upstream the proxy forwarded to.
