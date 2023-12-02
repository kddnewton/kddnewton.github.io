---
layout: post
title: Advent of Prism
subtitle: Part 2 - Data structures
meta:
  "twitter:card": summary
  "twitter:title": "Advent of Prism: Part 2"
  "twitter:description": "This post is part of a series about how the prism Ruby parser works."
  "twitter:site": "@kddnewton"
  "twitter:image": https://upload.wikimedia.org/wikipedia/commons/thumb/7/73/Ruby_logo.svg/1200px-Ruby_logo.svg.png
---

This blog series is about how the prism Ruby parser works. If you're new to the series, I recommend starting from [the beginning](/2023/11/30/advent-of-prism-part-0). This post is data structures.

Today, we're going to talk about the nodes that are used to represent the value literal data structures in Ruby. These include arrays, hashes, and ranges. Let's get into it.

## `ArrayNode`

Arrays in Ruby are represented by the `ArrayNode` node. They come in a couple of varieties. The nodes store a list of elements, an optional source location for their opening token, and an optional source location for their closing token. Here are a couple of examples:

```ruby
[1, 2, 3]

%w[foo bar baz]    # equivalent to ["foo", "bar", "baz"]
%i[foo bar baz]    # equivalent to [:foo, :bar, :baz]

%W[foo #{bar} baz] # equivalent to ["foo", bar.to_s, "baz"]
%I[foo #{bar} baz] # equivalent to [:foo, bar.to_s.to_sym, :baz]
```

The first example is a standard array. The next two are array literals that create a set of strings or symbols. The last two are the same except that they also allow interpolation. The `ArrayNode` node is used to represent all of these.

The `ArrayNode` can also show up in a somewhat unexpected place: the right-hand side of an assignment. This is because in Ruby you can assign multiple values at once:

```ruby
foo = 1, 2, 3
```

Semantically, this is entirely equivalent to `foo = [1, 2, 3]`. It is effectively an array with missing brackets, which is therefore exactly how it is represented in the syntax tree. (We will cover multiple assignment in a future post, but the important thing to remember is that multiple assignment is triggered by the left-hand side of the assignment, not the right.)

There is also one flag that can be set on array nodes that indicates whether or not there was a splat operator in the array, which is to make life easier on the various compilers that use prism as a frontend. The node itself looks like this in the syntax tree for `[1, 2, 3]`:

<div align="center">
  <img src="/assets/aop/part2-array-node.svg" alt="array node">
</div>

## `HashNode`

Hash literals in Ruby are represented by the `HashNode` node. They store a list of elements, the location of their opening token, and the location of their closing token. Here are a couple of examples:

```ruby
{ foo: 1, bar: 2, baz: 3 }
{ :foo => 1, :bar => 2, :baz => 3 }
{ FOO => BAR, "baz": 3 }
{ **foo.bar }
```

Regardless of the syntax used to represent the key-value pairs of the hash, they are always stored in one of two kinds of nodes, described below.

### `AssocNode`

The most common key-value pair in a hash is the `AssocNode`. It stores a key and a value, along with an optional location for the `=>` operator if one was used. The node itself looks like this in the syntax tree for `{ foo: 1 }`:

<div align="center">
  <img src="/assets/aop/part2-assoc-node.svg" alt="assoc node">
</div>

### `AssocSplatNode`

The less common element of a hash is the `AssocSplatNode`. It stores the location of the `**` operator, as well as the expression that follows it. The node itself looks like this in the syntax tree for `{ **foo }`:

<div align="center">
  <img src="/assets/aop/part2-assoc-splat-node.svg" alt="assoc splat node">
</div>

### All together

Putting all of the pieces together, here is the syntax tree for `{ foo: 1, **bar }`:

<div align="center">
  <img src="/assets/aop/part2-hash-node.svg" alt="hash node">
</div>

## `RangeNode`

Ranges in Ruby are represented by the `RangeNode` node. They store a `left` and a `right`, a flag that indicates whether or not the range is inclusive or exclusive, and the location of their operator. Here are a couple of examples:

```ruby
1..10
..10
1..
1...10
...10
1...
```

The `..` operator is inclusive, and the `...` operator is exclusive. Either side can be excluded to represent an unbounded range, but not both. The node itself looks like this in the syntax tree for `1..10`:

<div align="center">
  <img src="/assets/aop/part2-range-node.svg" alt="range node">
</div>

## Wrapping up

That's it for today. Today we explored 5 more nodes related to data structures. Here are a couple of things to remember from this post:

* Even though there are many different ways of creating arrays, they can all be represented by the `ArrayNode` node.
* Sometimes nodes can show up in unexpected places in the tree if they match the semantics of what is being expressed in the source code.
* Sometimes we add additional information to nodes to make working with them easier for only a subset of consumers. For example, the splat flag for `ArrayNode` will almost definitely not be used by linters or formatters, but it is useful for compilers.

In the next post we'll introduce nodes that read various variables.
