---
layout: post
title: Advent of Prism
subtitle: Part 12 - Program structure
meta:
  "twitter:card": summary
  "twitter:title": "Advent of Prism: Part 12"
  "twitter:description": "This post is part of a series about how the prism Ruby parser works."
  "twitter:site": "@kddnewton"
  "twitter:image": https://upload.wikimedia.org/wikipedia/commons/thumb/7/73/Ruby_logo.svg/1200px-Ruby_logo.svg.png
---

This blog series is about how the prism Ruby parser works. If you're new to the series, I recommend starting from [the beginning](/2023/11/30/advent-of-prism-part-0). This post is about program structure.

Today is a mixed-bag of a post, incorporating nodes that have to do with overall program structure. We'll look at two nodes that do not correspond to any syntax at all and are exclusively used for structure. We'll look at a node that does nothing, and some would argue should be removed. Finally we'll look at two nodes that are used most commonly when Ruby is being used as a shell script. Let's get going.

## `ProgramNode`

The top-level node of any parse result is going to be a `ProgramNode`. This node is actually a bit of a deviation from other Ruby ASTs out there. `whitequark/parser` and `seattlerb/ruby_parser` will both return a single expression if that's all that is being parsed. If multiple expressions are being parsed, `whitequark/parser` will wrap everything in a `begin` node and `seattlerb/ruby_parser` will wrap everything in a `block` node, which are effectively the same thing.

We decided to have a consistent top-level node because it makes it easier to delineate when the processing of the AST is done. Whether you're compiling, interpreting, linting, or something else, when you return back to the top of the tree after walking it it's helpful to have a single hook you know will be at the top. For example, let's say you're using prism's `Prism::Visitor` class to walk a tree and find regular expressions for handling later. You could do that with:

```ruby
require "prism"

class RegularExpressionVisitor < Prism::Visitor
  attr_reader :regular_expressions

  def initialize
    @regular_expressions = []
  end

  def visit_regular_expression_node(node)
    regular_expressions << node
  end
end

result = Prism.parse(ARGF.read)
visitor = RegularExpressionVisitor.new

result.value.accept(visitor)
visitor.regular_expressions # => [...]
```

This code will find all of the regular expressions in your tree. However, for a slightly more convenient syntax, we can also hook into the program node since it is guaranteed to be at the top of the tree. For example:

```ruby
require "prism"

class RegularExpressionVisitor < Prism::Visitor
  attr_reader :regular_expressions

  def initialize
    @regular_expressions = []
  end

  def visit_regular_expression_node(node)
    regular_expressions << node
  end

  def visit_program_node(node)
    super
    regular_expressions
  end
end

result = Prism.parse(ARGF.read)
result.value.accept(RegularExpressionVisitor.new) # => [...]
```

It's a small change, but it pays for itself in small ways like this all of the time.

## `StatementsNode`

Many nodes in the prism AST contain lists of statements. This includes things like classes, modules, if statements, etc. These lists of statements could easily be arrays of nodes on the parent nodes themselves. For example, let's look at a quick if statement:

```ruby
if foo
  bar
  baz
end
```

In our current AST that would look like:

<div align="center">
  <img src="/assets/aop/part12-statements-node.svg" alt="statements node">
</div>

There's nothing stopping us from pushing the `body` field directly into the `IfNode`. The indirection is a tradeoff we have decided to make for a couple of reasons.

First, there is a cost associated with storing an empty list in a language like C if you want the list to be embedded directly into the node (which we do for locality reasons). Therefore it's actually less costly to allocate a `StatementsNode` when you need it than to keep around an empty list when you don't. Second, having a single `StatementsNode` allows consumers to process lists of statements consistently, which has some nice side-effects if you consider processing comments at the same time, or the fact that only the last node within a `StatementsNode` will be returned to the parent context. Finally, it just makes the code cleaner.

Note that both `ProgramNode` and `StatementsNode` do not correspond to any real syntax in source. These are two of the three nodes in our entire tree that have this status. We feel, however, that their inclusion is justified for the reasons listed above.

## `ParenthesesNode`

When you use parentheses in your Ruby code, you're performing expression grouping manually. Sometimes this is necessary to control the operator precedence. Sometimes it's unnecessary for Ruby, but nice to signal to fellow programmers what is being performed.

Normally, parentheses can be dropped entirely in the resulting parse tree. This is always the case when the parentheses wrap a single expression. Parentheses can be more powerful than you might realize, however, and can wrap as many statements as you want. Either way, we have chosen to keep them in the resulting tree to allow consumers to consistently compile them and for tooling to always know where the user explicitly placed them.

First, let's look at an example of parentheses wrapping a single expression:

```ruby
if (foo)
  baz
end
```

Semantically this would be the same as if the parentheses we not present. Here is the AST for this code:

<div align="center">
  <img src="/assets/aop/part12-parentheses-node-1.svg" alt="parentheses node">
</div>

You'll notice we have a statements node inside the parentheses. Here's why:

```ruby
if (foo; bar)
  baz
end
```

This code will execute the `foo` method call first, then execute the `bar` method call and use that as the predicate for the `if` statement. (This is not dissimilar to the `,` operator in C.) Here is the AST for the above code:

<div align="center">
  <img src="/assets/aop/part12-parentheses-node-2.svg" alt="parentheses node">
</div>

All of the other Ruby parsers that we found dropped the parentheses entirely in the first case and created some kind of block/scope/list node in the second case. We chose to keep it consistent in both cases.

## `PreExecutionNode`

To this day, Ruby has many tools that can be used to allow efficient processing at the command line. One of these is the `BEGIN {}` block, which executes code when the virtual machine first starts up, regardless of its place in the source code. For example:

```ruby
foo = 1
BEGIN { foo = 2 }
foo # => 1
```

The `BEGIN {}` block is compiled as if it were the first expression in the file. In the case of multiple of these kinds of blocks, they execute in the order in which they appeared.

These nodes are particular interesting because it's one of the only places that requires two distinct tokens in immediate succession. The `BEGIN` keyword must always be followed by the `{` token, no exceptions (these blocks do not accept `do`/`end`). The body of the block follows, and then must be terminated by a matching `}` token.

These nodes can only be used as a top-level statement. Once you are inside another scope, you will get a syntax error. Presumably this is because it makes it nearly impossible to reason about when the code will be executed. The AST for `BEGIN { 1 }` looks like:

<div align="center">
  <img src="/assets/aop/part12-pre-execution-node.svg" alt="pre execution node">
</div>

## `PostExecutionNode`

In the same vein, the `END {}` block allows executing code when the virtual machine is done. The main difference with `BEGIN {}` is that it can be used anywhere in the tree (however it will warn if it's inside of methods). Here's an example:

```ruby
END { puts "goodbye!" }
```

Much like `BEGIN {}`, the `END` keyword token must be immediately followed by a `{` token. After the statements in the body of the block, it is closed by a matched `}` token. Here is the AST for `END { 1 }`:

<div align="center">
  <img src="/assets/aop/part12-post-execution-node.svg" alt="post execution node">
</div>

## Wrapping up

Today we talked about some nodes used for structuring the tree, as well as some expressions used to structure Ruby programs. Here are some take-aways from today:

* Some nodes in the tree exist to form a consistent and easy-to-use interface, but do not necessarily correspond to Ruby syntax.
* Parentheses can how more than a single statement (in _most_ cases).
* Ruby still has many tools to allow it to be used on the command line, including `BEGIN {}` and `END {}`.

Tomorrow we will finally get into the heart of Ruby code: method calls. See you then.
