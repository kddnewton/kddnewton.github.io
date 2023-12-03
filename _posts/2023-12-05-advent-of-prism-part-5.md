---
layout: post
title: Advent of Prism
subtitle: Part 5 - Operator writes
meta:
  "twitter:card": summary
  "twitter:title": "Advent of Prism: Part 5"
  "twitter:description": "This post is part of a series about how the prism Ruby parser works."
  "twitter:site": "@kddnewton"
  "twitter:image": https://upload.wikimedia.org/wikipedia/commons/thumb/7/73/Ruby_logo.svg/1200px-Ruby_logo.svg.png
---

This blog series is about how the prism Ruby parser works. If you're new to the series, I recommend starting from [the beginning](/2023/11/30/advent-of-prism-part-0). This post is about operator writes.

Continuing our exploration of writing to variables, today's post is about writing to variables using operators other than `=`. We call these nodes operator write nodes, and there is one for each of the 6 types of variables we've already talked about.

## `InstanceVariableOperatorWriteNode`

Instance variables can be indirectly written using other operators, such as `+=` or `*=`. In prism we call these operator writes. Here are some examples in Ruby code:

```ruby
@foo += 1
@foo -= 2
```

All in, there are 11 types of operators that we treat this way: `+=`, `-=`, `*=`, `/=`, `%=`, `**=`, `&=`, `|=`, `^=`, `<<=`, and `>>=`. As with the `=` operator, when one of these operators is encountered immediately following a read node, that read node is converted into its equivalent operator write node. For example, here's what the syntax tree looks like for `@foo += 1`:

<div align="center">
  <img src="/assets/aop/part5-instance-variable-operator-write-node.svg" alt="instance variable operator write node">
</div>

### Syntax sugar

In parsers, sometimes folks refer to these kinds of operators as syntax "sugar". The loose definition is syntax that can be used as a more terse version of other syntax that already exists. As an example, in the compiler the `@foo += 1` peration is almost exactly equivalent to the "desugared" version of:

```ruby
@foo = @foo + 1
```

As such, prism provides a `Prism::DesugarCompiler` that can be used to convert all operator writes that can be safely converted into their equivalent `=` form.

### Design

Other designs were considered for this node. In fact this node was originally implemented as a single operator write node that could be used for all operators and possible left-hand sides. This design was ultimately rejected because it ended up violating one of our key tenets: compilers should not have to look at child nodes to understand the type of node they are compiling. Furthermore, sharing a single operator write node hides some additional complexity, which is that not all of the operator writes can be desugared as we have with the instance variables. We'll see why moementarily.

## `ClassVariableOperatorWriteNode`

Class variables can be indirectly written with the same operators as instance variables. Here are some examples in Ruby code:

```ruby
@@foo += 1
@@foo -= 2
```

Here is what the syntax tree looks like for `@@foo += 1`:

<div align="center">
  <img src="/assets/aop/part5-class-variable-operator-write-node.svg" alt="class variable operator write node">
</div>

As with instance variables, prism provides a `Prism::DesugarCompiler` that can be used to convert all operator writes that can be safely converted into their equivalent `=` form.

### Operators

You'll notice that in addition to the `name` constant field that both of these nodes have, they also have an `operator` constant field. This field is used to store the operator that was used to write to the variable. It ends up being the name of the method that gets called on the value stored in the variable. For example, in addition to `@foo += 1` being effectively equivalent to `@foo = @foo + 1`, it is also effectively equivalent to `@foo = @foo.+(1)`.

As we discussed when we introduced the concept of "constants" in prism, we only want consumers of prism to have to intern strings once. Therefore to provide the name of the method more readily and to save some work for consumers, we store the name of the method in the constant pool.

## `GlobalVariableOperatorWriteNode`

Global variables can be indirectly written with the same operators. Here are some examples in Ruby code:

```ruby
$foo += 1
$foo -= 2
```

Note that same things that look like global variables are not allowed to be written at all, such as `$&`. With direct or indirect writes like operator writes, you will get the `Can't set variable` compile error in CRuby, or an equivalent parse error in prism. Here is what the syntax tree looks like for `$foo += 1`:

<div align="center">
  <img src="/assets/aop/part5-global-variable-operator-write-node.svg" alt="global variable operator write node">
</div>

### Naming

You may have noticed that a lot of the class names in this particular post are quite long. In fact, they are the longest names of any of the nodes in prism. I received some pushback when I initially proposed these names, likely because they appear more at home in the Java ecosystem than the Ruby one. Let me give you a brief justification, and you can decide for yourself whether you agree.

