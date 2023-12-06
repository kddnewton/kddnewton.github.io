---
layout: post
title: Advent of Prism
subtitle: Part 6 - Control-flow writes
meta:
  "twitter:card": summary
  "twitter:title": "Advent of Prism: Part 6"
  "twitter:description": "This post is part of a series about how the prism Ruby parser works."
  "twitter:site": "@kddnewton"
  "twitter:image": https://upload.wikimedia.org/wikipedia/commons/thumb/7/73/Ruby_logo.svg/1200px-Ruby_logo.svg.png
---

This blog series is about how the prism Ruby parser works. If you're new to the series, I recommend starting from [the beginning](/2023/11/30/advent-of-prism-part-0). This post is about control-flow writes.

Soldiering on with our dive into writing to variables, we finally arrive at the most complex form: control-flow writes. Control-flow writes involve the use of the `&&=` and `||=` operators. But before we dive into that, let's define control-flow.

## Control-flow

Control-flow refers to the order in which statements are executed by a program. For example, if you have `foo = 1; foo = 2`, you can safely say that the value of `foo` at the end of the program is `2` because statements in Ruby are executed in order. If you have something more complex like:

```ruby
foo = 1

if bar
  foo = 2
else
  foo = 3
end
```

you know that the value of `foo` is either `2` or `3`, depending on the result of the `bar` method call. The control-flow in this case is said to "branch" because the program can take one of two paths. If `bar` returns a truthy value, the program will execute the `foo = 2` branch. If `bar` returns a falsy value, the program will execute the `foo = 3` branch. We'll see how this relates to the `&&=` and `||=` operators in a moment.

## Instance variables

### `InstanceVariableAndWriteNode`

Instance variables can be indirectly written using the `&&=` operator. Here is an example in Ruby code:

```ruby
@foo &&= 1
```

This is effectively equivalent to:

```ruby
@foo && @foo = 1
```

Notice that this is quite a bit different from the operators we looked at in the last post. This can be a very large source of confusion. For operators like `+=`, they instead break down to `@foo = @foo + 1`, where the assignment happens regardless of the result of the operation. This is not the case with control-flow write operators. With `&&=`, the write only happens in the case that the instance variable is truthy. Put another way, the code above is _almost_ exactly equivalent to:

```ruby
if @foo
  @foo = 1
else
  @foo
end
```

Here is what the syntax tree looks like for `@foo &&= 1`:

<div align="center">
  <img src="/assets/aop/part6-instance-variable-and-write-node.svg" alt="instance variable and write node">
</div>

Notice that the good side of splitting all of the writes up into their own nodes plays in our favor in this case. `InstanceVariableAndWriteNode` is a very compact representation of the syntax tree for `@foo &&= 1`. Most other Ruby syntax trees represent this as at least 3 nodes: a node for the target instance variable, a node for the expression being written, and a third node joining the two named something like `opassign`. This requires consumers to find the `opassign` node, then look at the target to understand how to process it. Prism instead goes the route of providing that information in the type itself to save consumers some processing time.

## `InstanceVariableOrWriteNode`

Instance variables can also be indirectly written using the `||=` operator. Here is an example in Ruby code:

```ruby
@foo ||= 1
```

This is effectively equivalent to:

```ruby
@foo || @foo = 1
```

This is the opposite of the `&&=` operator in that the write only happens in the case that the instance variable is falsy. Put another way, the code above is almost exactly equivalent to:

```ruby
if !@foo
  @foo = 1
else
  @foo
end
```

Here is what the syntax tree looks like for `@foo ||= 1`:

<div align="center">
  <img src="/assets/aop/part6-instance-variable-or-write-node.svg" alt="instance variable or write node">
</div>

## Class variables

### `ClassVariableAndWriteNode`

Class variables can be indirectly written using the `&&=` operator, like so:

```ruby
@@foo &&= 1
```

This follows the same logical pattern as instance variables. Here is what the syntax tree looks like for `@@foo &&= 1`:

<div align="center">
  <img src="/assets/aop/part6-class-variable-and-write-node.svg" alt="class variable and write node">
</div>

### `ClassVariableOrWriteNode`

Class variables can also be indirectly written using the `||=` operator, like so:

```ruby
@@foo ||= 1
```

Again, this follows the same logical pattern as instance variables. Here is what the syntax tree looks like for `@@foo ||= 1`:

<div align="center">
  <img src="/assets/aop/part6-class-variable-or-write-node.svg" alt="class variable or write node">
</div>

## Global variables

### `GlobalVariableAndWriteNode`

Global variables can be indirectly written using the `&&=` operator, like so:

```ruby
$foo &&= 1
```

This follows the same control-flow that we've already discussed. As with other global variable writes, some global variables are not allowed to be written, and you will encounter a compile error if you try to write to them indirectly using these operators. Here is what the syntax tree looks like for `$foo &&= 1`:

<div align="center">
  <img src="/assets/aop/part6-global-variable-and-write-node.svg" alt="global variable and write node">
</div>

### `GlobalVariableOrWriteNode`

Global variables can also be indirectly written using the `||=` operator, like so:

```ruby
$foo ||= 1
```

Again, this follows the same control-flow that we've already discussed. Here is what the syntax tree looks like for `$foo ||= 1`:

<div align="center">
  <img src="/assets/aop/part6-global-variable-or-write-node.svg" alt="global variable or write node">
