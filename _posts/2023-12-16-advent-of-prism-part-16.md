---
layout: post
title: Advent of Prism
subtitle: Part 16 - Control-flow calls
meta:
  "twitter:card": summary
  "twitter:title": "Advent of Prism: Part 16"
  "twitter:description": "This post is part of a series about how the prism Ruby parser works."
  "twitter:site": "@kddnewton"
  "twitter:image": https://upload.wikimedia.org/wikipedia/commons/thumb/7/73/Ruby_logo.svg/1200px-Ruby_logo.svg.png
---

This blog series is about how the prism Ruby parser works. If you're new to the series, I recommend starting from [the beginning](/2023/11/30/advent-of-prism-part-0). This post is about control-flow calls.

Today we're going to be looking at the four nodes that represent control-flow calls. As we saw in [Part 6 - Control-flow writes](/2023/12/06/advent-of-prism-part-6) the `&&=` and `||=` operators are quite complex. When combined with method calls, they get even more complex. Let's have a look.

## `CallAndWriteNode`

When a method call is combined with the `&&=` operator, we create a `CallAndWriteNode`. When this is done, it actually represents two method calls in one node, much like the `CallOperatorWriteNode`. Here's an example:

```ruby
foo.bar &&= 1
```

This code is semantically similar to the following:

```ruby
receiver = foo
result = receiver.bar

if result
  receiver.bar=(1)
else
  result
end
```

First, the receiver of the methods is cached on the stack. Then, the read method is called on the receiver (in this case `#bar`). If the result of the read method is truthy, then the write method is called on the receiver (in this case `#bar=`) with the right-hand side of the operator as the argument. Otherwise, the result of the read method is returned. The result of the read method is returned.

The important part to remember about this node is that it represents a potential two method calls, not just one. Static analyzers that want to find all method calls have to account for this, which is why we've chosen to split this node out from a regular `CallNode`. Here is the AST for `foo.bar &&= 1`:

<div align="center">
  <img src="/assets/aop/part16-call-and-write-node.svg" alt="call and write node">
</div>

The fields on this node are pretty much the same as `CallOperatorWriteNode`, of which we are already familiar so we won't go through all of them. The important ones to see here are `read_name` and `write_name` which are the two methods that will be called.

## `CallOrWriteNode`

When the `||=` operator is combined with a method call, we create a `CallOrWriteNode`. This node is very similar to `CallAndWriteNode`, except that it represents a different control-flow path. Here's an example:

```ruby
foo.bar ||= 1
```

This code is semantically similar to the following:

```ruby
receiver = foo
result = receiver.bar

if result
  result
else
  receiver.bar=(1)
end
```

First, the receiver of the methods is cached on the stack. Then, the read method is called on the receiver (in this case `#bar`). If the result of the read method is truthy, then the result of the read method is returned. Otherwise, the write method is called on the receiver (in this case `#bar=`) with the right-hand side of the operator as the argument. The result of the read method is returned.

Again, the important part here is that two methods are called and not just one. Here is the AST for `foo.bar ||= 1`:

<div align="center">
  <img src="/assets/aop/part16-call-or-write-node.svg" alt="call or write node">
</div>

## `IndexAndWriteNode`

As with all of the other pairs of method call nodes, we must have the equivalent for the `[]` form. When an index expression is combined with a `&&=` operator, we create an `IndexAndWriteNode`. Here's an example:

```ruby
foo[:bar] &&= 1
```

This code is semantically similar to the following:

```ruby
receiver = foo
result = receiver.[](:bar)

if result
  receiver.[]=(:bar, 1)
else
  result
end
```

First, the receiver of the methods is cached on the stack. Then, the read method is called on the receiver (in this case `#[]`) with whatever arguments are present between the brackets. If the result of the read method is truthy, then the write method is called on the receiver (in this case `#[]=`) with the arguments inside the brackets and the right-hand side of the operator as the last argument. Otherwise, the result of the read method is returned.

In this case `#[]` will always be called and `#[]=` will optionally be called. Here is the AST for `foo[:bar] &&= 1`:

<div align="center">
  <img src="/assets/aop/part16-index-and-write-node.svg" alt="index and write node">
</div>

## `IndexOrWriteNode`

Finally, if an index expression is combined with the `||=` operator, we create an `IndexOrWriteNode`. Here's an example:

```ruby
foo[:bar] ||= 1
```

This code is semantically similar to the following:

```ruby
receiver = foo
result = receiver.[](:bar)

if result
  result
else
  receiver.[]=(:bar, 1)
end
```

Surprisingly, this type of code is actually somewhat common. It is commonly used as a way of ensuring default values in arrays and hashes or as a manner of memoization. Here is the AST for `foo[:bar] ||= 1`:

<div align="center">
  <img src="/assets/aop/part16-index-or-write-node.svg" alt="index or write node">
</div>

As with the other `Index*` nodes, there are no `read_name` nor `write_name` fields because the names of the methods are always `#[]` and `#[]=`, respectively.

## Wrapping up

As we've seen in the past, `&&=` and `||=` are quite complex operators. When combined with call nodes, they can be downright confusing. However, you've now seen all of the possible places where they can appear, so hopefully they'll be a little less daunting the next time you encounter them in production code. Here are some things to remember from today's post:

* `&&=` and `||=` operators trigger two method calls when used with a call expression, not just one.
* `||=` is commonly used as a way of ensuring default values in arrays and hashes or as a manner of memoization.

We are finally done with method calls! Tomorrow we will be filling in some of the larger gaps in our knowledge to date: scopes. See you then!
