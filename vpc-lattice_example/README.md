# Guidance for External Connectivity to Amazon VPC Lattice (Examples)

In this folder you have three files that provide the following examples:

* `vpc-lattice_service_association.yml` builds the VPC Lattice resources needed to test the Guidance using a VPC association as connectivity method with the VPC Lattice service network.
* `vpc-lattice_service_endpoint.yml` builds the VPC Lattice resources needed to test the Guidance using a VPC endpoint (type service network) as connectivity method with the VPC Lattice service network.
* `dns-resolution.yml` creates and configures the corresponding Route 53 hosted zones and/or records to provide end-to-end service consumption using this Guidance.

## Variables

### vpc-lattice_service_association.yaml

| Name | Description | Type | Required |
|------|-------------|------|:--------:|
| VpcId | VPC ID (Ingress VPC) | `String` | yes |
| CustomDomainName | Custom Domain Name (VPC Lattice service) | `String` | yes |
| CertificateArn | Certificate ARN (for HTTPS connection) | `String` | yes |

### vpc-lattice_service_endpoint.yaml

| Name | Description | Type | Required |
|------|-------------|------|:--------:|
| VpcId | VPC ID (Ingress VPC) | `String` | yes |
| VpcSubnetId1 | VPC Subnet 1 (Ingress VPC) | `String` | yes |
| VpcSubnetId2 | VPC Subnet 2 (Ingress VPC) | `String` | yes |
| VpcSubnetId3 | VPC Subnet 3 (Ingress VPC) | `String` | yes |
| CustomDomainName | Custom Domain Name (VPC Lattice service) | `String` | yes |
| CertificateArn | Certificate ARN (for HTTPS connection) | `String` | yes |

### dns-resolution.yaml

| Name | Description | Type | Required |
|------|-------------|------|:--------:|
| PrivateHostedZoneName | Private Hosted Zone Name (for External Connectivity VPC resolution) - specificy either this value for PrivateHostedZoneId | `String` | no |
| PrivateHostedZoneId | Private Hosted Zone ID (for External Connectivity VPC resolution) - specificy either this value for PrivateHostedZoneName | `String` | no |
| CustomDomainName | Custom Domain Name (VPC Lattice service) | `String` | yes |
| VPCLatticeDomainName | VPC Lattice service generated Domain Name | `String` | yes |
| VPCLatticeHostedZoneId | VPC Lattice service generated Hosted Zone ID | `String` | yes |
| NLBDomainName | Network Load Balancer domain name | `String` | yes |
| NLBHostedZoneId | Network Load Balancer hosted zone ID | `String` | yes |
| VpcId | VPC ID (Ingress VPC) | `String` | yes |
| PublicHostedZone | Amazon Route 53 Public Hosted Zone ID | `String` | yes |

## Deployment steps

1. Deploy the Guidance Solution following the deployment steps in the root [README](../README.md) file. Obtain the VPC ID and NLB information (domain name and Hosted Zone ID) deployed by the Guidance.

```
export VPC_ID=$(aws cloudformation describe-stacks --stack-name guidance-vpclattice-externalconnectivity --query 'Stacks[0].Outputs[?OutputKey == `VpcId`].OutputValue' --output text)

export NLB_DOMAIN_NAME=$(aws cloudformation describe-stacks --stack-name guidance-vpclattice-externalconnectivity --query 'Stacks[0].Outputs[?OutputKey == `NLBDomainName`].OutputValue' --output text)

export NLB_HOSTED_ZONE_ID=$(aws cloudformation describe-stacks --stack-name guidance-vpclattice-externalconnectivity --query 'Stacks[0].Outputs[?OutputKey == `NLBHostedZoneId`].OutputValue' --output text)
```

2. First, deploy `vpc-lattice_service_association.yaml` and/or `vpc-lattice_service_endpoint.yaml` templates to create the VPC Lattice resources.

```
aws cloudformation deploy --template-file vpc-lattice_service_association.yml --stack-name vpclattice-example-association --parameter-overrides CustomDomainName="$CUSTOM_DOMAIN_NAME" CertificateArn="$CERTIFICATE_ARN" VpcId="$VPC_ID" --capabilities CAPABILITY_IAM
```

```
aws cloudformation deploy --template-file vpc-lattice_service_endpoint.yml --stack-name vpclattice-example-endpoint --parameter-overrides CustomDomainName="$CUSTOM_DOMAIN_NAME" CertificateArn="$CERTIFICATE_ARN" VpcId="$VPC_ID" VpcSubnetId1="$VPC_SUBNET_ID1" VpcSubnetId2="$VPC_SUBNET_ID2" VpcSubnetId3="$VPC_SUBNET_ID3" --capabilities CAPABILITY_IAM
```

3. Obtain the VPC Lattice service network and VPC Lattice-generated domain name. The way to obtain this information will vary depending the connectivity method with the VPC Lattice service network.

*VPC ASSOCIATION*

```
export VPCLATTICE_SERVICE_DOMAIN_NAME=$(aws cloudformation describe-stacks --stack-name vpclattice-example-association --query 'Stacks[0].Outputs[?OutputKey == `VPCLatticeServiceDomainName`].OutputValue' --output text)

export VPCLATTICE_SERVICE_HOSTED_ZONE_ID=$(aws cloudformation describe-stacks --stack-name vpclattice-example-association --query 'Stacks[0].Outputs[?OutputKey == `VPCLatticeServiceHostedZoneId`].OutputValue' --output text)
```

*VPC ENDPOINT (TYPE SERVICE NETWORK)*

```
export SERVICENETWORK_ENDPOINT_ID=$(aws cloudformation describe-stacks --stack-name vpclattice-example-endpoint --query 'Stacks[0].Outputs[?OutputKey == `EndpointId`].OutputValue' --output text)

export SERVICE_ARN=$(aws cloudformation describe-stacks --stack-name vpclattice-example-endpoint --query 'Stacks[0].Outputs[?OutputKey == `VPCLatticeServiceArn`].OutputValue' --output text)

export VPCLATTICE_SERVICE_DOMAIN_NAME=$(aws ec2 describe-vpc-endpoint-associations --vpc-endpoint-ids $SERVICENETWORK_ENDPOINT_ID --query "VpcEndpointAssociations[?AssociatedResourceArn=='${SERVICE_ARN}'].DnsEntry.DnsName" --output text)

export VPCLATTICE_SERVICE_HOSTED_ZONE_ID=$(aws ec2 describe-vpc-endpoint-associations --vpc-endpoint-ids $SERVICENETWORK_ENDPOINT_ID --query "VpcEndpointAssociations[?AssociatedResourceArn=='${SERVICE_ARN}'].DnsEntry.HostedZoneId" --output text)
```

4. Now you can deploy the DNS resolution example. If you need to create the Private Hosted Zone for the first time use the *PrivateHostedZoneName* parameter, otherwise use *PrivateHostedZoneId*.

```
aws cloudformation deploy --template-file dns-resolution.yml --stack-name vpclattice-dns-example --parameter-overrides PrivateHostedZoneName="$HOSTED_ZONE_NAME" CustomDomainName="$CUSTOM_DOMAIN_NAME" VPCLatticeDomainName="$VPCLATTICE_SERVICE_DOMAIN_NAME" VPCLatticeHostedZoneId="$VPCLATTICE_SERVICE_HOSTED_ZONE_ID" NLBDomainName="$NLB_DOMAIN_NAME" NLBHostedZoneId="$NLB_HOSTED_ZONE_ID" VpcId="$VPC_ID" PublicHostedZone="$PUBLIC_HZ" --capabilities CAPABILITY_IAM
```

