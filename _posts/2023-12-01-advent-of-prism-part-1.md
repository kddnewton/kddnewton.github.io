---
layout: post
title: Advent of Prism
subtitle: Part 1 - Literals
meta:
  "twitter:card": summary
  "twitter:title": "Advent of Prism: Part 1"
  "twitter:description": "This post is part of a series about how the prism Ruby parser works."
  "twitter:site": "@kddnewton"
  "twitter:image": https://upload.wikimedia.org/wikipedia/commons/thumb/7/73/Ruby_logo.svg/1200px-Ruby_logo.svg.png
---

This blog series is about how the prism Ruby parser works. If you're new to the series, I recommend starting from [the beginning](/2023/11/30/advent-of-prism-part-0). This post is literals, and their variations.

## Background

### Parsers

Before we dive into today's topic, we need to take a step back and discuss what a parser is, what it does, and why it's useful.

First, let's first imagine that we have a bunch of multi-colored blocks (my kids are pretty young, so my metaphors are highly likely to involve childrens' toys). Let's imagine we're playing with our blocks and an annoying adult comes along and tries to make this into an educational experience. They start by asking us some questions:

* How many blocks are there?
* How many red blocks are there?
* How many rectangular blocks are there?
* If you stack all of the blocks, how high would the stack be?
* How many more blue blocks are there than red blocks?

You could get an answer to all of these questions by counting blocks in the same jumble every time. However, different ways of organizing the blocks would yield answers to these questions more quickly. If you're frequently trying to count by color, then sorting the blocks by color first would make answering these questions easier. If you're frequently trying to count by shape, the same theory applies. If you're trying to count height, however, that would be a very different application. Sorting by shape might help, but sorting by color certainly wouldn't.

Whatever organizational scheme you choose for your blocks will end up having tradeoffs for which questions can be answered most easily. In programming we would call each of these schemes an "intermediate representation" or IR. Succinctly: IRs allow mutating source data into a representation that makes answering some questions easier.

Relating this all back to our purposes today, a parser is a library that transforms source code into a syntax tree, which itself is an intermediate representation of the code. Its purpose is to make it easier to execute the code. Most Ruby runtimes will then take that syntax tree and transform it again into another intermediate representation, usually called a bytecode, through a compiler.

The reason I chose this metaphor is that it's important to remember that there's nothing stopping programming languages from executing source code directly by reparsing files every time they're executed. We choose to use parsers to transform source code into syntax trees and other intermediate representations to make it easier to work with and answer questions. I hope I didn't lose you there in the metaphor. tl;dr, parsers transform source code into syntax trees. Let's move on to syntax trees themselves.

### Syntax trees

Syntax trees are a way of representing source code in a tree structure. Every node in the tree represents a different part of the source code. If you squint sideways at a piece of source code, you might just be able to make out the syntax tree by looking at the indentation. Here's an example:

```ruby
class Foo
  def foo
    bar +
      baz
  end
end
```

There are lots of nodes in the syntax tree, but the core ones that you can see are:

```
(program
  (class :Foo
    (def :foo
      (call :bar
        (arguments (call :baz))
      )
    )
  )
)
```

See how the structure of the tree loosely mirrors the structure of the indentation? That's not a coincidence. As programmers we're taught to indent our code to make it easier to read. The way we indent is to usually group statements at the same level of the syntax tree together.

Nodes in the tree have certain fields associated with them. In the tree above, it's using an s-expression format, which has been around since the 1950s with the introduction of LISP. The first element of the s-expression is the type of the node. The rest of the elements are the children of the node. For example, the `class` node has two children: the name of the class (`Foo`) and the body of the class. We'll use many representations of syntax trees in this blog series, including s-expressions when we want to simplify the tree. Note that we've lost some information in this representation, like the location of these nodes in the source. This will be important later as we decide which information to keep around and which to discard.

Finally, let's talk about individual nodes in the tree.

### Nodes

