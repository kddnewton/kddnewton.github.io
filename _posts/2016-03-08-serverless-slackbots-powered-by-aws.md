---
layout: post
title: Serverless Slackbots Powered by AWS
---

Today Localytics is open sourcing two tools that help you quickly scaffold custom Slack commands using AWS Lambda, AWS API Gateway, and the Serverless framework. These tools grew out of our continued investment in making ChatOps the primary way Localytics engineers manage our infrastructure. With Serverless and a small bit of scaffolding, we’re now able to create custom Lambda functions that handle slash commands from Slack in about 10 minutes.

## ChatOps and AWS Lambda

ChatOps helps break down silos by making infrastructure management a collaborative process. Our engineering team is able to quickly see activity from our systems and tools within the same stream of information as the general discussion amongst the team about their daily work. Our chat service of choice - [Slack](https://slack.com) - provides convenient integration points with their [slash commands utility](https://slack.com/apps/manage/custom-integrations).

[AWS Lambda](https://aws.amazon.com/lambda/) is a natural fit for implementing slash commands because of its event-based architecture. Since we are deployed on AWS we also get to leverage the integrations that Lambdas have with other pieces of the AWS puzzle, like S3 event notifications and DynamoDB streams. The [Serverless framework](http://www.serverless.com/) helps fill in some of the gaps that Lambda has with its development and deployment workflow. Serverless lets you set up lifecycle stages that bind together your Lambda functions along with their dependent AWS resources, so you can easily promote code from dev to test to prod. Serverless also has an active and responsive community that is great to work with.

## `serverless-slackbot-scaffold` and `lambda-slack-router`

For scaffolding we’ve built our [serverless-slackbot-scaffold](https://github.com/localytics/serverless-slackbot-scaffold). This is a [khaos](https://github.com/segmentio/khaos) template, which is a handy utility package that uses handlebar templates to scaffold projects. The README of the repository describes the process for installing and running the templating engine. Once the new directory has been created, you’ll see a sparse serverless app, featuring a nodejs component (a Serverless structure with a specified runtime) that contains a slackbot function (representing a lambda function).

Over the course of developing our own projects, we realized common patterns were emerging around routing subcommands to the correct functions. As a result, you’ll notice that the package.json file in the nodejs directory requests an additional package besides the default Serverless dependencies, which is the [lambda-slack-router package](https://github.com/localytics/lambda-slack-router). This package’s easy DSL allows us to quickly manipulate the JSON payload coming from Slack, verify the integrity against a predefined token, and call the correct subcommand. This means we’re not restricted to commands like “/bot” but have easy access to “/bot ping”, “/bot echo”, and so on. With this package in place, the only part of this bot that needs editing is the actual business logic of the Lambda. [Example routers](https://github.com/localytics/serverless-slackbot-scaffold/tree/master/examples) are provided in the scaffold repository to get you started.

Once the business logic is written, we’re free to deploy to AWS. Following the deployment steps from the [templated project’s README](https://github.com/localytics/serverless-slackbot-scaffold/blob/master/template/README.md#deployment) we can deploy the function to a specific stage (our template contains the test, dev, and prod stages pre-configured), acquire the postback URL, and put that into the Slack configuration. Once everything has resolved, you can use the “/bot help” prebuilt command to see how to use your new bot.

## Lessons learned

The Serverless framework has aided us immeasurably in handling development and deployment of our functions, as well as brought a sense of pre-defined structure to our projects. Over the course of using Serverless, we’ve explored (and contributed to) a number of the [available plugins](https://github.com/serverless/serverless#plugins) which can be quickly implemented to augment Serverless’ abilities. As Serverless and its ecosystem continues to grow, developing Lambda functions is going to become even easier than it is now.

Feel free to use our scaffold and router for yourself to develop your own Slack integrations, and when you do please share your experience, approach, and any feedback in a gist, on a blog, or in the comments.