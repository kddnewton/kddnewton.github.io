---
layout: post
title: Advent of Prism
subtitle: Part 8 - Target writes
meta:
  "twitter:card": summary
  "twitter:title": "Advent of Prism: Part 8"
  "twitter:description": "This post is part of a series about how the prism Ruby parser works."
  "twitter:site": "@kddnewton"
  "twitter:image": https://upload.wikimedia.org/wikipedia/commons/thumb/7/73/Ruby_logo.svg/1200px-Ruby_logo.svg.png
---

This blog series is about how the prism Ruby parser works. If you're new to the series, I recommend starting from [the beginning](/2023/11/30/advent-of-prism-part-0). This post is about target writes.

We have finally reached the last post about writing values to variables. Today we'll talk about an indirect form of writing that prism calls "target" writes. Target writes are used to write to variables with values that do not have a corresponding node in the AST. This is in contrast to, for example, writing using an operator like `=`, `+=`, or `&&=`.

## Target writes

There are five places in the AST that target writes can appear. We'll discuss each of them in turn.

### `for` loops

The iteration variable of the `for` loop is a target write. This means it doesn't have a direct syntactic counterpart for the value that is being assigned. It looks like:

```ruby
for i in 1..10
  puts i
end
```

In this case `i` is a `LocalVariableTargetNode`. It doesn't need to be, though. It could be any of the nodes in this post. For example, you could write to an instance variable in a `for` loop:

```ruby
for @i in 1..10
  puts @i
end
```

This would be an `InstanceVariableTargetNode`. You could also write to multiple values, as in:

```ruby
for i, @i, @@i, $i, I, I::I in 1..10
end
```

... but I wouldn't recommend it.

### `rescue` clauses

The captured error of a `rescue` clause is a target write. It looks like:

```ruby
begin
rescue => e
end
```

In this case the `e` is a `LocalVariableTargetNode`. As with `for` loops, it can be any other target write node as well. This one however cannot be multiple values.

### Multiple assignment

We'll cover multiple assignment in more detail later in this post, but for now here is an example:

```ruby
foo, bar = baz
```

In this case both `foo` and `bar` are target writes represented by `LocalVariableTargetNode` nodes. As with the other examples, they can be any other target write node as well.

### Pattern matching

With pattern matching you can capture variables from the individual patterns using identifiers or the `=>` operator. For example:

```ruby
case foo
in [bar, Integer => baz]
end
```

In this case both `bar` and `baz` are local variable target writes. With pattern matching, however, you are limited to targeting local variables only.

### Regular expression named captures

Regular expressions can have named captures. For example:

```ruby
/(?<foo>bar)/ =~ "bar"
```

These named capture groups either introduce new local variables or write to existing ones. We represent these with local variable target writes. These can only be used to write to local variables.

Now that we've seen where they can appear, let's talk about the actual nodes.

## `InstanceVariableTargetNode`

Instance variables can be targeted. They are represented by the `InstanceVariableTargetNode` node. The AST for `@foo, = 1` looks like:

<div align="center">
  <img src="/assets/aop/part8-instance-variable-target-node.svg" alt="instance variable target node">
</div>

Later in this post we will discuss the `MultiWriteNode` and `ImplicitRestNode` that you see listed above. For now, the important point of this diagram is the `InstanceVariableTargetNode` node. In this case the `@foo, = 1` code is saying "expand out the right-hand side of this `=` operator and spread it over `@foo` and the implicit rest variable". The result is that `@foo` is assigned the value `1`, but you can imagine other scenarios where `@foo` would implicitly receive the first value of the expanded right-hand side.

## `ClassVariableTargetNode`

Class variables can be targeted. They are represented by the `ClassVariableTargetNode` node. The AST for `@@foo, = 1` looks like:

<div align="center">
  <img src="/assets/aop/part8-class-variable-target-node.svg" alt="class variable target node">
</div>

## `GlobalVariableTargetNode`

Global variables can also be targeted. As with other global variable writes, some global variables are read-only and will raise an compile error if you try to write to them. These writes are represented by the `GlobalVariableTargetNode` node. The AST for `$foo, = 1` looks like:

<div align="center">
  <img src="/assets/aop/part8-global-variable-target-node.svg" alt="global variable target node">
</div>

## `LocalVariableTargetNode`

Local variables can be targeted. They are represented by the `LocalVariableTargetNode` node. The AST for `foo, = 1` looks like:

<div align="center">
  <img src="/assets/aop/part8-local-variable-target-node.svg" alt="local variable target node">
</div>

Note that like all other local variable nodes, this also has a depth. As we mentioned above, local variables can also be targeted through pattern matching and regular expression named captures. We'll cover those when we get to those nodes.

## `ConstantTargetNode`

Constants can be targeted. They are represented by the `ConstantTargetNode` node. The AST for `Foo, = 1` looks like:

<div align="center">
  <img src="/assets/aop/part8-constant-target-node.svg" alt="constant target node">
</div>

## `ConstantPathTargetNode`

Constant paths can also be targeted. They are represented by the `ConstantPathTargetNode` node. The AST for `Foo::Bar, = 1` looks like:

<div align="center">
  <img src="/assets/aop/part8-constant-path-target-node.svg" alt="constant path target node">
</div>

Like the other constant path nodes, a `nil` parent represents the use of the top-level constant scope. Constant paths also have some implications for compilation where the constant owner will be pushed onto the scope first, but that's outside the scope of this post.

## `MultiWriteNode`

