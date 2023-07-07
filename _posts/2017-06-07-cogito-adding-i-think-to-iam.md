---
layout: post
title: Cogito - Adding "I think" to IAM
source: https://eng.localytics.com/cogito/
---

Today we are open-sourcing [Cogito](https://localytics.github.io/libcogito), an abstraction of [AWS IAM](https://aws.amazon.com/iam/) syntax. IAM (Identity and Access Management) is AWS's module that dictates the ability of various users and resources to mutate other resources within the AWS ecosystem. Permissions are described through a JSON-structured policy document that lives within the AWS console.

In AWS accounts with [many microservices](http://eng.localytics.com/testing-aws-scala-microservices/) like ours, IAM policies quickly become difficult to maintain. Ensuring a consistent system while balancing security checks with ease-of-use can lead to such a headache that users avoid dealing with it by tending toward allowing blanket open permissions. In addition, the structure of the JSON policies was difficult to remember and work with in larger tooling.

We wanted a tool that could abstract away some of this pain, as well as provide us with a starting point from which to move forward with better practice around our IAM policies. We wanted an intuitive way to describe policies without having to remember a complicated JSON structure, as well as the ability to check our policies into source control.

## The solution

The solution we built for all of these problems was to design a new, intuitive syntax that we could maintain in our own repositories with a minimal learning curve. This was the basis of [libcogito](https://github.com/localytics/libcogito). `libcogito` is a small C library that allows translation between the AWS-specified JSON policy document syntax and Cogito's own syntax. For example, with the built-in `AmazonS3ReadOnlyAccess` policy, you get:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:Get*",
        "s3:List*"
      ],
      "Resource": "*"
    }
  ]
}
```

In Cogito's syntax, this becomes:

```
ALLOW s3:Get*, s3:List* ON *;
```

For this small policy you can already see a large reduction in size - for more expansive policies the benefits are even greater. Through Cogito you end up writing human-readable statements that are easier to maintain and understand. You can even validate the syntax with the library on your own system, as opposed to having to hit an AWS endpoint to validate.

## Integration

### Syntax highlighting

Once we built `libcogito`, we turned our attention to integrating it into our workflow. We did this in a couple of ways. The first was to build support into our editors for easier management. As it turns out, building `.tmbundle`s is relatively straightforward, and so we built [cogito.tmbundle](https://github.com/localytics/cogito.tmbundle) for syntax highlighting.

### Humidifier

We also integrated Cogito into [humidifier](http://eng.localytics.com/humidifier-cloudformation-made-easier/), our open-source tool for managing [CloudFormation](https://aws.amazon.com/cloudformation/) resources. We've been successfully managing our CloudFormation resources for over a year now with the help of `humidifier`. However, in order to write managed policies with `humidifier`, you still ended up having to write the JSON and then dumping that into one of the properties. With Cogito, we were able to remedy this by building [cogito-rb](https://github.com/localytics/cogito-rb), a ruby gem that wraps `libcogito` and allows us to do things like:

```ruby
Humidifier::IAM::ManagedPolicy.new(
  managed_policy_name: 'TestPolicy',
  policy_document: {
    'Version' => '2012-10-17',
    'Statement' =>
      JSON.parse(Cogito.to_json(File.read('TestPolicy.iam')))
  }
)
```

This code could then be checked in alongside a `TestPolicy.iam` file, allowing easy maintenance and readability. For more examples of how to use Cogito with Ruby, check out the [cogito-rb](https://github.com/localytics/cogito-rb) repository and its associated documentation. This gem is released and available on [rubygems](https://rubygems.org/gems/cogito).

### CloudFormation

Finally, we integrated through CloudFormation syntax itself, as a [custom resource](http://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/template-custom-resources.html). Custom resources enable stacks to hit external APIs when CloudFormation stacks are created or updated. In our case, this allowed us to build a [lambda](https://aws.amazon.com/lambda/) that uses [cogito-py](https://github.com/localytics/cogito-py) and an [AWS linux](http://docs.aws.amazon.com/AmazonECR/latest/userguide/amazon_linux_container_image.html) compiled version of `libcogito` to perform the translation.

All of that is to say, we can write IAM syntax in our CloudFormation stacks. An example stack would look like:

```json
{
  "Resources": {
    "TestPolicyCogitoResource": {
      "Type": "Custom::CogitoResource",
      "Version": "1.0",
      "Properties": {
        "ServiceToken": "arn:aws:lambda:us-east-1:000123456789:function:cogito-dev-cogito",
        "Policy": "ALLOW s3:Get*, s3:List* ON *;"
      }
    },
    "TestPolicy": {
      "Type": "AWS::IAM::ManagedPolicy",
      "Properties": {
        "PolicyDocument": {
          "Fn::GetAtt": [
            "TestPolicyCogitoResource",
            "PolicyDocument"
          ]
        }
      }
    }
  }
}
```

When this stack gets deployed, a new managed policy will be created with the Cogito-translated policy document containing:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:Get*",
        "s3:List*"
      ],
      "Resource": "*"
    }
  ]
}
```

