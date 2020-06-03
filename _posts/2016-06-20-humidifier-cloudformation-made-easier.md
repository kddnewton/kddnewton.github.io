---
layout: post
title: Humidifier - CloudFormation made easier
---

Today we are open-sourcing [Humidifier](https://github.com/localytics/humidifier/) - one of the tools that we use internally to manage infrastructure on Amazon Web Services (AWS) at Localytics. This Ruby gem allows you to programmatically generate domain objects that represent the AWS CloudFormation (CFN) resources you want, handling the details of JSON manipulation under the covers. We’ve found that Humidifier not only increases development speed, but also results in easy-to-understand, maintainable code that allows you to focus on building resources instead of programming in JSON.

## Motivation

As our infrastructure at Localytics continues to scale on AWS, we’ve become more and more reliant on CFN. Being able to create multiple interrelated resources in a fast and reproducible way is a must for a fast-moving technology team, especially when living in a microservice environment. CFN’s key strength lies in its ability to manage large amounts of infrastructure. Its JSON structure, however, can be inflexible, difficult to manage at times, and challenging for newcomers to CFN. Things as simple as referencing another resource in the same stack or concatenating strings requires complex objects that invariably decrease development speed.

## Existing Tools

Many tools currently exist in the industry that solve the problem of provisioning and maintaining AWS resources, such as Terraform and SparkleFormation. While we admire these tools, we found ourselves wanting something a little different. We found that SparkleFormation’s DSL was too complex for our use cases, and we missed having our resources provisioned as part of CFN stacks (which you give up with Terraform). We wanted to write the code ourselves but retain the ability to leverage CFN’s strengths.

## Building Humidifier

Fortunately, the CFN docs are in pretty good shape. [This page](http://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-template-resource-type-ref.html) in particular became the inspiration for Humidifier, as it lists every possible resource that CFN supports. Each link from that list contains the specifications for all of the attributes on each CFN resource. With those specs in hand we built Humidifier to scrape the docs, build Ruby classes for each resource, and provide accessors for every attribute available. Through these same utilities, Humidifier is able to stay current by checking and updating the specifications on a regular basis. The result is a Ruby gem that provides complete programmatic access to CFN resources, including the ability to quickly and easily deploy CFN stacks and change sets.

Using Humidifier you can drastically reduce the amount of lines that you need to write to describe your infrastructure. The following is an example of a simple stack with a load balancer and auto-scaling group built with CFN’s JSON structure.

```json
{
  "AWSTemplateFormatVersion": "2010-09-09",
  "Description": "Example stack",
  "Parameters": {
    "Env": {
      "Type": "String",
      "Description": "The deploy environment"
    }
  },
  "Resources": {
    "LoadBalancer": {
      "Type": "AWS::ElasticLoadBalancing::LoadBalancer",
      "Properties": {
        "Scheme": "internet-facing",
        "Listeners": [
          {
            "LoadBalancerPort": 80,
            "Protocol": "http",
            "InstancePort": 80,
            "InstanceProtocol": "http"
          }
        ],
        "AvailabilityZones": [
          "us-east-1a"
        ]
      }
    },
    "AutoScalingGroup": {
      "Type": "AWS::AutoScaling::AutoScalingGroup",
      "Properties": {
        "LaunchConfigurationName": "example-launch-configuration",
        "MinSize": "1",
        "MaxSize": "20",
        "AvailabilityZones": [
          "us-east-1a"
        ],
        "LoadBalancerNames": [
          {
            "Ref": "LoadBalancer"
          }
        ],
        "Tags": [
          {
            "Key": "Name",
            "Value": {
              "Fn::Join": [
                "-",
                [
                  {
                    "Ref": "Env"
                  },
                  "example-group"
                ]
              ]
            },
            "PropagateAtLaunch": true
          }
        ]
      }
    }
  }
}
```

Using Humidifier, we can build the same structure in Ruby. This code is shorter, easier to understand, and can be tested and reused like any other code you write.

```ruby
stack = Humidifier::Stack.new(aws_template_format_version: '2010-09-09', name: 'example-stack', description: 'Example stack')
stack.add_parameter('Env', description: 'The deploy environment', type: 'String')

stack.add('LoadBalancer', Humidifier::ElasticLoadBalancing::LoadBalancer.new(
  scheme: 'internet-facing',
  listeners: [{ LoadBalancerPort: 80, Protocol: 'http', InstancePort: 80, InstanceProtocol: 'http' }],
  availability_zones: ['us-east-1a']
))

stack.add('AutoScalingGroup', Humidifier::AutoScaling::AutoScalingGroup.new(
  launch_configuration_name: 'example-launch-configuration',
  min_size: '1',
  max_size: '20',
  availability_zones: ['us-east-1a'],
  load_balancer_names: [Humidifier.ref('LoadBalancer')],
  tags: [{
    Key: 'Name',
    Value: Humidifier.fn.join(['-', [Humidifier.ref('Env'), 'example-group']]),
    PropagateAtLaunch: true
  }]
))

stack.deploy(parameters: [parameter_key: 'Env', parameter_value: 'sandbox'])
```

## Open Source

Humidifier is up on GitHub here and free for use. The docs are available on GitHub pages here. When you use it, please share your experience, approach, and any feedback in a gist, on a blog, or in the comments.