Finally, we get to the `MultiWriteNode`. This is one of the most complicated pieces of the CRuby compiler. Effectively it means there's a list of targets on the left-hand side of an `=` operator, and some value on the right-hand side. The value on the right-hand side is expanded out and spread over the targets on the left-hand side. For example:

```ruby
foo, bar = baz
@foo, $bar = 1, 2, 3
*, foo = baz
```

These are all what we call multi writes. All of the targets we have talked about today (and a few more that we'll get to in the future) can be on the left-hand side of a multi write. The AST for `foo, *, bar = baz` looks like:

<div align="center">
  <img src="/assets/aop/part8-multi-write-node.svg" alt="multi write node">
</div>

Note that there is a field for `lefts` which indicates a list of nodes that were found before any potential `*` operators, a field for `rest` which is the optional `*`, and `rights` which indicates the nodes that were found after the `*` operator. The `value` field holds the right-hand side of the write.

When these nodes are compiled things get complicated quickly. The compiler needs to visit each target in turn and determine if any context needs to be pushed onto the stack first. Then it pushes the value onto the stack and adds an instruction to spread each element within the value onto the stack (called `expandarray`). Finally, each target is assigned a value from the stack, with `nil` values been pushed if there are not enough.

We named this `MultiWriteNode` because we considered it a "direct" write to multiple targets because there is an explicit value that is being written. This is as opposed to indirectly writing to a set of targets, which we'll see next.

## `MultiTargetNode`

Indirectly writing to a set of targets is represented by the `MultiTargetNode`. This node appears in three places in the AST, which we'll discuss in turn.

### `for` loops

We talked about how `for` loop indices hold target nodes. We've shown examples of this already, but here's another one:

```ruby
for foo, bar in baz
end
```

The iteration variable can automatically be destructured into multiple values. This can get even more complicated if other types of targets are used, like:

```ruby
for $foo, Bar::Baz in qux
end
```

Any of the targets mentioned above can be used in a `for` loop. They imply that the iteration variable should be array-like and that the values should be destructured into the targets. This means that for some collection like `[[1, 2], [3, 4]]` the first iteration would assign `1` to `$foo` and `2` to `Bar::Baz`, and the second iteration would assign `3` to `$foo` and `4` to `Bar::Baz`.

The node that holds these targets is a `MultiTargetNode`. It is effectively a list of targets with optional locations for parentheses. The AST for `for foo, bar in baz do end` looks like:

<div align="center">
  <img src="/assets/aop/part8-multi-target-node.svg" alt="multi target node in for">
</div>

Note that there is a field for `lefts`, `rest`, and `rights` just as with the `MultiWriteNode`.

### Multiple assignment

When a multiple assignment expression is used, generally you will only find a `MultiWriteNode`. However, if you use nested parentheses to further destructure values that are already being destructured, you will find a `MultiTargetNode`. For example:

```ruby
(foo, (bar, baz)) = [1, [2, 3]]
```

Here, we are delving further into the structure of the right-hand side of the `=` operator. We'll have a `MultiWriteNode` that houses the whole assignment, with a `LocalVariableTargetNode` as the first target and a `MultiTargetNode` as the second target. Effectively each nested `MultiTargetNode` represents another level of destructuring. The AST for `foo, (bar, baz) = [1, [2, 3]]` looks like:

<div align="center">
  <img src="/assets/aop/part8-multi-target-node-2.svg" alt="multi target node in masgn">
</div>

### Method declarations

The last place that multi targets can appear is in method declarations. This is not commonly seen, but required positional parameters (i.e., not keyword and not block) can be destructured automatically through the method declaration. For example:

```ruby
def foo((bar, *, baz))
  [bar, baz]
end

p foo([1, 2, 3, 4, 5])
# => [1, 5]
```

These can appear for required positionals before optionals/rest or after. We'll get more into method definitions another time. The AST for `def foo((bar, *, baz)) end` looks like:

<div align="center">
  <img src="/assets/aop/part8-multi-target-node-3.svg" alt="multi target node in def">
</div>

## Naming

Target nodes are quite a departure from existing Ruby parsers. None of the other ASTs that we found have these same kinds of nodes. Usually they're represented as their write equivalents with a missing value. We found that this made it difficult to treat write nodes consistently, because we had to always check if the value was present to determine the kind of node we were dealing with.

The general growth of node types in the prism AST has been difficult to grapple with. Lots of tools want a simplified tree because they don't care about some of the nuanced differences between a target node or a write node. We're definitely sympathetic to this problem (I maintain a formatter that is based on prism, I'm well aware of the difficulties). The issue is, it's a lot easier to join nodes together than it is to split them apart.

Consumers of prism should be aware of these nodes, and if they don't care about the differences between them they can either create unified nodes or alias handler methods to handle both types. On the otherhand, if they were joined together, every tool that cared about the differences would have to re-derive them based on a shared but undocumented understanding of the AST. We felt that the risk was high that this would lead to inconsistent behavior between tools, so we went with the split nodes.

## Wrapping up

Target nodes represent writing indirectly to a variable. They are used in some places you might not expect! There is one more kind of target write that we skipped over today, which are actually method calls. We'll talk about those when we get to the many posts we'll have to have to cover all kinds of method calls. All in, here are a couple of things to remember from today's post:

* Ruby has many ways to indirectly write to a variable.
* Just because you see an expression that looks like a read doesn't mean it is a read.
* Splitting up nodes makes it easier on some consumers but harder on others.

That's it for today. We're finally done with writing to variables! Tomorrow we will take the series in a new direction and talk about strings. See you then!