When we were first designing/proposing prism, we scoured the documentation and code for all of the Ruby syntax trees we could get our hands on. Our goal was to take the best of every possible tool we could and put it into one. This included the various Ruby runtimes and their parsers, the static analysis tools, and other tools like the `Ripper` standard library. Almost all of them call `@foo += 1` things like `iasgn`, `ivasgn`, `opassign`, etc.

The issue with these names is the same issue I have with acronyms. It's not that they're bad, wrong, or incorrect. Once you learn them, they make perfect sense. It's the barrier to entry. We want prism to be able to be used and contributed to by as large of a community as possible. This has to be considered in _every aspect_ of the project — including documentation, tests, and especially naming. While these names are indeed, quite verbose, they are also explicitly clear. I would much rather stray too far in that direction than the opposite.

## `LocalVariableOperatorWriteNode`

Local variables can be indirectly written as well. Here are some examples in Ruby code:

```ruby
foo = 0
foo += 1
tap { foo -= 2 }
```

Note that like all other local variable writes, `depth` must be calculated at parse time. All of the operators that we're looking at today will immediately add the local variable to the current scope if it does not already exist, but its value will implicitly be `nil`. This is why if you see `foo += 1` but `foo` hasn't yet been declared, you'll get a `NoMethodError` on `NilClass` for `+`. This leads to some particularly cursed behavior if you monkey-patch operator methods onto `NilClass`. I'm horrified enough by the idea that I won't even show you an example of that here.

Here is what the syntax tree looks like for `foo += 1`:

<div align="center">
  <img src="/assets/aop/part5-local-variable-operator-write-node.svg" alt="local variable operator write node">
</div>

## `ConstantOperatorWriteNode`

Writing to relative constants using operators is represented using the `ConstantOperatorWriteNode` node. Here are some examples in Ruby code:

```ruby
Foo += 1
Foo -= 2
```

Note that doing this operator is permitted, but will always issue a warning because you are redefining a constant. Here is what the syntax tree looks like for `Foo += 1`:

<div align="center">
  <img src="/assets/aop/part5-constant-operator-write-node.svg" alt="constant operator write node">
</div>

## `ConstantPathOperatorWriteNode`

Finally, writing to constant paths using operators is represented using the `ConstantPathOperatorWriteNode` node. Here are some examples in Ruby code:

```ruby
::Foo += 1
Foo::Bar::Baz -= 1
::Foo::Bar *= 1
self::Foo /= 1
foo.bar::Baz %= 1
```

I would be remiss if I didn't mention: please don't do this. There is going to be so much syntax in this series that I'm going to show you that you should really never write in your code. This is the first of those examples. Using any of these operators in this way will always give you a warning anyway, but it's still worth mentioning. Here is what the syntax tree looks like for `self::Foo += 1`:

<div align="center">
  <img src="/assets/aop/part5-constant-path-operator-write-node.svg" alt="constant path operator write node">
</div>

This is the exception to the ability to desugar operator writes. While it may seem like `Foo::Bar += 1` is the same as `Foo::Bar = Foo::Bar + 1`, there are some incredibly minute differences. When Ruby sees a constant path operator write, it caches the lookup of the constant context (in this example, this means the lookup of `Foo`). That means that if anything were to change the lookup of `Foo` (for example, through `const_missing`), it would not be reflected in the operator write case. Desugaring `Foo::Bar += 1` is more similar to something like:

```ruby
tmp = Foo
tmp::Bar = tmp::Bar + 1
```

where `tmp` is an internally stored variable. It's actually not possible to replicate the behavior of `Foo::Bar += 1` in normal Ruby code, which is both why we don't desugar it with `Prism::DesugarCompiler` and also why we justify the existence of every node in this post.

## Wrapping up

Today we covered the 6 types of operator writes in Ruby that write indirectly to variables.[^1] Here are some key takeaways:

* It's worth reiterating that nodes that are already parsed by the parser can change type depending on additional context like the operators mentioned in today's post. This is especially important for tools that might do incremental parsing like a REPL or an IDE.
* The `Prism::DesugarCompiler` can be used to convert all operator writes that can be safely converted into their equivalent `=` form.
* The `operator` constant field is used to store the operator that was used to write to the variable. It ends up being the name of the method that gets called on the value stored in the variable.

In the next post we will continue our exploration of writing to variables with the most complex form: control-flow writes.

---

[^1]: You may have noticed the number of qualifiers in this sentence. There are both more ways to use these operators, and many more ways to write indirectly to variables. Rest assured, we have much more ground to cover.
