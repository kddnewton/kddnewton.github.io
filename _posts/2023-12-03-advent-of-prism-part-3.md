---
layout: post
title: Advent of Prism
subtitle: Part 3 - Reads
meta:
  "twitter:card": summary
  "twitter:title": "Advent of Prism: Part 3"
  "twitter:description": "This post is part of a series about how the prism Ruby parser works."
  "twitter:site": "@kddnewton"
  "twitter:image": https://upload.wikimedia.org/wikipedia/commons/thumb/7/73/Ruby_logo.svg/1200px-Ruby_logo.svg.png
---

This blog series is about how the prism Ruby parser works. If you're new to the series, I recommend starting from [the beginning](/2023/11/30/advent-of-prism-part-0). This post is about reads.

Today, we're going to talk about the nodes that represent syntax that reads data. This includes all kinds of variables and constants, as well as some lesser known special variables. Let's get into it.

## `InstanceVariableReadNode`

Likely the simplest node in this post, `InstanceVariableReadNode` represents the syntax for reading an instance variable. The syntax for this is `@` followed by an underscore or an alphabetical character, followed by any number of underscores or alphanumeric characters. Here are a couple of examples:

```ruby
@foo
@__Foo
@foo_bar
```

There is a slight caveat to "alphabetical" and "alphanumeric" in the above paragraph, which is that these are encoding-dependent. Furthermore, if their leading byte value is non-ASCII (i.e., `>= 0x80`), it can be anything. This means that `@😍` is a perfectly valid instance variable name. Here's what the syntax tree looks like for `@😍`:

<div align="center">
  <img src="/assets/aop/part3-instance-variable-read-node.svg" alt="instance variable read node">
</div>

You'll notice that there is a `name` field on the node that goes beyond our normal location information. This is the first time we've run into a "constant" field, which is one of the 12 types of fields that prism supports on nodes. As such, it's important that we explain it.

### Constant pool

When prism is parsing, it maintains an internal hash table of all of the constant strings it has found so far. This is loosely analogous to the internal ID table that CRuby keeps around to intern strings. By maintaining a constant pool, prism allows its consumers to only have to serialize single these names once, and then reference them by a handle in the future. This is also used internally in prism to resolve local variables because it drastically lowers the number of string comparisons that end up needing to be performed.