</div>

## Local variables

As with other local variable writes, the `&&=` and `||=` operators can either modify existing local variables or declare new ones. If they haven't yet been declared, local variables take on the value of `nil`, which has implications for the control flow of both of these operators since `nil` is falsy.

### `LocalVariableAndWriteNode`

Here is an example of writing to a local variable using the `&&=` operator:

```ruby
foo &&= 1
```

Note that if `foo` hasn't yet been introduced to the scope, then this will create a local variable named `foo` but do nothing since it will have the value of `nil`. You can verify it has been introduced with the `Kernel#local_variables` method, as in:

```ruby
foo &&= 1
local_variables # => [:foo]
```

As with other local variable writes, these nodes also contain the depth of the local variable in terms of the number of scopes above the current scope where the local was declared. Here is what the syntax tree looks like for `foo &&= 1` when `foo` has already been declared in the current scope:

<div align="center">
  <img src="/assets/aop/part6-local-variable-and-write-node.svg" alt="local variable and write node">
</div>

### `LocalVariableOrWriteNode`

Local variables can also be indirectly written using the `||=` operator, like so:

```ruby
foo ||= 1
```

Again, this follows the same control-flow that we've already discussed. If `foo` has not already been declared, then this will create a local variable named `foo` and assign it the value of `1` because `foo` initially takes on the value of `nil`. Here is what the syntax tree looks like for `foo ||= 1` when `foo` has already been declared in the current scope:

<div align="center">
  <img src="/assets/aop/part6-local-variable-or-write-node.svg" alt="local variable or write node">
</div>

## Constants

### `ConstantAndWriteNode`

Constants can be indirectly written using the `&&=` operator, like so:

```ruby
Foo &&= 1
```

Interesting, because this effectively breaks down to `Foo && Foo = 1`, this will trigger a `NameError` if the constant does not already exist. Therefore this must be used on a constant that has already been written. As a result, every time syntax like this is used a warning will be triggered about a constant redefinition. (This is another example of code that should very likely never be written, even though it is allowed. It is also an example of why the name "constant" is quite a misnomer.)

Here is what the syntax tree looks like for `Foo &&= 1`:

<div align="center">
  <img src="/assets/aop/part6-constant-and-write-node.svg" alt="constant and write node">
</div>

### `ConstantOrWriteNode`

Constants can also be indirectly written using the `||=` operator, like so:

```ruby
Foo ||= 1
```

The pairing of the `&&=` and `||=` write nodes for constants end up differing quite a bit here, because there is a special path through the compiler for `||=` that makes them not equivalent to `Foo || Foo = 1`. Instead, they're much more similar to:

```ruby
if defined?(Foo)
  Foo
else
  Foo = 1
end
```

The `||=` operator therefore means something quite different from you might expect in this context.[^1] Here is what the syntax tree looks like for `Foo ||= 1`:

<div align="center">
  <img src="/assets/aop/part6-constant-or-write-node.svg" alt="constant or write node">
</div>

## Constant paths

As with operator writes on constant paths, the owner of the constant gets cached when these expressions are compiled. This makes these expressions deceptively complex.

### `ConstantPathAndWriteNode`

Constant paths can be indirectly written using the `&&=` operator, like so:

```ruby
Foo::Bar &&= 1
```

There's no way to break down this expression in pure Ruby, but it effectively amounts to something like:

```ruby
tmp = Foo

if tmp::Bar
  tmp::Bar = 1
else
  tmp::Bar
end
```

Here is what the syntax tree looks like for `Foo::Bar &&= 1`:

<div align="center">
  <img src="/assets/aop/part6-constant-path-and-write-node.svg" alt="constant path and write node">
</div>

### `ConstantPathOrWriteNode`

Constant paths can also be indirectly written using the `||=` operator, like so:

```ruby
Foo::Bar ||= 1
```

Here we have two things to consider: the owner of the `Bar` constant is cached _and_ there is a special path through the compiler for `||=` that makes them not equivalent to `Foo::Bar || Foo::Bar = 1`. Instead, this is more akin to:

```ruby
tmp = Foo

if defined?(tmp::Bar)
  tmp::Bar
else
  tmp::Bar = 1
end
```

This is quite a nuanced piece of code, and as such we feel most comfortable calling it out as its own node as opposed to combining it with some other operator/control-flow writes. The reality is there is a lot that is unique about this particular expression.

Here is what the syntax tree looks like for `Foo::Bar ||= 1`:

<div align="center">
  <img src="/assets/aop/part6-constant-path-or-write-node.svg" alt="constant path or write node">
</div>

## Wrapping up

Today we covered the 12 types of control-flow writes in Ruby that write indirectly to variables. Here are some key takeaways:

* Control-flow writes usually break down to a conditional check _before_ the value is written.
* The `||=` operator has significantly different semantics depending on the target it is writing to.
* Writing to constants with control flow is very nuanced.

After three days of looking at writing to variables, tomorrow we will take a quick break to dive further into the land of control flow.

---

[^1]: It actually does the same kind of `defined?` check for class and global variables as well. It _used_ to do it for instance variables too, but this was because uninitialized instance variables used to issue a warning. The check was removed in more recent versions of Ruby, which had the nice benefit of making instance variable `||=` writes a lot faster. Because this is a pretty common pattern for memoization, that was a big win for the ecosystem.
