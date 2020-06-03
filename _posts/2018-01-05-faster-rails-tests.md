---
layout: post
title: Faster Rails tests
---

Feedback loop speed in one of the biggest contributing factors to overall development time. The faster you get results, the faster you can move on to other things. A fast enough test suite is therefore critical to teams' success, and is worth investing some time at the beginning to save in the long run.

Below is a list of techniques for speeding up a Rails test suite. It is not comprehensive, but should definitely provide some quick wins. This list of techniques assumes you're using [`minitest`](https://github.com/seattlerb/minitest), but most everything should translate over to [`rspec`](https://github.com/rspec/rspec) by simply replacing `test/test_helper.rb` with `spec/spec_helper.rb`.

## Lead with data

Note that in general you shouldn't apply any technique until you measure. A great tool for that is [`ruby-prof`](https://github.com/ruby-prof/ruby-prof). You can add a trigger to your test suite that will profile the entire thing (note that this takes quite a while for a larger test suite) and writes out the results to a file that you can peruse later.

In `test/test_helper.rb`:

```ruby
if ENV['PROFILE']
  require 'ruby-prof'
  RubyProf.start

  Minitest.after_run do
    File.open('tmp/profile.out', 'w') do |file|
      result = RubyProf.stop
      printer = RubyProf::FlatPrinter.new(result)
      printer.print(file, min_percent: 0.1)
    end
  end
end
```

This will list the methods in which your test suite spent the longest amount of execution time, and is a good starting point from which to begin looking for solutions.

Additionally you can use a plugin for your test runner that will report the longest running tests. For `minitest`, you can use [`minitest-reporters`](https://github.com/kern/minitest-reporters)'s `MeanTimeReporter`.

In `test/test_helper.rb`:

```ruby
if ENV['PROFILE']
  require 'minitest/reporters'
  Minitest::Reporters.use!(Minitest::Reporters::MeanTimeReporter.new)
end
```

## [`bcrypt`](https://github.com/codahale/bcrypt-ruby)

The `bcrypt` gem (used by `has_secure_password`) takes a while to compute password hashes, and generally you don't need that kind of security in test. Instead, you can roll an incredibly simple and fast crypto that just reverses the input string. The point of this is that you don't need to worry about cryptographic security if you're just logging in in tests, and this can save a lot of cycles (especially in systems tests).

In `test/test_helper.rb`:

```ruby
module BCrypt
  class Password
    def initialize(encrypted)
      @encrypted = encrypted
    end

    def is_password?(unencrypted)
      @encrypted == unencrypted.reverse
    end

    def self.create(unencrypted, **)
      unencrypted.reverse
    end
  end
end
```

## [`bootsnap`](https://github.com/Shopify/bootsnap)

`bootsnap` is a gem that does a ton to speed up the boot time of your application, including prescanning load paths and precompiling instruction sequences. It's additionally baked into the default Rails 5.2 `Gemfile`. Follow the instructions in the README to get an automatic speed boost to the test suite startup time.

## Cache `Time::utc` calls

Since you're typically working with a smaller dataset in tests (especially if you're working with Rails fixtures) the number of unique time objects that are going to be serialized/deserialized from the database is going to be relative small. As such, caching the `::utc` responses can drastically reduce the time spent in this method.

In `test/test_helper.rb`:

```ruby
class << Time
  prepend(
    Module.new do
      def cache
        @cache ||= {}
      end

      def utc(*args)
        cache[args] ||= super
      end
    end
  )
end
```

## Disable `ActiveSupport::Notifications`

`ActiveSupport::Notifications` allow you (and Rails itself) to hook into a system that notifies objects when certain events happen throughout the system. These take up cycles that don't need to be spent in test unless you're specifically testing them. You can turn them off both explicitly unsubscribing from each predefined event and by overriding the `ActiveSupport::Notifications::instrument` method to not even check if a notification needs to be pushed out.

In `test/test_helper.rb`:

```ruby
%w[sql.active_record render_collection.action_view render_partial.action_view
   logger.action_view render_template.action_view].each do |notification|
  ActiveSupport::Notifications.unsubscribe(notification)
end

class << ActiveSupport::Notifications
  def instrument(_, payload = {})
    yield payload if block_given?
  end
end
```

## Disable garbage collection

WARNING: This may or may not speed up your tests, depending on the verison of Ruby that you're running, the content of your tests, the nature of your application, and the nature of your test suite. This could potentially have very negative consequences, as in if your entire test suite were testing CSV deserialization (read: lots of memory usage). For SOME test suites however, you can reap major speed wins by taking GC out of the equation entirely.

In `test/test_helper.rb`:

```ruby
GC.disable
```

## Disable logging

Logging is Rails tests is opt-out as opposed to opt-in. It's useful when you need it, but can drastically slow down speed when you don't. Disable all of Rails' various logging facilities to recoup some speed.

In `config/environments/test.rb`:

```ruby
Rails.application.configure do
  config.logger = Logger.new(nil)
  config.log_level = :fatal
end
```

## [`fast_blank`](https://github.com/SamSaffron/fast_blank)

If you're using the `blank?` or `present?` method heavily in your code (and are therefore seeing it in your profile) you can use the `fast_blank` gem to drastically improve the perform of these methods. You should see a significant drop off in the amount of time spent in these methods just by adding this gem to your `Gemfile`.

## [`fast_underscore`](https://github.com/kddeisz/fast_underscore)

`fast_underscore` is a small gem that overwrites one method from Rails: `ActiveSupport::Inflector#underscore`. It's used a lot internally in Rails (determining table names, determining inverse associations, etc.) and can end up eating up a large percentage of the execution time of the test suite. Follow the instructions in the README to get an automatic speed boost, especially to the startup time of the test suite.

## [`paperclip`](https://github.com/thoughtbot/paperclip)

If you're using `paperclip` to handle image uploads and you're generating multiple styles from the input, that can take a very long time. `Paperclip` will shell out to [`ImageMagick`](https://www.imagemagick.org) to identify and convert the images, and these steps usually aren't necessary in test. First, disable post processing so that you don't generate the thumbnails.

In `test/test_helper.rb`:

```ruby
module Paperclip
  class Attachment
    def post_process(*)
      false
    end
  end
end
```

You can then choose to either leave in the call to [`identify`](https://www.imagemagick.org/script/identify.php) to check content-type or remove that altogether as well. If you do leave it in, you can speed it up by using a different fork function.

`paperclip` depends on the [`cocaine`](https://github.com/thoughtbot/cocaine) gem to run the `identify` command. `cocaine` supports multiple strategies for how to run commands, from which it chooses the best strategy to use on the running platform. The default strategy is `Process.spawn`, but this can be sped up with the [`posix-spawn`](https://github.com/rtomayko/posix-spawn) gem. The difference (from the README) is below:

fork(2) calls slow down as the parent process uses more memory due to the need to copy page tables. In many common uses of fork(), where it is followed by one of the exec family of functions to spawn child processes (Kernel#system, IO::popen, Process::spawn, etc.), it’s possible to remove this overhead by using special process spawning interfaces (posix_spawn(), vfork(), etc.)

The last technique taken from a [great blog post](https://blog.instabug.com/2015/09/optimizing-paperclip-gem-for-testing-and-production/) on speeding up `paperclip`.


## Use a `MemoryStore`

A `MemoryStore` in general is going to be much faster than a `FileStore` for caching. If you are using your cache anywhere in test, be sure to switch it over to a `MemoryStore` in your configuration.

In `config/environments/test.rb`:

```ruby
Rails.application.configure do
  config.cache_store = :memory_store
end
```
