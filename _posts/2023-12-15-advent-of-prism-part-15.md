---
layout: post
title: Advent of Prism
subtitle: Part 15 - Call arguments
meta:
  "twitter:card": summary
  "twitter:title": "Advent of Prism: Part 15"
  "twitter:description": "This post is part of a series about how the prism Ruby parser works."
  "twitter:site": "@kddnewton"
  "twitter:image": https://upload.wikimedia.org/wikipedia/commons/thumb/7/73/Ruby_logo.svg/1200px-Ruby_logo.svg.png
---

This blog series is about how the prism Ruby parser works. If you're new to the series, I recommend starting from [the beginning](/2023/11/30/advent-of-prism-part-0). This post is about call arguments.

Today we're going to talk about the nodes we use to represent the arguments to a method call. Let's get into it.

## `ArgumentsNode`

The general list of methods that we pass to a method call is represented by an `ArgumentsNode`. This node is effectively a wrapper around the list of arguments. It is present when there is one or more arguments, and `nil` if there are no arguments. Here's an example:

```ruby
foo(1, 2, 3)
```

This is represented by the following AST:

<div align="center">
  <img src="/assets/aop/part15-arguments-node.svg" alt="arguments node">
</div>

You'll notice there's an explicit field for flags. This is only used for a single flag, which indicates the presence of a splat operator within the list of arguments. If there is a splat operator, then compilers cannot statically determine the number of arguments, and must instead determine it at runtime. So if compilers want to take a different path through the code depending on whether or not there is a splat operator, they can check this flag.

Argument lists also appear on a couple of keywords: `super`, `break`, `next`, `yield`, and `return`. We've covered `super` already, but will get to the others soon.

## `BlockArgumentNode`

When you pass a block to a method with the `&` operator, we create a `BlockArgumentNode`. This syntax implies that `#to_proc` should be called on the argument and passed to the method. Here's an example:

```ruby
foo(&bar)
```

The above snippet is represented by the following AST:

<div align="center">
  <img src="/assets/aop/part15-block-argument-node.svg" alt="block argument node">
</div>

The expression is actually optional if you're within a method definition that has an anonymous block. For example:

```ruby
def foo(&)
  bar(&)
end
```

This syntax means to forward the block from the `foo` method call down to the `bar` method call. This is also represented by a `BlockArgumentNode`, but with a `nil` expression. For example, the `bar(&)` in the above example:

<div align="center">
  <img src="/assets/aop/part15-block-argument-node-2.svg" alt="block argument node">
</div>

## `ForwardingArgumentsNode`

You can use the `...` operator to forward all arguments types (positional, keyword, and block) to a method call. This is represented by a `ForwardingArgumentsNode`. Here's an example:

```ruby
def foo(...)
  bar(...)
end
```

This will be represented by the following AST:

<div align="center">
  <img src="/assets/aop/part15-forwarding-arguments-node.svg" alt="forwarding arguments node">
</div>

In terms of actually parsing this, it's relatively simple. The `...` operator can only appear in an argument list if it has been declared in the current method's parameter list. Internally we take a shortcut by adding `...` to the local table and then checking it as we would any other identifier.

## `KeywordHashNode`

When you use internal hash syntax within an argument list, we create a `KeywordHashNode`. Here are a couple of examples:

```ruby
foo(bar: 1)
foo(:bar => 1)
foo(**bar)
```

In all of these cases we create a `KeywordHashNode`. The last two lines will be passed as a hash argument. The first line it depends on how the method was declared; it could end up being a hash in the first position or a keyword. Here's what the AST looks like for the first example:

<div align="center">
  <img src="/assets/aop/part15-keyword-hash-node.svg" alt="keyword hash node">
</div>

## `SplatNode`

When you use the `*` unary operator, we create a `SplatNode`. This can appear in a couple of different places. It can either imply to spread out a list of values or to group them. Here are a couple of examples:

```ruby
foo(*bar)

foo, * = bar
foo, = *baz

begin
rescue *Foo
end

foo in [*bar]
```

Today we'll only be looking at the first example. The others have either already been covered or will be covered in their own posts. Here's what the AST looks like for `foo(*bar)`:

<div align="center">
  <img src="/assets/aop/part15-splat-node.svg" alt="splat node">
</div>

Note that the `expression` field is optional. Just like the `&` operator, it can be used to forward arguments, as in:

```ruby
def foo(*)
  bar(*)
end
```

The AST for the method call in this example looks like this:

<div align="center">
  <img src="/assets/aop/part15-splat-node-2.svg" alt="splat node">
</div>

## `ImplicitNode`

The last type of node we'll look at today is `ImplicitNode`. This node is used to represent an implicit hash key. While not exclusively used in method calls (it can also be used in plain hashes) it is most commonly used in keyword arguments. Here is an example:

```ruby
foo(bar:)
```

This is represented by the following AST:

<div align="center">
  <img src="/assets/aop/part15-implicit-node-1.svg" alt="implicit node">
</div>

Note that an implicit node effectively wraps the node that would have been present if it were explicit. We wrap it so that we don't have to have an `ImplicitCallNode`, `ImplicitLocalVariableReadNode`, and `ImplicitConstantReadNode`. Instead it's a marker that the following subtree is implicit.

It can also be used to represent local variables, as in:

```ruby
bar = 1
foo(bar:)
```

<div align="center">
  <img src="/assets/aop/part15-implicit-node-2.svg" alt="implicit node">
</div>

Finally, it can be used to look up constants, as in:

```ruby
foo(Bar:)
```

That results in the following AST:

<div align="center">
  <img src="/assets/aop/part15-implicit-node-3.svg" alt="implicit node">
</div>

## Wrapping up

Today we looked at the many different kinds of arguments to method calls. Here are a couple of things to remember from today's post:

* `ArgumentsNode` will always be present in the event of one or more arguments.
* `BlockArgumentNode` and `SplatNode` do not necessarily have an attached expression.
* `ImplicitNode` is used to represent implicit hash values based on their key.

Tomorrow we'll wrap up our discussion of method calls by looking at the most complicated form: control-flow calls.
