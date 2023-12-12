---
layout: post
title: Advent of Prism
subtitle: Part 13 - Calls (part 1)
meta:
  "twitter:card": summary
  "twitter:title": "Advent of Prism: Part 13"
  "twitter:description": "This post is part of a series about how the prism Ruby parser works."
  "twitter:site": "@kddnewton"
  "twitter:image": https://upload.wikimedia.org/wikipedia/commons/thumb/7/73/Ruby_logo.svg/1200px-Ruby_logo.svg.png
---

This blog series is about how the prism Ruby parser works. If you're new to the series, I recommend starting from [the beginning](/2023/11/30/advent-of-prism-part-0). This post is about call nodes.

We are now halfway through this blog series, and it's high time we talked about the heart of Ruby programming: calling methods. Method calls take _many_ different forms. The next four posts will show all of their various incantations. For today, we'll be giving you the lay of the land so that you know what you're getting into.

Method calls in Ruby consistent of four things:

1. A receiver (implicit or explicit)
2. A name
3. The number of arguments (known as `argc`)
4. A set of flags

This is the hardest node to get right in the whole AST, because it is so foundational to Ruby's interpretation. We want to provide as much information as possible in as concise a format as possible. We also want to ensure all basic[^1] method calls can be succinctly handled by this one singular node.

We'll go through each form of method call in turn.

## Identifiers

When a plain identifier is found in Ruby, it first looks to see if that identifier maps to name of a visible local variable. If it does not, then it is considered a method call. It's important to note that this determination happens at parse time, which means if someone were to define a local variable later the earlier identifier would still map to a method call. For example:

```ruby
foo # calls method `foo`
foo = 1
foo # returns the local variable
```

Filling in our four fields for method calls looks like:

1. Receiver - the receiver is implicitly the current value of `self`
2. Name - the name is the same as the value of the identifier
3. `argc` - 0, there are no arguments
4. Flags - a special flag called `variable_call` which changes the error from a `NoMethodError` to a `NameError`

The AST for `foo` looks like:

<div align="center">
  <img src="/assets/aop/part13-call-node-1.svg" alt="call node">
</div>

## Method names

If an identifier is found that cannot be a local variable, then it is always a method call. This happens, for example, when the identifier has a `!` or `?` suffix. For example:

```ruby
foo?
```

In this case it does not check if a local is defined by that name. Filling in our fields:

1. Receiver - the receiver is implicitly the current value of `self`
2. Name - the name is the same as the value of the identifier
3. `argc` - 0, there are no arguments
4. Flags - none

The AST for `foo?` looks like:

<div align="center">
  <img src="/assets/aop/part13-call-node-2.svg" alt="call node">
</div>

## Identifiers with parentheses

If an identifier is followed by parentheses, it becomes a method call and it is not checked against the local table. Note that the number of spaces following the identifier matters. `foo()` is a method call where the parentheses wrap an empty set of arguments. `foo ()` is a method call where the first argument is `nil` (the equivalent of `()`). For example:

```ruby
foo = 1
foo() # method call to foo, even though foo is a local
```

Filling in our fields:

1. Receiver - the receiver is implicitly the current value of `self`
2. Name - the name is the same as the value of the identifier
3. `argc` - 0
4. Flags - none

Here is the AST for `foo()`:

<div align="center">
  <img src="/assets/aop/part13-call-node-5.svg" alt="call node">
</div>

## Identifiers with arguments

If an identifier is immediately followed by arguments then it becomes a method call and it is not checked against the local table. For example:

```ruby
foo = 1
foo 1 # method call to foo, even though it is also a local
```

Arguments are represented with an `ArgumentsNode`. These nodes and all of the other possible arguments will be covered in a later post. Filling in our fields for the snippet above:

1. Receiver - the receiver is implicitly the current value of `self`
2. Name - the name is the same as the value of the identifier
3. `argc` - 1, the integer `1`
4. Flags - none

