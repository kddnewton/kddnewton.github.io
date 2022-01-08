---
layout: post
title: Ripper CHANGELOG 3.1.0
---

The Ripper module ships with the Ruby standard library and gets updated (implicitly or explicitly) every time the Ruby parser changes. Unfortunately, Ripper itself never changes version (it's been stuck at `0.1.0` [since it was first shipped](https://github.com/ruby/ruby/blob/09cfc653b77584d557a551df6a5b8ebddbbd11a2/parse.y#L801) with Ruby in 2004). As such, there isn't really a dedicated CHANGELOG, and it's somewhat difficult to determine what changed inside the Ripper module without digging into the source.

Because I [maintain](https://kddnewton.com/ripper-docs/) [a](https://github.com/kddnewton/syntax_tree) [couple](https://github.com/prettier/plugin-ruby) [of](https://github.com/kddnewton/sorbet-eraser) [things](https://github.com/kddnewton/preval) that depend on Ripper's interface, I have some insight into what goes down when Ripper updates. Because of this, I'm putting out this blog post with a list of the changes in the hope that it helps anyone else out there that may be using Ripper for their own purposes.

First of all, if you're unfamiliar with how Ripper works, I recommend checking out my [documentation project](https://kddnewton.com/ripper-docs/). It's there to help explain a lot of the terminology I'm going to use to describe the changes here. If you're interested in skipping past my description of the changes are want to just see the code that has to change, feel free to take a look at [this pull request](https://github.com/kddnewton/syntax_tree/pull/11/files) that I had to make to [kddnewton/syntax_tree](https://github.com/kddnewton/syntax_tree) to support Ruby 3.1.0.

Without further ado, the changes are listed below.

## Blocks without names

Because blocks can now be forwarded without a name, both `on_args_add_block` and `on_blockarg` have changed somewhat.

```ruby
def decorated(&block)
  # ... do something with the block here ...
end

def decorator(&)
  logger.info("About to perform the action")
  decorated(&)
  logger.info("Performed the action")
end
```

* `on_args_add_block` - previously you could rely on the second argument (the block argument) to determine whether or not a block was actually passed. Instead, you now need to check if you've recently seen an `on_op` call with the `"&"` argument. If you have, then a block is being passed through without a name.
* `on_blockarg` - the only argument to this event handler is the name of the block argument. Since you can now forward blocks, this can now be `nil` instead of always being the result of an `on_ident` call.

## Hash keys without values

You can now create hash keys without values, somewhat similar to how it's done in JavaScript. Because of this, `on_assoc_new` changed.

```ruby
x = 1
y = 2

{ x:, y: }
# => { x: 1, y: 2 }
```

* `on_assoc_new` - this event handler accepts both a key and value argument. The value argument used to be any Ruby expression, but now can also be `nil`.

## Endless methods without parentheses

You can now create endless methods without using parentheses around the arguments to method calls, which changes `on_bodystmt`, `on_def`, and `on_defs`.

```ruby
def double(value) = value * 2
def double3 = double 3

double3 # => 6
```

* `on_bodystmt` - this event handler accepts 4 arguments, corresponding to the contained statements and then 3 optional consequent clauses. Previously, the first argument was always the result of `on_stmts_new`/`on_stmts_add`. Now however, if it's nested inside an endless method definition, it can contain any Ruby expression.
* `on_def`/`on_defs` - both of these method definition event handlers accept as their last argument the statements that comprise the method definition. Previously this was always the result of `on_bodystmt` for methods with `end` keywords and a single expression for methods without `end` keywords. Now it's the result of having called `on_bodystmt` with a single expression.

## Argument forwarding

When you forward arguments using the `...` operator, it has changed position in its event handler. This changes the `on_params` event handler.

```ruby
def request(type, arg, &block)
  # ...
end

def get(...)
  request(:GET, ...)
end
```

* `on_params` - now when you're using argument forwarding, the block argument (the last argument to the `on_params` event handler) is a `:&` symbol literal. The result of `on_args_forward` has also changed position from being in the rest position (the 3rd argument) to being in the keyword rest position (the 6th argument).

## Pinned expressions

You can now pin expressions and not just identifiers within pattern matching. This changes the `on_begin` event handler.

```ruby
case 1
in ^(0 + 1)
  puts "matched"
end
```

* `on_begin` - this event handler used to always accept a single `on_bodystmt` result. It now accepts any Ruby expression in the case that it represents a pinned expression inside of a pattern match. In this case you need to determine if there has been an `on_op` call with the `"^"` value as its argument to determine if you're inside a pattern match.

## Wrapping up

For a comprehensive list of the changes that went into Ruby 3.1.0, I recommend [this blog post](https://rubyreferences.github.io/rubychanges/3.1.html). If you think I've missed anything, feel free to reach out on twitter [@kddnewton](https://twitter.com/kddnewton).
