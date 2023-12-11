---
layout: post
title: Advent of Prism
subtitle: Part 11 - Defined
meta:
  "twitter:card": summary
  "twitter:title": "Advent of Prism: Part 11"
  "twitter:description": "This post is part of a series about how the prism Ruby parser works."
  "twitter:site": "@kddnewton"
  "twitter:image": https://upload.wikimedia.org/wikipedia/commons/thumb/7/73/Ruby_logo.svg/1200px-Ruby_logo.svg.png
---

This blog series is about how the prism Ruby parser works. If you're new to the series, I recommend starting from [the beginning](/2023/11/30/advent-of-prism-part-0). This post is about the `defined?` keyword.

The `defined?` keyword allows you to check if some expression is "defined" at runtime. The definition of "defined" changes depending on the expression. The expression itself can be absolutely any valid expression in the Ruby parse tree, which makes it one of the most complex nodes in the tree to reason about, even if the parsing of it is relatively simple. First, let's look at an example:

```ruby
defined?(@foo)
```

This code is asking if there is an instance variable visible in the current scope named `@foo` that is currently defined. The AST for this code looks like:

<div align="center">
  <img src="/assets/aop/part11-defined-node.svg" alt="defined node">
</div>

The inner locations provide the location of the `defined?` keyword, and the location of the optional parentheses. It contains a single pointer which points to whatever expression is being passed to the keyword.

The general execution of the `defined?` keyword pushes either a string or `nil` onto the stack, depending on whether or not the expression is defined. The string that is pushed depends on the type of expression. All-in, there are 14 different messages that can result from this check. We'll go through each, and the various nodes that lead to them being pushed.

## `"nil"`

If you pass either `nil` or `()` to the keyword. For example:

```ruby
defined?(nil)
```

## `"instance-variable"`

If you pass an instance variable, regardless of its value. For example:

```ruby
@foo = 1
defined?(@foo)
```

Interestingly this works even if you assign `nil` to `@foo`.

## `"local-variable"`

Similar to instance variables, regardless of value. For example:

```ruby
foo = 1
defined?(foo)
```

## `"global-variable"`

Any global variable that has been defined will result in this string. For example:

```ruby
$foo = 1
defined?($foo)
```

Interestingly, this works for back references only if a match has been run. For example:

```ruby
defined?($&) # => nil
// =~ ""
defined?($&) # => "global-variable"
```

This also works for numbered references, but only if there was a matching one in a regular expression. For example:

```ruby
defined?($1) # => nil
// =~ ""
defined?($1) # => nil
/()/ =~ ""
defined?($1) # => "global-variable"
```

## `"class variable"`

The same as instance and local, class variable is pushed when a class variable is defined, regardless of value. For example:

```ruby
@@foo = 1
defined?(@@foo)
```

## `"constant"`

This will perform the constant lookup and determine if a constant is valid for that name, regardless of value. Interestingly, even if `const_missing` is fired and it returns a valid constant, `nil` will be pushed instead. For example:

```ruby
defined?(Object) # => "constant"
defined?(Object::Object) # => "constant"

def Object.const_missing(_) = Object
Foo # => Object
defined?(Foo) # => nil
```

## `"method"`

If you're checking if a method is defined, you can call it within a `defined?` check and it will check if the method is there. For example:

```ruby
defined?(Object.name)
```

This works for method chains as well, which will call until it gets to the last node in the chain. For example:

```ruby
defined?(Object.name.bytes.length) # => "method"
defined?(Object.name.bytes.length.foo) # => nil
```

## `"yield"`

This is effectively a way of checking if a block is given to a given method. Checking `yield` will always result in `nil` if you're not inside of a method. If you _are_ inside of a method, it depends on if a block was given. For example:

```ruby
def check = defined?(yield)
check # => nil
check {} # => "yield"
```

## `"super"`

Similar to `yield`, this will check if there is a super method for the current method. For example:

```ruby
class Parent
  def check1 = nil
end

class Child < Parent
  def check1 = defined?(super)
  def check2 = defined?(super)
end

child = Child.new
child.check1 # => "super"
child.check2 # => nil
```

## `"self"`

This one is pretty simple. If you check if `self` is defined, you always get back `"self"`. For example:

```ruby
defined?(self)
```

Because this one is statically determined, the compiler won't even push instructions to do a check, it will instead just push on the `"self"` string.

## `"true"`

This is another one that can be statically determined. For example:

```ruby
defined?(true)
```

## `"false"`

The final one that is statically determined. For example:

```ruby
defined?(false)
```

## `"assignment"`

Any kind of assignment in the entire tree can result in `"assignment"` being pushed onto the stack. All of these are actually statically determined, so there is no equivalent runtime check being performed. It can have some interesting side-effects though. For example:

```ruby
defined?(foo) # => nil
defined?(foo = 1) # => "assignment"
defined?(foo) # => "local-variable"
```

You may not expect it, but there is no contract that `defined?` does not induce side-effects.

## `"expression"`

For any other kind of Ruby expression, you get the `"expression"` string. This is effectively a catch-all for anything that was not already handled. For example:

```ruby
defined?((alias foo bar))
defined?(foo => bar)
defined?(foo in bar)
defined?(if true; end)
```

## Wrapping up

While the `defined?` keyword is not particularly complicated to parse, it does have some very ill-defined semantics that can be quite surprising. The `DefinedNode`'s `value` field also accepts the widest variety of nodes in the entire tree, which is why I felt it deserved its own post. Here are a couple of things to remember from today:

* The `defined?` keyword is very powerful, and can check against any Ruby expression.
* There is no guarantee that `defined?` does not have side-effects.
* Ease of parsing and ease of understanding are not correlated.

Tomorrow we'll be looking at some of the nodes that we use to set up the overall structure of the tree, as well as some interesting relics from Ruby's shell-scripting origins.