An example of how to deploy this AWS Lambda and more extensive examples can be found in our [cogito-resource](https://github.com/localytics/cogito-resource) repository. For more examples of how to use Cogito with python, check out the [cogito-py](https://github.com/localytics/cogito-py) repository and its associated documentation. This package is released and available on [pypi](https://pypi.python.org/pypi/cogito).

## Backup & restore

Using Cogito, we were able to build even more tools into our workflow. For example, the following snippets allow us to dump all of our existing IAM policies to a zip file, and then restore from that zip file whenever we want:

```ruby
#!/usr/bin/env ruby

require 'bundler/inline'

gemfile do
  source 'https://rubygems.org'
  gem 'cogito', '0.2.0'
  gem 'aws-sdk', '~> 2.9'
  gem 'rubyzip', '>= 1.0.0'
end

require 'json'
require 'zip'

Aws.config[:region] = 'us-east-1'
client = Aws::IAM::Client.new

Zip::File.open('aws-policies.zip', Zip::File::CREATE) do |zipfile|
  client.list_policies.each do |response|
    response.policies.each do |policy|
      encoded =
        client.get_policy_version(
          policy_arn: policy.arn,
          version_id: policy.default_version_id
        ).policy_version.document

      statements = JSON.parse(URI.decode(encoded))['Statement']
      statements = [statements] unless statements.is_a?(Array)

      entry_name = "#{policy.policy_id}-#{policy.policy_name}.iam"
      zipfile.get_output_stream(entry_name) do |os|
        os.write(Cogito.to_iam(JSON.dump(statements)))
      end
    end
  end
end
```

```ruby
#!/usr/bin/env ruby

require 'bundler/inline'

gemfile do
  source 'https://rubygems.org'
  gem 'cogito', '0.2.0'
  gem 'aws-sdk', '~> 2.9'
  gem 'rubyzip', '>= 1.0.0'
end

require 'json'
require 'zip'

Aws.config[:region] = 'us-east-1'
client = Aws::IAM::Client.new

Zip::File.open('aws-policies.zip') do |zipfile|
  policy_ids =
    client.list_policies.flat_map do |response|
      response.policies.map(&:policy_id)
    end

  zipfile.each do |entry|
    policy_id, policy_name = File.basename(entry.name, '.iam').split('-', 2)
    next if policy_ids.include?(policy_id)

    policy_document = {
      'Version': '2012-10-17',
      'Statement': JSON.parse(Cogito.to_json(entry.get_input_stream.read))
    }

    new_policy_id =
      client.create_policy(
        policy_name: policy_name,
        policy_document: JSON.dump(policy_document)
      ).policy.policy_id

    zipfile.rename(entry.name, "#{new_policy_id}-#{policy_name}.iam")
  end
end
```

## Wrapping up

Overall, we've had great success using Cogito within our workflow. The various integration points make it easy to understand and maintain, and it generally works well as means of solving our various pain points with AWS IAM syntax. If you also have headaches working with a large amount of policies in your system, feel free to [install cogito](https://github.com/localytics/libcogito#installation) in any of its various forms. When you do please share your experience, approach, and any feedback in a gist, on a blog, or in the comments.
