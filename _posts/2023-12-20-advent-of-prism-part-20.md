---
layout: post
title: Advent of Prism
subtitle: Part 20 - Alias and undef
meta:
  "twitter:card": summary
  "twitter:title": "Advent of Prism: Part 20"
  "twitter:description": "This post is part of a series about how the prism Ruby parser works."
  "twitter:site": "@kddnewton"
  "twitter:image": https://upload.wikimedia.org/wikipedia/commons/thumb/7/73/Ruby_logo.svg/1200px-Ruby_logo.svg.png
---

This blog series is about how the prism Ruby parser works. If you're new to the series, I recommend starting from [the beginning](/2023/11/30/advent-of-prism-part-0). This post is about the `alias` and `undef` keywords.

These two keywords are not often used, largely because there are methods that can be called to do the same thing. However, they are still a part of the Ruby language.

## `AliasMethodNode`

The `alias` keyword allows you to create an alias for a method. For example:

```ruby
alias new_name old_name
```

This creates a new method called `new_name` that is an alias for the `old_name` method from the current context. This is represented by the following AST:

<div align="center">
  <img src="/assets/aop/part20-alias-node.svg" alt="alias node">
</div>

We represent the names of the methods with symbols even if they are bare words because they can also be symbols. A semantically equivalent example to the above using symbols would be:

```ruby
alias :new_name :old_name
```

Any method name at all can be used, including those that are not valid Ruby identifiers. For example, the following is valid:

```ruby
alias push <<
```

You can also use dynamic method names with interpolated symbols, as in:

```ruby
new_prefix = "new"
old_prefix = "old"
alias :"#{new_prefix}_name" :"#{old_prefix}_name"
```

This is semantically equivalent to the first example. This is represented by:

<div align="center">
  <img src="/assets/aop/part20-alias-node-2.svg" alt="alias method node">
</div>

## `AliasGlobalVariableNode`

You can also alias global variables. For example:

```ruby
alias $new_name $old_name
```

This is represented by:

<div align="center">
  <img src="/assets/aop/part20-alias-global-variable-node.svg" alt="alias global variable node">
</div>

This is particularly useful for providing longer names for global variables that are used often. As an example, see the [English.rb](https://github.com/ruby/ruby/blob/1e5c8afb151c0121e83657fb6061d0e3805d30f6/lib/English.rb) core Ruby library.

## `UndefNode`

The `undef` keyword allows you to undefine a method. For example:

```ruby
undef foo
```

This is represented by:

<div align="center">
  <img src="/assets/aop/part20-undef-node.svg" alt="undef node">
</div>

Much like the `alias` keyword, we use symbols to represent the method names even if they are bare words. `undef` accepts multiple method names, so the following is also valid:

```ruby
undef :foo, :bar, :baz
```

This is represented by:

<div align="center">
  <img src="/assets/aop/part20-undef-node-2.svg" alt="undef node">
</div>

Finally, you can also use dynamic symbols, as in:

```ruby
undef :"foo_#{bar}"
```

## Wrapping up

The `alias` and `undef` keywords are not found very often but they are pieces of syntax that stretch back as far as Ruby 1.0. Here are a couple of things to remember from today:

* `alias` can be used to create an alias for a method or a global variable
* `undef` can be used to undefine one or more methods

In the next post, we'll be looking at throws and jumps.
