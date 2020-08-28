---
layout: post
title: Linting Ruby
---

The last couple of weeks I've been thinking about the process of linting Ruby code. For [the most part](https://www.ruby-toolbox.com/categories/code_metrics) within the Ruby community we've pretty much standardized on [rubocop](https://github.com/rubocop-hq/rubocop), and for good reason - it's an impressive project with a massive breadth in terms of how far it is willing to go to guide you toward better code. Other tools within the community exist as well, including my personal favorite [reek](https://github.com/troessner/reek).

Looking at the state of these linters, it's interesting to see that every one of them that I could find is based on other parsers. They seem to generally either use [whitequark/parser](https://github.com/whitequark/parser) or [seattlerb/ruby_parser](https://github.com/seattlerb/ruby_parser). Both of these parsers are kept up-to-date with the latest Ruby features, but it begs the question: can we write a linter for Ruby code using just the standard library?

## Ripper

Ruby ships with its own parser that you can use without installing other gems: `ripper`. To try it out, run the following code on your command line:

```bash
$ echo 'foo + bar' | ruby -rripper -e 'pp Ripper.sexp_raw(ARGF)'
```

(Briefly, this is printing out a string of code which then gets piped into a new Ruby process' standard input. The Ruby process first requires `ripper`, then executes the code to process and print a concrete syntax tree back to standard out. You can also print entire ruby files into that same process using `cat`.)

Using this, we can see the concrete syntax tree (CST) that Ripper will generate for us:

```ruby
[:program,
 [:stmts_add,
  [:stmts_new],
  [:binary,
   [:vcall, [:@ident, "foo", [1, 0]]],
   :+,
   [:vcall, [:@ident, "bar", [1, 6]]]]]]
```

This CST is a tree representation of our code. It includes location information for what `ripper` calls `scanner` events (basic leaf tokens in the tree) and array bodies for what `ripper` calls `parser` events (non-leaf nodes in the tree).

Fortunately, Ripper comes with ways to get access to these nodes _as it's parsing_, which means we can detect certain patterns with remarkable efficiency. For example, if you wanted to detect when these kinds of binary nodes occurred, you could write your own `ripper` parser, like so:

```ruby
class Parser < Ripper
  def on_binary(left, oper, right)
    pp [left, oper, right]
  end
end

Parser.new(ARGF).parse
```

Put that code into a `parser.rb` file and run:

```bash
$ echo 'foo + bar' | ruby -rripper parser.rb 
```

You'll see it hit that `binary` node and then it did it printed out the arguments it received. Now that you know how to get information about what kind of nodes exist within the syntax tree of any Ruby file, you can start to match against certain patterns.

## Assignment in condition

Let's say for example that we want to detect any time someone puts an assignment into a condition. This would look something like:

```ruby
if foo = bar
  return 'Equals'
end
```

You can see from this somewhat contrived example that this may have been a mistake. The author of this code likely was attempting to do a comparison (with `==`) and instead accidentally used a single equals assignment operator. Just for safety's sake, we want to warn the developer and disallow this kind of assignment.

First, we need to determine the pattern that we're going to match against. To do that, we need to be able to see the tree that `ripper` is generating. Reusing our script from earlier, we can put this test code into `test.rb` and then run:

```bash
$ cat test.rb | ruby -rripper -e 'pp Ripper.sexp_raw(ARGF)'
```

We end up with a bit bigger of a tree this time:

```ruby
[:program,
 [:stmts_add,
  [:stmts_new],
  [:if,
   [:assign,
    [:var_field, [:@ident, "foo", [1, 3]]],
    [:vcall, [:@ident, "bar", [1, 9]]]],
   [:stmts_add,
    [:stmts_new],
    [:return,
     [:args_add_block,
      [:args_add,
       [:args_new],
       [:string_literal,
        [:string_add,
         [:string_content],
         [:@tstring_content, "Equals", [2, 10]]]]],
      false]]],
   nil]]]
```

Here's the important thing to notice within this tree: immediately descending from the `if` node as its first child (which represents the branch predicate) is an `assign` node. This becomes relatively trivial to find, as we can extend a base `ripper` parser with a small module to find these kinds of `if` nodes:

```ruby
class Parser < Ripper::SexpBuilderPP; end

module AssignmentInCondition
  def on_if(predicate, *others)
    raise 'got an assignment in a condition' if predicate[0] == :assign
    super(predicate, *others)
  end
end

parser = Parser.new(ARGF)
parser.singleton_class.prepend(AssignmentInCondition)
parser.parse

puts 'Lint success.'
```

(You may be wondering why I would use `singleton_class` and `prepend` here - I'll come back to that.) If we put this into `linter.rb` file and then run with our previous `test.rb` file, we get:

```bash
$ cat test.rb | ruby -rripper linter.rb
Traceback (most recent call last):
	2: from linter.rb:12:in `<main>'
	1: from linter.rb:12:in `parse'
linter.rb:5:in `on_if': got an assignment in a condition (RuntimeError)
```

## Literal in condition

Now let's try a more complex example. Let's say we wanted to find any time a developer used a literal value (in this case a literal number, `true`, or `false`) inside a condition.

Effectively we have the same code as before, but with a new check to validate that the condition is a literal node. The module containing the check will look something like this:

```ruby
module LiteralAsCondition
  def on_if(predicate, *others)
    raise 'literal found in condition' if literal?(predicate)
    super(predicate, *others)
  end
end
```

Now we need to write the `literal?` method. Fortunately, Ruby 2.7 has shipped with some new pattern matching syntax that is going to feel right at home in this context since we're matching against well-known array patterns. The following code should accomplish what we want:

```ruby
def literal?(node)
  case node
  in [:@int, *] | [:var_ref, [:@kw, 'true' | 'false']]
    true
  else
    false
  end
end
```

Here we're expecting the `node` variable to be an array. If it contains `@int` as its first child, we're going to match correctly. And if instead it contains a `var_ref` node with a `@kw` child that has the strings `true` or `false`, we're also going to match correctly.

We can throw some extra spice on this by checking against `binary` nodes to make sure we don't have a literal inside one side of an `||` statement (and use a little recursion for good measure):

```ruby
def literal?(node)
  case node
  in [:@int, *] | [:var_ref, [:@kw, 'true' | 'false']]
    true
  in [:binary, left, :"||", right]
    literal?(left) || literal?(right)
  else
    false
  end
end
```

Adding onto our previous parser, we can add in this new parsing and everything should run just fine:

```ruby
parser.singleton_class.prepend(LiteralAsCondition)
```

## Linting

Now that we have the ability to match patterns that we want to find, it's a small step to a full-fledged linter. We can add a reporter with some nice ANSI color codes to get our addicting green dots:

```ruby
class Reporter
  def report_error
    print "\e[0;31;49mE\e[0m"
  end

  def report_failure
    print "\e[0;31;49mF\e[0m"
  end

  def report_success
    print "\e[0;32;49m.\e[0m"
  end
end
```

We can add a runner that will use `Dir.glob(pattern)` to get the correct files to lint (and maybe extend it later with some ignores). And we can take advantage of the way we structured our violation checks into modules to selectively turn them on and off:

```ruby
def rules_from(config)
  config.default = { 'Enabled' => true }

  Module.new do
    Rules.constants.each do |constant|
      include(Rules.const_get(constant)) if config[constant.to_s]['Enabled']
    end
  end
end

parser = Parser.new(File.read(path))
parser.singleton_class.prepend(rules_from(config))
parser.parse
```

In the above we can selectively build a module at runtime that includes only the rules we want enabled, thereby drastically increasing speed if some rules are disabled. (This as opposed to still running with them and when they get hit to check the code returning because they're in fact disabled.)

## Wrapping up

I regret to inform you that this blog post is not going to turn into the next linter you use in your day-to-day workflow. It's merely a thought experiment about ways that we could improve upon existing tooling, and also an interesting way to explore some syntax trees, metaprogramming, and new Ruby syntax.

That being said, I've bundled the code that this post references into its own [project on GitHub](https://github.com/kddeisz/rblint) that you can feel free to peruse. It's only got three rules in it, and it's definitely pretty nascient, but it's fun either way - _especially_ because you can run it like this:

```bash
$ ruby --disable-gems bin/rblint 'path/to/files/**/*.rb'
```

That `--disable-gems` option has massive speed implications depending on your system and what tool you've used to manage your Ruby versions.

## tl;dr

You can write your own linter in Ruby using just the standard library, and it's not too much code. Matching against syntax tree expressions is really nice in Ruby 2.7 with the new pattern matching syntax. Metaprogramming is fun. Ruby!
