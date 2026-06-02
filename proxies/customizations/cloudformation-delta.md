# CloudFormation delta: add a port 80 listener

Both customizations in this folder ([`http-passthrough.md`](./http-passthrough.md) and
[`https-redirect.md`](./https-redirect.md)) need the same change to [`guidance-stack.yml`](../../guidance-stack.yml): expose port `80` on the NLB and route it to the proxy container. The proxy config differs between the two (see their pages); this infrastructure delta is identical and engine-agnostic.

Apply all of the following.

## a. NLB security group: allow inbound 80

Add alongside the existing `ProxyNLBSGIPv4IngressHTTPS` rule:

```yaml
  ProxyNLBSGIPv4IngressHTTP:
    Type: AWS::EC2::SecurityGroupIngress
    Properties:
      GroupId: !Ref ProxyNLBSG
      CidrIp: !Ref AllowedIPv4Block
      IpProtocol: 'tcp'
      FromPort: 80
      ToPort: 80

  # Only needed if you deployed with an IPv6 block.
  ProxyNLBSGIPv6IngressHTTP:
    Type: AWS::EC2::SecurityGroupIngress
    Condition: Ipv6Provided
    Properties:
      GroupId: !Ref ProxyNLBSG
      CidrIpv6: !Ref AllowedIPv6Block
      IpProtocol: 'tcp'
      FromPort: 80
      ToPort: 80

  # NLB -> ECS egress on 80
  ProxyNLBSGEgressHTTP:
    Type: AWS::EC2::SecurityGroupEgress
    Properties:
      GroupId: !Ref ProxyNLBSG
      DestinationSecurityGroupId: !Ref ProxyECSSG
      IpProtocol: 'tcp'
      FromPort: 80
      ToPort: 80
```

## b. ECS security group: allow inbound 80 from the NLB

Add alongside the existing `ProxyECSSGIngressHTTPS` rule:

```yaml
  ProxyECSSGIngressHTTP:
    Type: AWS::EC2::SecurityGroupIngress
    Properties:
      GroupId: !Ref ProxyECSSG
      SourceSecurityGroupId: !Ref ProxyNLBSG
      IpProtocol: 'tcp'
      FromPort: 80
      ToPort: 80
```

## c. NLB target group and listener for 80

Add alongside `ProxyNLBTGroupHTTPS` / `ProxyNLBListenerHTTPS`:

```yaml
  ProxyNLBTGroupHTTP:
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

  ProxyNLBListenerHTTP:
    Type: 'AWS::ElasticLoadBalancingV2::Listener'
    Properties:
      DefaultActions:
        - TargetGroupArn: !Ref ProxyNLBTGroupHTTP
          Type: forward
      LoadBalancerArn: !Ref ProxyNLB
      Port: 80
      Protocol: TCP
```

## d. Container port mapping

In `ProxyTask` -> `ContainerDefinitions` -> `PortMappings`, add port 80:

```yaml
          PortMappings:
            - ContainerPort: 443
              Protocol: tcp
            - ContainerPort: 80
              Protocol: tcp
```

## e. Service load balancer binding

In `ProxyService`, add the HTTP target group to `LoadBalancers` and the listener to
`DependsOn`:

```yaml
    DependsOn:
      - ProxyNLBListenerHTTPS
      - ProxyNLBListenerHTTP
    Properties:
      # ...
      LoadBalancers:
        - ContainerName: Proxy
          ContainerPort: 443
          TargetGroupArn: !Ref ProxyNLBTGroupHTTPS
        - ContainerName: Proxy
          ContainerPort: 80
          TargetGroupArn: !Ref ProxyNLBTGroupHTTP
```