Every node in the tree has a set of fields. These fields can be either child nodes or attributes. For example a `ClassNode` has a `body` field which is either a `StatementsNode`, a `BeginNode`, or `nil` (don't worry, we'll cover this node in depth later). A `ClassNode` will also have a `name` field which returns a symbol describing the name of the class. In prism, there are 12 types of fields that can be on nodes. We'll describe each as they come up. If you're feeling adventurous and want to look at the fields yourself, you can find them [here](https://github.com/ruby/prism/blob/d8e816180f50cc47392a660be0605e59ecf71a86/config.yml).

### Prism

Okay, I think that's enough background for now. Rest assured, we'll be talking about prism, parsers, intermediate representations, syntax trees, and nodes for the entire blog series. With all of this information in our heads, let's see how it applies to literals in Ruby.

## Numbers

There are four different kinds of numbers in Ruby syntax: integers, floats, rationals, and imaginary numbers. They are described below.

### `IntegerNode`

By far the most common number is the integer. It comes in a couple of varieties. It can be seen with different bases:

```ruby
10   # base decimal, value 10
0d10 # base decimal, value 10
0b10 # base binary, value 2
0o10 # base binary, value 8
010  # base octal, value 8
0x10 # base hexidecimal, value 16
```

A 0 prefix indicates the number has a different base. The `d`, `b`, `o`, and `x` prefixes indicate the base. If one of those four letters is omitted, the base is assumed to be octal.

Integers can also be signed:

```ruby
-1
```

This works for all bases. It's important to note that negative integers are a single node in the syntax tree. This means they do not respect the definition of `Integer#-@`. There are therefore some interesting differences between `-1` and `-(1)` (the second one is a method call).

Integers are also allowed to have underscores scattered throughout them in any inner position (though not doubled):

```ruby
1_000_000
2023_12_01
```

When prism parses an integer, it keeps track of a flag indicating the base of the integer in addition to every node's common flags and location information. Prism does not parse the actual value of the integer because different consumers of the prism library will have different ways of representing integers in memory. It is the responsibility of the consumer to transform its value into a useful representation. In the Ruby API we provide a `IntegerNode#value` method that calls `Kernel#Integer()` with the slice of the source that the integer represents.

The node itself looks like this in the syntax tree for `1`:

<div align="center">
  <img src="/assets/aop/part1-integer-node.svg" alt="integer node">
</div>

### `FloatNode`

Floats are also relatively common in Ruby. These are numbers that contain a decimal point or use scientific notation. They can be signed (like integers) and have the same interesting proprieties as integers when it comes to negative numbers. They also support underscores in the same way integers do. Unlike integers, they cannot have other bases. Here are a couple of examples:

```ruby
1.0
1.0e10
1e10
-1.0
```

When prism parses a float, it only keeps the location information around. Like integers, it is the responsibility of the consumer to parse the actual value. In the Ruby API, we provide `FloatNode#value` which uses `Kernel#Float()` to parse the value.

The node itself looks like this in the syntax tree for `1.0`:

<div align="center">
  <img src="/assets/aop/part1-float-node.svg" alt="float node">
</div>

### `RationalNode`

Rationals are objects in Ruby that represent a ratio between two numbers. They can be derived from integers or floats. They are represented in Ruby source by appending an `r` character to the end of a number. They have the same base options as integers, can be signed, and support underscores. Interestingly when used with a float they specifically do not support scientific notation. Here are some examples:

```ruby
1r
0x10r
10.0r
-20r
```

When prism parses a rational, it parses the underlying number as its own node and then wraps it in a rational node. The inner node can be accessed through the `numeric` field on `RationalNode`. The rational node itself also does not parse the value, but it can be accessed through `RationalNode#value` in the Ruby API which calls `Kernel#Rational()` to get the value.

The node itself looks like this in the syntax tree for `1r`:

<div align="center">
  <img src="/assets/aop/part1-rational-node.svg" alt="rational node">
</div>

### `ImaginaryNode`

Complex numbers are objects in Ruby that represent a pair of numbers, one real and one imaginary. The imaginary component can be derived from integers, floats, or rationals by appending an `i` character to the end of the number. It's important to note for these numbers that only the imaginary part is being represented in the syntax. They have the same properties as the numbers they are derived from. Here are some examples:

```ruby
1i
0x10i
10.0i
1ri
-20ri
```

When prism parses an imaginary number, it parses the underlying number as its own node and then wraps it in an imaginary node. The inner node can be accessed through the `numeric` field on `ImaginaryNode`. The imaginary node itself also does not parse the value, but it can be accessed through `ImaginaryNode#value` in the Ruby API which calls `Kernel#Complex()` to get the value.

The node itself looks like this in the syntax tree for `1ri`:

<div align="center">
  <img src="/assets/aop/part1-imaginary-node.svg" alt="imaginary node">
</div>

## Booleans

The next set of nodes are the booleans and `nil`. These are very simple nodes in the syntax tree - none of them have any information other than their type and source location. We'll still go over them here for completeness.

### `TrueNode`

Whenever the `true` keyword is used, it is represented in the syntax tree as a `TrueNode`. Here's an example:

```ruby
true
```

The node itself looks like this in the syntax tree for `true`:

<div align="center">
  <img src="/assets/aop/part1-true-node.svg" alt="true node">
</div>

### `FalseNode`

Whenever the `false` keyword is used, it is represented in the syntax tree as a `FalseNode`. Here's an example:

```ruby
false
```

The node itself looks like this in the syntax tree for `false`:

<div align="center">
  <img src="/assets/aop/part1-false-node.svg" alt="false node">
</div>

### `NilNode`

Whenever the `nil` keyword is used, it is represented in the syntax tree as a `NilNode`. Here's an example:

```ruby
nil
```

The only particularly interesting thing to remember here is that this is representing `nil` being used in the actual syntax, as opposed to us trying to represent a missing value in the syntax tree. So for example, `1..` would be parsed as a range node with an `right` field that it itself `nil` (but not represented by a `NilNode`). The node itself looks like this in the syntax tree for `nil`:

<div align="center">
  <img src="/assets/aop/part1-nil-node.svg" alt="nil node">
</div>

## Parse metadata

Ruby allows you to access certain metadata about the current file being parsed. These are keywords in the Ruby language, and are represented by the following three nodes.

### `SourceFileNode`

Whenever the `__FILE__` keyword is used, it is represented in the syntax tree as a `SourceFileNode`. Here's an example:

```ruby
__FILE__
```

This will always return the name of the file being parsed. Usually you will find these nodes being used to find a path that is relative to the current file or provided as debugging information to the `eval` family of methods.

Because we know the name of the file being parsed as its being parsed, prism helpfully adds a `filepath` field to the `SourceFileNode` node that contains the name. The node itself looks like this in the syntax tree for `__FILE__`:

<div align="center">
  <img src="/assets/aop/part1-source-file-node.svg" alt="source file node">
</div>

### `SourceLineNode`

Similar to the `__FILE__` keyword, the `__LINE__` keyword is represented in the syntax tree as a `SourceLineNode`. Here's an example:

```ruby
__LINE__
```

This will always return the line number of the current line being parsed. This keyword is almost always used to provide debugging information to the `eval` family of methods. The node itself looks like this in the syntax tree for `__LINE__`:

<div align="center">
  <img src="/assets/aop/part1-source-line-node.svg" alt="source line node">
</div>

### `SourceEncodingNode`

Finally, we have the `__ENCODING__` keyword. This is represented in the syntax tree as a `SourceEncodingNode`. Here's an example:

```ruby
__ENCODING__
```

This is useful for finding the `__ENCODING__` of the current file, which can be changed by a magic comment at the top of the file, like so:

```ruby
# encoding: Shift_JIS
```

We'll dive into encodings in detail in a future post. In the meantime, the node itself looks like this in the syntax tree for `__ENCODING__`:

<div align="center">
  <img src="/assets/aop/part1-source-encoding-node.svg" alt="source encoding node">
</div>

## `SelfNode`

This isn't exactly a "literal", but it didn't fit into many other categories either. Accessing the current value of `self` is syntactically simple, while semantically very complex. Fortunately for us, it only comes in one syntactic variation:

```ruby
self
```

The node itself looks like this in the syntax tree for `self`:

<div align="center">
  <img src="/assets/aop/part1-self-node.svg" alt="self node">
</div>

## AST design

A quick note about the design of these nodes before we wrap up. You may ask yourself why we have separate nodes for the various kinds of numbers in the tree. After all, for the most part they will be treated the same by the various compilers that use prism. This gets into a much broader, important question about the granularity of nodes in the syntax tree.

Technically, you could represent every node in the tree with the same kind of object and treat them all homogeneously. In fact, many tools do exactly this by providing their own s-expression object. However, there are a couple of downsides to this approach:

* You have to query the object itself to get its type information. This means you don't get a lot of the niceties that Ruby provides you like pattern matching, `case` statements, or `is_a?` checks.
* Treating all of the nodes the same makes it unclear where type-specific functionality should live. Oftentimes this means it gets pushed out to separate methods that accept a node. Worse, it could end up being defined on every node and returning `nil`/raising an error when it's called on the wrong type.
* The reality is not all nodes _should_ be treated the same - a lot of them are fairly unique. Treating them all the same hides some of the more interesting aspects of the language, thereby making it harder to understand.

On the other hand, you could end up having far too many nodes. In the ripper syntax tree, there are more than 10 different kinds of nodes for handling various types of method calls. If you're writing a tool that wants to lint Ruby code, that means you need to handle all of those different kinds of nodes. This can be a lot of work, and is very error prone.

Clearly, there's a balancing act to be performed here. In prism, we've made a couple of decisions that we think strike a good balance:

* You should never have to look at a child node or field to determine the type of a node. For example, we don't have a generic `Assignment` node, which would mean you would have to go and look at the target of the assignment to know how to handle it.
* Nodes should be split on semantic boundaries, not syntactic boundaries. For example, we have a `CaseNode` and a `CaseMatchNode`, for `case ... when` and `case ... in` respectively. While these nodes do use the same `case` keyword, semantically they are vastly different.
* Nodes should use flags to indicate divergence within their type rather than creating new nodes. For example, we could have created a `BinaryIntegerNode` any time an integer used the `0b` prefix. However, this would have meant every consumer would have had to handle all bases for all number types, which would quickly have gotten out of hand.

Designing for multiple consumers is very hard, and something we've spent quite a bit of time discussing and working on. I'm under no delusions that the prism syntax tree is perfect, but I can confidently say that it is the best Ruby syntax tree that has been created to date. This is based on the fact that no one person has had total say in its design: from the beginning it has been designed by a committee of people with all varying interests (different runtimes, tools, and uses cases).

## Wrapping up

There you have it! In this first post we talked briefly about the role of a parser, we introduced the first 11 nodes in the tree, and we had a brief discussion on tree design. Here are a couple of things to remember from this post:

* Parsers transform source code into a meaningful intermediate representation.
* Integers have a base, and it's implicitly octal if it starts with 0 and no letter.
* Designing a syntax tree is hard, and there are tradeoffs to be made.

In the next post we'll introduce nodes used to represent data structures.