The AST for `foo 1` looks like:

<div align="center">
  <img src="/assets/aop/part13-call-node-3.svg" alt="call node">
</div>

It's important to note that there is a large difference between `foo(1)` and `foo 1` in terms of the parser, but not in turns of the compiler. `foo 1` is a statement, and can only appear in places that support statements. `foo(1)` is an expression, and can appear in many more places. This is, of course, a simplification, but in general you can think of statements as exclusively being the children of `StatementsNode` nodes.

## Identifiers with blocks

If an identifier is immediately followed by a block then it becomes a method call and it is not checked against the local table. For example:

```ruby
foo = 1
foo {} # method call to foo, even though it is a local
```

Filling in our fields:

1. Receiver - the receiver is implicitly the current value of `self`
2. Name - the name is the same as the value of the identifier
3. `argc` - 0 (blocks do not count to `argc`)
4. Flags - none

The AST for `foo {}` looks like:

<div align="center">
  <img src="/assets/aop/part13-call-node-4.svg" alt="call node">
</div>

Don't worry, we'll cover blocks at a later date.

## Constants

All of the above except for the plain identifiers also work with constants. Here are a couple of examples:

```ruby
Foo?
Foo()
Foo 1
Foo {}
```

All four of these lines are method calls, even though they are using constants as their name. You don't see this often (it violates every style guide I could find to define these methods) but there are a couple of `Kernel` methods that fit this pattern that you might see in the wild, namely: `Kernel#Integer`, `Kernel#Float`, `Kernel#Rational`, and `Kernel#Complex`.

Filling in our fields:

1. Receiver - the receiver is implicitly the current value of `self`
2. Name - the name is the same as the value of the constant
3. `argc` - 0
4. Flags - none

Here is the AST for `Foo()`:

<div align="center">
  <img src="/assets/aop/part13-call-node-6.svg" alt="call node">
</div>

## `call` shorthand

Identifiers and constants alike have a special shorthand for calling the `call` method. For example:

```ruby
foo.()
Foo.()
```

Both of these are method calls to `#call` on their receivers. Filling in our fields:

1. Receiver - the left-hand side of the `.` operator
2. Name - `call`
3. `argc` - the number of arguments within the parentheses
4. Flags - none

Here is what the AST looks like for `foo.()`:

<div align="center">
  <img src="/assets/aop/part13-call-node-13.svg" alt="call node">
</div>

## Explicit receivers

All of the above examples have implicit receivers. If you explicitly specify a receiver, then it is known to be a method call. For example:

```ruby
1.to_s
```

You can also use the `::` operator to indicate a method call, though there are some nuances when you use method calls that look like constants. Filling in our fields for the above example:

1. Receiver - the expression on the left-hand side of the `.` operator
2. Name - the name immediately following the `.` operator
3. `argc` - 0 in this case
4. Flags - none

Here is the AST for `1.to_s`:

<div align="center">
  <img src="/assets/aop/part13-call-node-8.svg" alt="call node">
</div>

## Safe navigation

You can also use the `&.` operator to indicate a method call. This operator is slightly different if its receiver resolves to `nil`. If it does, then nothing is evaluated on the right-hand side of the operator (including arguments!). For example:

```ruby
foo&.bar
```

1. Receiver - the expression on the left-hand side of the `&.` operator
2. Name - the name immediately following the `&.` operator
3. `argc` - 0 in this case
4. Flags - `safe_navigation`

Here is what the AST looks like for `foo&.bar`:

<div align="center">
  <img src="/assets/aop/part13-call-node-9.svg" alt="call node">
</div>

## Unary operators

Unary operators in Ruby trigger method calls. For example:

```ruby
!foo
~foo
+foo
-foo
```

These are all method calls to the `!`, `~`, `+@`, and `-@` methods respectively. Filling in our fields:

1. Receiver - the expression on the right-hand side of the unary operator
2. Name - the name of the operator if it cannot be binary, otherwise the name of the operator and `@`
3. `argc` - 0
4. Flags - none

