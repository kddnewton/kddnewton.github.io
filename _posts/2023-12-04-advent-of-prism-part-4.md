---
layout: post
title: Advent of Prism
subtitle: Part 4 - Writes
meta:
  "twitter:card": summary
  "twitter:title": "Advent of Prism: Part 4"
  "twitter:description": "This post is part of a series about how the prism Ruby parser works."
  "twitter:site": "@kddnewton"
  "twitter:image": https://upload.wikimedia.org/wikipedia/commons/thumb/7/73/Ruby_logo.svg/1200px-Ruby_logo.svg.png
---

This blog series is about how the prism Ruby parser works. If you're new to the series, I recommend starting from [the beginning](/2023/11/30/advent-of-prism-part-0). This post is about writes.

As a follow-up to yesterday's post, today we're going to talking about writing values to variables. These nodes are going to look extremely similar to yesterday's. You'll see why. Let's get straight into it.

## `InstanceVariableWriteNode`

Writing to an instance variable using the `=` operator is represented using an `InstanceVariableWriteNode`. Because the parser is reading left-to-right, it has already encountered the name of the instance variable, and has parsed it as an `InstanceVariableReadNode`. It then finds the `=` operator, and knows that it now needs to convert it into its equivalent write node. Here are some examples of this operation:

```ruby
@foo = 1
@__Foo = 1
@foo_bar = 1, 2, 3
```

This process is the same as all of the other nodes in the post as well: when the `=` operator is found, the left-hand side gets converted into a write. You'll see that this generally means creating a new node using the same fields as the read node, with the addition of the location of the `=` operator and a child node for the value being written.

Here's what the syntax tree looks like for `@foo = 1`:

<div align="center">
  <img src="/assets/aop/part4-instance-variable-write-node.svg" alt="instance variable write node">
</div>

You may be wondering at this point about the design of this node, why we didn't go in a couple of other directions. Here are a couple of other options we considered:

* An instance variable node and a write node, such that it looked like `(write (ivar :@foo) (int 1))`.
* An instance variable node with an optional `value` field, such that it looked like `(ivar :@foo (int 1))` for writes and `(ivar :@foo)` for reads.

Both of these options (and others) will work well for some consumers and not well for others. The issue is, semantically reading and writing are very different operations. If we want consumers to be able to handle individual nodes consistently without having to look at child nodes to understand what the actual type is, we need the type split here. Furthermore, writing an instance variable is very semantically different from writing — for example — a constant. We want to be able to handle these cases consistently differently. While every added node type is a tradeoff because of the growing complexity of the tree, we think (after much debate) in this case the added complexity is worth it.

## `ClassVariableWriteNode`

Writing to a class variable using the `=` operator is represented using a `ClassVariableWriteNode`. It is converted into a write node using the same process described above. Here are some examples of this operation:

```ruby
@@foo = 1
@@__Foo = 1
@@foo_bar = 1, 2, 3
```

Here is what the syntax tree looks like for `@@foo = 1`:

<div align="center">
  <img src="/assets/aop/part4-class-variable-write-node.svg" alt="class variable write node">
</div>

This is the first time we've seen `*_loc` fields, which are location fields on nodes in the tree, so let's explain those briefly. Every node in the tree stores its source location through the generic `location` accessor. In the Ruby API this returns a `Prism::Location` object that can be used to retrieve all kinds of location information about lines, columns, characters, etc. Similarly, location fields on nodes provide the same information but for inner locations that aren't represented by other child nodes. For example, In `ClassVariableWriteNode` we have `name_loc` and `operator_loc`. These are the locations of the name of the class variable and the `=` operator, respectively.

Lots of consumers will not need this additional information. In fact, JRuby and TruffleRuby have an explicit option to disable the creation of these fields in their serialized AST because they are unused. However, for tooling like linters or formatters, these fields end up being extremely useful. For example, in a formatter you want to leave comments in place as much as possible. If you have the following code:

```ruby
@@foo = # comment
  1
```

you want the formatter to leave that comment in place. It needs to know that the closest token in the tree to the comment is the `=` operator. As such, that field needs to be in place on the tree. Similarly, a linter might want to enforce that class variables are always written in a certain way. It needs to know the location of the `=` operator to do that. As a result of these requirements, you will see `*_loc` location fields on more inner nodes of the tree as we go through the rest of the series.[^1]

## `GlobalVariableWriteNode`

Writing to a global variable using the `=` operator is represented using a `GlobalVariableWriteNode`. It is converted into a write node using the same process described above. Here are some examples of this operation:

