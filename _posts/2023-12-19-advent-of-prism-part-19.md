---
layout: post
title: Advent of Prism
subtitle: Part 19 - Blocks
meta:
  "twitter:card": summary
  "twitter:title": "Advent of Prism: Part 19"
  "twitter:description": "This post is part of a series about how the prism Ruby parser works."
  "twitter:site": "@kddnewton"
  "twitter:image": https://upload.wikimedia.org/wikipedia/commons/thumb/7/73/Ruby_logo.svg/1200px-Ruby_logo.svg.png
---

This blog series is about how the prism Ruby parser works. If you're new to the series, I recommend starting from [the beginning](/2023/11/30/advent-of-prism-part-0). This post is about blocks and lambdas.

At long last, we have reached the point of talking about blocks and lambdas. These are major pieces of Ruby functionality that we have been deftly avoiding until now. Today, we'll take a look.

## `BlockNode`

Blocks in Ruby code are represented by braces or the `do` and `end` keywords. They can also optionally declare parameters. They then accept a set of statements that are saved and then executed later when the block is called (either through the `yield` keyword or by transforming it into a `Proc` and then calling `#call`). Here's an example:

```ruby
foo do
  1
end
```

This code is represented by the following AST:

<div align="center">
  <img src="/assets/aop/part19-block-node.svg" alt="block node">
</div>

As you can see from the diagram, blocks hold a pointer to their body as well as their local table. The `body` field can either be a `StatementsNode` (as we see in this example) or a `BeginNode` (like we saw with methods, classes, modules, and singleton classes). That would look like:

```ruby
foo do
  1
rescue
end
```

which is represented by the following AST:

<div align="center">
  <img src="/assets/aop/part19-block-node-2.svg" alt="block node">
</div>

`rescue` and its corresponding `else` and `ensure` clauses can only be used when the keywords are being used as the bounds of the block, and not braces.

It's also worth noting that semantically, there is no difference between the bounds of the block. Once they are parsed, they are exactly the same. However, in the parser they have different precedence. Braces are bound much more tightly than `do` and `end`. For example:

```ruby
foo bar {} # send the block to `bar`
foo bar do end # send the block to `foo`
```

It's not necessarily important for you to remember the specifics of how these are bound as much as it is to remember that they cannot be immediately substituted.

## `BlockParametersNode`

When blocks (or lambdas) declare parameters they are wrapped in a `BlockParametersNode`. These nodes are effectively a wrapper around a list of parameters. For example:

```ruby
foo { |bar| }
```

This is represented by the following AST:

<div align="center">
  <img src="/assets/aop/part19-block-parameters-node.svg" alt="block parameters node">
</div>

There are two differences from regular parameters nodes. The first is that they hold an inner location to their bounds (`||` for blocks, `()` for lambdas). The second is that they hold a list of block locals. We'll talk about these next.

## `BlockLocalVariableNode`

In both blocks and lambdas, you can declare local variables that are only visible within the scope of the block or lambda. These declarations go right next to the declaration of the parameters themselves. For example:

```ruby
foo { |; bar| }
```

The `bar` variable is then only visible within the block. This is semantically similar to:

```ruby
foo do
  bar = nil
end
```

The main difference is that if `bar` is declared in an outer scope the block local will not overwrite it, while assigning `nil` to it will. These locals are represented by `BlockLocalVariableNode` nodes and go into the `locals` field on `BlockParametersNode`. The first example is represented by the following AST:

<div align="center">
  <img src="/assets/aop/part19-block-local-variable-node.svg" alt="block local variable node">
</div>

The actual syntax for these is that they are a semicolon-separated list of identifiers that follow a semicolon within the parameter list.

## `LambdaNode`

Lambda literals are represented by the `LambdaNode` node. They look similar to blocks and function in much the same way — both function as closures around a set of parameters and a body. Here is an example:

```ruby
-> (foo) { foo * 2 }
```

The syntax for a lambda literal begins with the `->` token. It is then optionally followed by a parameter list. The parameter list can be optionally wrapped in parentheses. The parentheses are required if certain types of parameter types are used. This is followed by a body that is either wrapped in braces or the `do` and `end` keywords.

The example above is represented by the following AST:

<div align="center">
  <img src="/assets/aop/part19-lambda-node.svg" alt="lambda node">
</div>

Believe it or not, we've seen every node in this AST before except for the `LambdaNode` itself. On that node we have lots of internal locations, a pointer to a local table, a set of parameters, and a body. Much like blocks the body can be either a `StatementsNode` or a `BeginNode`.

Like blocks, lambdas can also declare block locals. These are represented by the same `BlockLocalVariableNode` nodes that we saw above. This looks like:

```ruby
-> (; foo) {}
```

It's important to note that these are lambda literals only and not calls to the `Kernel#lambda` method. Those are represented by `CallNode` nodes like all other method calls because they can be overridden depending on context. 

## `NumberedParametersNode`

The last piece of syntax we're going to talk about today is numbered parameters. This is a special syntax that allows referencing positional parameters without explicitly declaring them. For example:

```ruby
-> { _1 * 2 }
```

The syntax for numbered parameters is an underscore followed by a digit. The digit is the position of the parameter that you want to reference (1-indexed).

Numbered parameters are mutually exclusive with regular parameters. If you declare both in the same context, you'll get a syntax error. You also cannot use them in nested contexts without a syntax error (e.g., `-> { -> { _1 } }`). Because of this mutual exclusivity we can be assured that the `parameters` field on `BlockNode` and `LambdaNode` will be `nil` when numbered parameters are used. We take advantage of that fact to provide some extra information for prism consumers. Here's the AST for the above example:

<div align="center">
  <img src="/assets/aop/part19-numbered-parameters-node.svg" alt="numbered parameters node">
</div>

As you can see, when numbered parameters are in use we use a `NumberedParametersNode` node to represent them. This node holds an integer that represents the number of parameters that are being referenced. Compilers can use this to set up the correct number of parameters for the block or lambda.

As a brief aside, Matz [recently accepted](https://bugs.ruby-lang.org/issues/18980) a proposal for `it` to be another reference to `_1`. It's controversial to say the least.

## Wrapping up

Blocks and lambdas play a foundational role in Ruby. They are used to execute a set of statements over a closure at a prescribed time. Knowing their syntax and semantics will allow you to take full advantage of them. Here are a couple of things to remember from today:

* Blocks and lambdas can have local variables declared that are only visible within the block or lambda.
* Numbered parameters are a special syntax that allows referencing positional parameters without explicitly declaring them.

That's all for today. Tomorrow we'll be looking at two interesting keywords: `alias` and `undef`.