Here is what the AST looks like for `!foo`:

<div align="center">
  <img src="/assets/aop/part13-call-node-10.svg" alt="call node">
</div>

### `not`

There is a special `not` keyword that breaks down to a method call as well. For example:

```ruby
not foo
```

This is a method call to the `!` method. The only difference is at the parser level: `not foo` is a statement, and `not(foo)` is an expression. The fields are the same as for the `!` operator. The AST for `not foo` looks like:

<div align="center">
  <img src="/assets/aop/part13-call-node-11.svg" alt="call node">
</div>

Note that the only difference between this AST and the one for `!foo` is the `message_loc` field. This also illustrates the difference between the `message` and `name` methods on `CallNode`. `name` is derived, whereas `message` is the actual source of the method call.

## Binary operators

Many binary operators in Ruby trigger method calls. For example:

```ruby
1 + 2
```

This is a method call to the `Integer#+` method. This form has implications for parsing (namely operator precedence) but once compiled do not have any impact on execution. For example, these are almost entirely equivalent to `1.+(2)`. Filling in our fields:

1. Receiver - the receiver is the expression on the left-hand side of the operator
2. Name - the name is the same as the operator
3. `argc` - this is always 1, the expression on the right-hand side of the operator
4. Flags - none

Here is the AST for `1 + 2`:

<div align="center">
  <img src="/assets/aop/part13-call-node-7.svg" alt="call node">
</div>

## Indexing

Indexing is a special form of method call. It is a method call to the `[]` method. For example:

```ruby
foo[1]
```

Filling in our fields:

1. Receiver - the receiver is the expression on the left-hand side of the `[]` operator
2. Name - the name is always `[]`
3. `argc` - this is the number of arguments inside the `[]` operator (which can be 0!)
4. Flags - none

Here is what the AST looks like for `foo[1]`:

<div align="center">
  <img src="/assets/aop/part13-call-node-12.svg" alt="call node">
</div>

## Assignment

When a method call is immediately followed by a `=`, it changes the name of the method call by appending a `=` and appends the right-hand side of the operator as another argument. For example:

```ruby
foo.bar = 1 # a method call to bar= with one argument
foo[:bar] = 1 # a method call to []= with two arguments
```

Filling in our fields:

1. Receiver - the receiver is the expression on the left-hand side of either the `.`, `::`, `&.`, or `[]` operators
2. Name - the name is the same as the call before the `=` was found, with `=` appended
3. `argc` - one more than the number of arguments before the `=` was found
4. Flags - none

Here is what the AST looks like for `foo.bar = 1`:

<div align="center">
  <img src="/assets/aop/part13-call-node-14.svg" alt="call node">
</div>

Note that because the `[]` form can have other arguments, this includes a block. For example:

```ruby
foo.bar[&baz] = 1
```

This means to call `bar=` with a single argument (`1`) and a block that is the result of calling `#to_proc` on the result of the `baz` method call. We'll cover this more when we get to blocks. For now, here is the AST for the above snippet:

<div align="center">
  <img src="/assets/aop/part13-call-node-15.svg" alt="call node">
</div>

## Wrapping up

Wow, that was a lot of calls. This is just the first of many posts about method calls and believe it or not, these were the simplest. Suffice to say, there are _many_ ways to express method calls in Ruby. Here are a couple of things to remember from today:

* Method calls are everywhere in Ruby, even in some syntax you might not expect.
* Constants aren't necessarily constants — be sure to check for arguments!
* All arithmetic operators are method calls, and subject to redefinition.

Tomorrow we'll continue our exploration of method calls by looking at some of the most complicated ones as well as the `super` keyword. See you then!

---

[^1]: "Basic" has a loose definition here. There are method calls that can be expressed in Ruby that are quite complicated. We split up the method calls into other nodes in those cases. You'll see why when we get to them in the coming days.