```ruby
$foo = 1
$__Foo = 1
```

Here is what the syntax tree looks like for `$foo = 1`:

<div align="center">
  <img src="/assets/aop/part4-global-variable-write-node.svg" alt="global variable write node">
</div>

## `LocalVariableWriteNode`

Local variables written with the `=` operator are represented using a `LocalVariableWriteNode`. As we mentioned with the `LocalVariableReadNode`, local variables are a bit more complicated because we have to resolve them at parse time. Therefore we additionally have a `depth` field on these nodes that represents the number of semantic scopes we need to traverse to find the declaration of the variable. Here are some examples of this operation:

```ruby
foo = 1 # will have depth 0
tap { foo = 2 } # will have depth 1
```

Here is what the syntax tree looks like for `foo = 1` when it is the first time `foo` is encountered:

<div align="center">
  <img src="/assets/aop/part4-local-variable-write-node.svg" alt="local variable write node">
</div>

As a contrast, here is what the syntax tree looks like for the `foo = 2` write in the `tap` block from the example above:

<div align="center">
  <img src="/assets/aop/part4-local-variable-write-node-2.svg" alt="local variable write node depth 2">
</div>

It's important to note for local variables that as soon as the `=` operator is encountered, the parser adds the name of the local variable to the local table. This means it is in the local table _before_ the value of the write is parsed. It also means that the local variable can be used within the value of the write as well, as in `foo = foo`.

Finally, as a somewhat interesting bit of trivia, being in the local table resolves some ambiguities in the grammar, which changes the following code:

```ruby
foo / 1#/
```

from a method call with a regular expression argument to a division between a local and the integer `1` followed by a comment.

## `ConstantWriteNode`

Writing to a relative constant with no path is represented using a `ConstantWriteNode`. It is converted into a write node using the same process described above when the `=` operator is encountered. Here are some examples of this operation:

```ruby
Foo = 1
Foo_Bar_Baz = 1
```

Here is what the syntax tree looks like for `Foo = 1`:

<div align="center">
  <img src="/assets/aop/part4-constant-write-node.svg" alt="constant write node">
</div>

## `ConstantPathWriteNode`

As the last node of today's post, writing to a constant path is represented using a `ConstantPathWriteNode`. It is slightly different in that the node doesn't get folded in quite the same way when an `=` is encountered because the `ConstantPathNode` is already an inner node in the tree. Here are some examples of what it looks like in Ruby source:

```ruby
::Foo = 1
Foo::Bar::Baz = 1
::Foo::Bar = 1
self::Foo = 1
foo.bar::Baz = 1
```

As with reads, the constant path can be relative to the current context, absolute from the root of the constant tree, or relative to some variable value. Here is what the syntax tree like for the relative constant path write of `Foo::Bar = 1`:

<div align="center">
  <img src="/assets/aop/part4-constant-path-write-node-1.svg" alt="relative constant path write node">
</div>

Here is what the syntax tree looks like for the absolute constant path write of `::Foo = 1`:

<div align="center">
  <img src="/assets/aop/part4-constant-path-write-node-2.svg" alt="absolute constant path write node">
</div>

Finally, here is what the syntax tree looks like for the constant path write relative to a variable such as `self::Foo = 1`:

<div align="center">
  <img src="/assets/aop/part4-constant-path-write-node-3.svg" alt="relative to a variable constant path write node">
</div>

## Wrapping up

Today we covered the 6 types of _direct_ writes in Ruby. Rest assured, there are many more ways to write values to variables that are _indirect_, which we'll talk about in future posts. (This includes `for` loops, `rescue` clauses, regular expressions, pattern matching, multi-writes, and many more.) Here are a couple of things to remember from this post:

* The parser can change the type of a node mid-parse depending on operators it encounters. We'll see this again in the future.
* Prism provides inner location information on nodes, which are most useful for static analysis tools.
* Again, local variables are resolved at parse time, so even local variable writes have associated depths.

In the next post we'll looks at more ways to write to variables, this time with operators other than `=`.

---

[^1]: The lack of location information is one of the things that makes the `Ripper` API so difficult to deal with. `Ripper` provides you with all of the nodes, but very few of the tokens. Furthermore its location API is based on the current state of the parser when the token/node is encountered, which can end up being very different from what you expect (it may have already read past a comment, for example). Therefore to use `Ripper` properly, you need to fully understand the state of the parser when any event is dispatched. Unfortunately, this API is also not documented or guaranteed, so it can change within a Ruby patch version.
