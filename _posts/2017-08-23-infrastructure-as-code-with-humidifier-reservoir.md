---
layout: post
title: Infrastructure as code with humidifier-reservoir
source: https://eng.localytics.com/infrastructure-as-code-with-humidifier-reservoir/
---

A little more than a year ago we made the [first commit](https://github.com/localytics/humidifier/commit/f051578) to the gem that eventually became [humidifier](https://github.com/localytics/humidifier). It's [evolved quite a bit](https://github.com/localytics/humidifier/releases) in the last year, including integrating AWS' [resource specification](http://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/cfn-resource-specification.html) which had the side-effect of greatly stabilizing the API. Here at Localytics, we've been using `humidifier` in myriad ways, including managing our AWS infrastructure, launching and configuring new servers, and aiding in refactoring our network ACLs for better security (to name a few).

Today we are open-sourcing [humidifier-reservoir](https://github.com/localytics/humidifier-reservoir), a tool for building AWS infrastructure using `humidifier` and simple configuration files. This tool has evolved out of our continued effort to streamline our infrastructure while maintaining the configurability that we've worked hard to build into `humidifier`. Below are descriptions and examples on why we built `humidifier-reservoir` and how you can integrate it into your workflow.

## Flexibility

First and foremost, we originally built `humidifier` with [flexibility in mind](http://eng.localytics.com/humidifier-cloudformation-made-easier/). Previously we had evaluated other excellent tools like [Terraform](https://www.terraform.io/), [Ansible](https://www.ansible.com/), and [SparkleFormation](http://www.sparkleformation.io/). All of these tools work well and are well-supported by the community; however, we wanted something that was both more tightly integrated with [AWS CloudFormation](https://aws.amazon.com/cloudformation/) and that also allowed us more configuration options that were specific to AWS.

When working with humidifier, we found that it was great for dynamic infrastructure - or, infrastructure that changed regularly (e.g., auto-scaling groups for new application versions and their associated target groups). The weakness, however, came from static infrastructure. When we used `humidifier` to create AWS components that weren't changing regularly, we ended up duplicating a lot of the functionality in infrastructure configuration tools, with even more boilerplate.

In order words, the flexibility of `humidifier` was outweighed by the burden of having to write everything in code. We ended up determining that the best way forward was to take the best of both worlds - the flexibility of `humidifier` with the simplicity of non-code configuration files. That resulted in the birth of `humidifier-reservoir`.

## Configuration

`humidifier-reservoir` allows you to map 1-to-1 resource attributes to resources that can be immediately deployed to CloudFormation. It also allows you to define custom attributes that you can then use `humidifier` to further configure to your needs. For example, you can specify a couple of AWS IAM users in a `users.yml` file:

```yaml
EngUser:
  path: /reservoir/
  user_name: EngUser
  groups:
  - Engineering
  - Testing
  - Deployment

AdminUser:
  path: /reservoir/
  user_name: AdminUser
  groups:
  - Management
  - Administration
```

In the above example, `path`, `user_name`, and `groups` are all part of the CloudFormation resource specification, so they go straight through into the resultant JSON. Using `humidifier-reservoir`, you can simplify this further by defining a custom mapping like so:

```ruby
class UserMapper < Humidifier::Reservoir::BaseMapper  
  GROUPS = {
    'eng' => %w[Engineering Testing Deployment],
    'admin' => %w[Management Administration]
  }

  defaults do |logical_name|
    { path: '/reservoir/', user_name: logical_name }
  end

  attribute :group do |group|
    groups = GROUPS[group]
    groups.any? ? { groups: GROUPS[group] } : {}
  end
end
```

With this mapping in place, your configuration can be simplified down to:

```yaml
EngUser:
  group: eng

AdminUser:
  group: admin
```

This can greatly increase the speed with which you can develop CloudFormation templates, and ultimately makes it easier to deploy them. Finally, using tools already built into `humidifier`, you can deploy each change incrementally using change sets to view each change as it happens.

## Cogito

Further improvements to process can be gained by combining these two open-source AWS infrastructure tools with our third tool: `cogito`. With some simple code, you can take `cogito`-syntax IAM statements in deploy them into CloudFormation templates, as in:

```ruby
#!/usr/bin/env ruby

require 'cogito'  
require 'humidifier/reservoir'  
require 'json'

class PolicyMapper < Humidifier::Reservoir::BaseMapper  
  attribute :policy do |policy|
    {
      policy_document: {
        Version: '2012-10-17',
        Statement: JSON.parse(Cogito.to_json(policy))
      }
    }
  end
end

Humidifier::Reservoir.configure do |config|  
  config.stack_path = 'stacks'
  config.map :policies, to: 'AWS::IAM::ManagedPolicy', using: PolicyMapper
end

Humidifier::Reservoir::CLI.start(ARGV)
```

```yaml
S3DefaultPolicy:  
  description: Grants S3 permissions
  policy: ALLOW s3:ListBucket ON *;
```

Then by running the `./reservoir` CLI, you will have a valid CloudFormation document that you can deploy immediately.

## Lessons learned

At Localytics, we are always working on making our tools better and examining our processes for potential gains. For us, this represented a large speed gain in managing and maintaining CloudFormation templates. By keeping configuration files in a single repository and building tooling around it using `humidifier-reservoir`, all of our static infrastructure can now be deployed into CloudFormation templates using a simple CLI. Furthermore, changing our existing infrastructure is just a matter of opening a pull request.

`humidifier-reservoir` is up on GitHub [here](https://github.com/localytics/humidifier-reservoir) and free for use. When you use it, please share your experience, approach, and any feedback in a gist, on a blog, or in the comments.
