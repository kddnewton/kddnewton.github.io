---
layout: post
title: Exploring CLI best practices
source: https://eng.localytics.com/exploring-cli-best-practices/
---

Like at many software companies, we at Localytics build command-line interfaces (CLIs) that manage our internal infrastructure and processes. These tools cover a broad range of applications, including integrating with our background jobs server, creating and maintaining AWS resources, as well as handling deployment and continuous delivery. We've written all of our CLIs with ruby, using [thor](https://github.com/erikhuda/thor) to handle parsing and dispatching the commands.

For the last couple of weeks we've been fine-tuning many of these CLIs, and we've learned some things along the way about the user experience. Even though most of these CLIs are internal, we've found they need the same level of fidelity as external ones. Users expect a certain degree of quality, even from internal tooling.

Below is our list of best practices we've learned throughout this process. While this is certainly not an exhaustive list, if you follow these best practices you will be well on your way to creating an intuitive CLI that users will be happy to use.

## Options

1. _Every option that can have a default option should have a default option._

    Writing out tons of options when you're invoking a CLI is exhausting. It's prone to spelling errors, and usually results in users having to record their last usage or rely on their bash history in order to find the right incantation to make your CLI work properly. Most users coming to your CLI are trying to accomplish a task and don't need advanced configuration. Move your consumers faster through your CLI by making the most common path the default, while still allowing the fine tuning options for those that need it.

2. _Provide long, readable option names with short aliases._

    Longer option names are great for scripting the invocation of a CLI because it's clear what's happening (e.g., `--profile`). Shorter option names are great for consumers on their laptops that can remember them (e.g., `-p`). Provide both to support both use cases.

3. _Use [common command line options](https://www.gnu.org/prep/standards/html_node/Option-Table.html#Option-Table)._

    If your CLI is consistent with common patterns across the industry, your users are more likely to find it intuitive. Don't use `--recur` when you can use `-r` and `--recursive`. You want your script to contain the fewest number of surprises; being unique doesn't provide anything other than confusion.

4. _Provide options for explicitly identifying the files to process._

    A lot of CLIs perform some action over files or directories, be it reading them, parsing them, or even just counting them. Instead of requiring your users to execute your CLI in a specific working directory, provide the ability to point to those files directly. This saves the end user the effort of having to remember the current directory, and leads to many fewer extraneous `cd` statements in the middle of scripts.

5. _Don't have positional options._

    Options that depend on the position in which they were given are difficult to work with. If you're going to parse command line options yourself, make sure they can be specified in any order.

## Usage

{:start="6"}
6. _Provide an extensive, comprehensive help command that can be accessed by `help`, `--help` or `-h`._

    You want your users to forget how to invoke your CLI, it means it was intuitive and didn't require extra brain power to grok. For those moments when they can't figure out what they need to know, provide an intuitive help command that lists every option, and how to use it. If it's a more extensive CLI, make sure there's a help command for each individual command as well. This advice is particularly salient when you come back to working on it after a while and can't remember how to invoke your own CLI.

7. _Provide a version command that can be accessed by version, `--version` or `-v`._

    If your CLI is going to be distributed, make sure you provide an intuitive way to access the version information. It will save you and the end user time if it's easy to access, as bug reports can come with a version attached. Follow [semantic versioning](http://semver.org/) so your users can expect breaking changes only on major releases.

8. _Don't go for a long period without output to the user._

    Sometimes your script will take longer to execute than people expect. Outputting something like `'Processing...'` can go a long way toward reassuring the user that their command went through. Engineers especially have a natural tendency to distrust something they didn't write themselves, which can lead to people exiting out of a program that they think is hung.

9. _If a command has a side effect provide a dry-run/whatif/no_post option._

    Especially for CLIs that impact production systems, it's handy to have the CLI run through the motions without actually executing anything. This gives extra reassurance that what the user typed in corresponds to what they think it's going to do.

10. _For long running operations, allow the user to recover at a failure point if possible._

    It's a terrible experience to get halfway done processing a large number of files/items/etc. only to have the script crash with no way to restart where it left off. It may not even be the fault of the script itself - it could be something as simple as network connectivity. If your script fails halfway through, process the errors appropriately and allow the script to restart where it left off.

## Interfacing

{:start="11"}
11. _Exit with nonzero status codes if and only if the program terminated with errors._

    Consistent exit statuses mean your CLI can be embedded within larger shell scripts, making it much more useful. Allow your users to switch on whether or not it was a clean exit, and handle the errors as they see fit.

    Conversely, don't exit with a nonzero status code if your CLI didn't encounter an error. Your cleverness will end up confusing and frustrating your users, especially if `-e` is set.

12. _Write to stdout for useful information, stderr for warnings and errors._

    Depending on the context your CLI is run in, stdout and stderr can point to very different locations. Don't make it unnecessarily difficult for your users to find the correct logs when there's an error, or to parse the logs between what they need to know and what's just a warning.

## Technical design

{:start="13"}
13. _Keep the CLI script itself as small as possible._

    This point is less specific to CLI design, and more general good software design. Move as much business logic out of the actual CLI script as possible. Your script will be much more easily extended with a more modular code design. If you want a web or application view of the functional logic that your CLI performs, it's much easier to reuse if your code is already properly factored out of the main CLI controller. As an added benefit, this makes the code easier to test.

14. _Reserve outputting stack traces for truly exceptional cases._

    For users that aren't familiar with CLIs, stack traces can be intimidating. Oftentimes, even with good error messaging, the additional output can lead users to think something went wrong with the actual program as opposed to their configuration or option combination. If you can tell when exceptional behavior is going to happen in your program, process your own errors properly, and output only the information that the user needs to know.

## Libraries

As part of the last point, we are open-sourcing two libraries we have built to make it easier to invoke thor CLIs within a safe execution context, as well as handling other types of callbacks. They are `hollaback` and `thor-hollaback`. `thor-hollaback` adds callbacks to thor à la rails controllers. Using `thor-hollaback`, you can accomplish this point by:

1. Having a custom error class
2. Wrapping your CLI with a `class_around` that points to an error handler
3. Writing your error handler

As an example, see the below:

```ruby
require 'thor'
require 'thor/hollaback'

module MyProgram
  class Error < StandardError
  end

  class CLI
    class_option :debug, desc: 'Sets up debug mode', aliases: ['-d'], type: :boolean
    class_around :safe_execute

    desc 'test [arg]', 'The test command'
    def test(arg)
      raise Error, 'Oh no!' if arg == 'fail'
    end

    no_commands do
      def safe_execute
        yield
      rescue Error => error
        raise error if options[:debug]
        STDERR.puts error.message
        exit 1
      end
    end
  end
end
```

## Lessons learned

As our continued use of CLIs to manage infrastructure and processes increases, we will continue to rely on this list for helping us build usable, intuitive interfaces for our users. We hope this list will help you build better CLIs as well.

Both gems are available on [rubygems.org](https://rubygems.org/) and are freely available for use. When you use them, please share your experience, approach, and any feedback in a gist, on a blog, or in the comments.