The other large benefit comes in the serialization API. Normally when interacting with prism you would either interact with the Ruby API (which wraps the C API via a Ruby native extension) or the C API directly. However, prism also has a serialization API that allows you to serialize a syntax tree into a binary format. That binary format can then be deserialized through a templated deserializer in any language that supports it (we currently do this in `Java` and `JavaScript`). For more information, see the [doc](https://github.com/ruby/prism/blob/5691a6f4041db255568870221823c706f5ad006f/docs/serialization.md) in prism.

At the end of the serialization process, the constant pool is serialized as a list of strings. During serialization, any constant that is being referenced is instead serialized as an offset into the constant pool. This means only one copy of a given string is serialized into the final resulting binary. This is a big win for serialization size, and therefore a big win for performance.

## `ClassVariableReadNode`

Reading a class variable is syntactically almost identical to reading an instance variable. The only difference is it is prefixed with `@@` instead of `@`. Here are a couple of examples:

```ruby
@@foo
@@__Foo
@@foo_bar
```

The same encoding rules apply to class variables as they do to instance variables. Here's what the syntax tree looks like for `@@😍`:

<div align="center">
  <img src="/assets/aop/part3-class-variable-read-node.svg" alt="class variable read node">
</div>

## `GlobalVariableReadNode`

When global variables are read, that syntax is represented by a `GlobalVariableReadNode`. The syntax for global variables is slightly more complex than the previous two because it supports many operators (like `$~`, `$@`, `$!`, etc.) as well as an interesting `$-` prefix convention used to access command-line switches. Here are a couple of examples:

```ruby
$foo
$__Foo
$~
$-v
```

Global variables reads can also show up as an argument to the `alias` keyword. Here's an example:

```ruby
alias $foo $bar
```

We'll go into more detail when we cover that node in a future post. Here's what the syntax tree looks like for `$-v`:

<div align="center">
  <img src="/assets/aop/part3-global-variable-read-node.svg" alt="global variable read node">
</div>

## `BackReferenceReadNode`

When regular expressions are matched against using certain APIs like `=~` or `String#match`, Ruby internally will set some special global variables. These global variables can be used to access various parts of the match. Here are some examples:

```ruby
$&   # last match
$`   # string before last match
$'   # string after last match
$+   # string matches last paren
```

These are called "back references" because they are used to reference parts of the match that have already been matched. Like global variables, they can also show up with the `alias` keyword, as in `alias $foo $&`. Here's what the syntax tree looks like for `$&`:

<div align="center">
  <img src="/assets/aop/part3-back-reference-read-node.svg" alt="back reference read node">
</div>

## `NumberedReferenceReadNode`

Similar to back references, numbered references allow you to access capture groups from a regular expression match. Here's an example:

```ruby
/(foo)(bar)/ =~ "foobar"
$1   # "foo"
$2   # "bar"
```

These nodes hold their location information as well as a `number` field which represents the number of the capture group (1-indexed) from left to right in the regular expression. Here's what the syntax tree looks like for `$1`:

<div align="center">
  <img src="/assets/aop/part3-numbered-reference-read-node.svg" alt="numbered reference read node">
</div>

You'll notice the `number` field is an integer. This is the first time we've encountered the uncommonly used `uint32` field type on a node. It's relatively self-explanatory; it is used to represent an unsigned 32-bit integer.

## `LocalVariableReadNode`

When local variables are read, that syntax is represented by a `LocalVariableReadNode`. Local variables have the same syntactic rules as instance and class variables without a prefix, except that their leading character must be either an underscore or lowercase according to the current encoding. Here are a couple of examples:

```ruby
foo
__Foo
_
```

Local variables must be resolved by the parser _at the time of parsing_. This is due to some ambiguities in the grammar when determining if something is an argument to a method call or not. This means that in order to properly parse Ruby, you must know the local variables that are in scope at any given point in the program. As such, prism provides a `depth` field on local variable reads that indicates how many scopes up the variable is defined.[^1]

Here's what the syntax tree looks like for `foo` (when `foo` has already been defined in the current scope):

<div align="center">
  <img src="/assets/aop/part3-local-variable-read-node.svg" alt="local variable read node">
</div>

## `ConstantReadNode`

When constants are read, that syntax is represented by a `ConstantReadNode`. Note that this is only relative constants that are a part of a larger constant path. For example:

```ruby
Foo
Éoo
```

Effectively, constant reads have the same syntactic rules as local variables, except that their leading character must be uppercase according to the current encoding. Here's what the syntax tree looks like for `Foo`:

<div align="center">
  <img src="/assets/aop/part3-constant-read-node.svg" alt="constant read node">
</div>

## `ConstantPathNode`

Constants can be nested in Ruby according to the module nesting. Accessing those constants can be done through a constant path. Here are a couple of examples:

```ruby
::Foo
Foo::Bar::Baz
::Foo::Bar

self::Foo
foo.bar::Baz
```

The first example includes a prefix of `::`, which indicates that the constant lookup should being at the root of the module nesting tree.

You'll notice that the first three examples only contain constant reads as a part of their path, where the last two include other kinds of expressions. Constant paths can be dynamic in this way, it's not required that they only contain constant reads. To represent these chains of nodes, prism uses a `ConstantPathNode`. These nodes contain an optional `parent` field (`nil` in the first example), a `child` field (almost always a constant read), and the location of the `::` delimiter. Here's what the syntax tree looks like for `Foo::Bar::Baz`:

<div align="center">
  <img src="/assets/aop/part3-constant-path-node.svg" alt="constant path node">
</div>

## Wrapping up

All in, today we covered all 7 nodes that represent syntax that reads data. Here are a couple of things to remember from this post:

* Every kind of variable's syntax is subject to the current encoding.
* Prism uses a constant pool to reduce the number of string comparisons it needs to perform.
* Regular expression matches can implicitly set a _lot_ of global variables, so be sure you actually need the match data (otherwise check out `String#match?`).
* Constants can be accessed through a dynamic path.

In the next post we'll look at corollary to the nodes we looked at today: writes.

---

[^1]: There are — of course — plenty of caveats to this. For more details on this particular field, check the [doc](https://github.com/ruby/prism/blob/5691a6f4041db255568870221823c706f5ad006f/docs/local_variable_depth.md) in prism.
