---
layout: post
title: Advent of Prism
subtitle: Part 14 - Calls (part 2)
meta:
  "twitter:card": summary
  "twitter:title": "Advent of Prism: Part 14"
  "twitter:description": "This post is part of a series about how the prism Ruby parser works."
  "twitter:site": "@kddnewton"
  "twitter:image": https://upload.wikimedia.org/wikipedia/commons/thumb/7/73/Ruby_logo.svg/1200px-Ruby_logo.svg.png
---

This blog series is about how the prism Ruby parser works. If you're new to the series, I recommend starting from [the beginning](/2023/11/30/advent-of-prism-part-0). This post is about call nodes.

Yesterday we looked at the general form of call nodes. Today we'll look at some of the more complex ones, as well as the `super` keyword. Let's get started.

## Call operator writes

Way back in [Part 5 - Operator writes](/2023/12/05/advent-of-prism-part-5), we saw how you can use operator writes as a more terse way of writing to a variable through a method call. This works when the left-hand side of the operator is itself a method call as well. Let's take a look.

### `CallOperatorWriteNode`

When a method call is on the left-hand side of an operator write token, we create a `CallOperatorWriteNode`. We split this node up because it actually implies two method calls instead of one! We wanted consumers to have to explicitly handle this split because you could easily accidentally miss that another method was being called. Here's an example:

```ruby
foo.bar += 1
```

Semantically, this is _almost_ equivalent to:

```ruby
tmp = foo
tmp.bar=(tmp.bar.+(1))
```

Ruby will cache the owner of the `bar` and `bar=` methods so that that code will only be run once. As you can see, both `bar` and `bar=` are being called on the same object (in this case the `receiver` field of the `CallOperatorWriteNode`). Here is what the AST looks like for `foo.bar += 1`:

<div align="center">
  <img src="/assets/aop/part14-call-operator-write-node.svg" alt="call operator write node">
</div>

That's a lot of fields! In fact, these nodes have more fields than almost any other in the tree (excepting method definitions). Let's go through them one by one.

* `flags` - these are the same flags as the `CallNode` flags
* `receiver` - the receiver of the call
* `call_operator_loc` - the location of the `.`
* `message_loc` - the location of `bar`
* `read_name` - the name of the method being called to read the value (`bar`)
* `write_name` - the name of the method being called to write the value (`bar=`)
* `operator` - the operator being used (`+`)
* `operator_loc` - the location of the `+=`
* `value` - the value being passed to the `bar=` method (`1`)

### `IndexOperatorWriteNode`

Similar to `CallOperatorWriteNode`, we also have an `IndexOperatorWriteNode` for when the called method is using the `[]` syntax. Here's an example:

```ruby
foo[:bar] += 1
```

Semantically, this is _almost_ equivalent to:

```ruby
tmp = foo
tmp.[]=(tmp.[](:bar).+(1))
```

Here is what the AST looks like for `foo[:bar] += 1`:

<div align="center">
  <img src="/assets/aop/part14-index-operator-write-node.svg" alt="index operator write node">
</div>

The fields are largely the same, with the addition of locations for the brackets and an arguments node for whatever is inside the brackets. We also have the potential of a block on these nodes being passed with the `&` operator within the brackets, as in:

```ruby
foo[&bar] += 1
```

The AST for that looks like:

<div align="center">
  <img src="/assets/aop/part14-index-operator-write-node-2.svg" alt="index operator write node">
</div>

Finally, it's possible to omit arguments entirely because the `[]` method is not required to have any specific number of arguments. That would look like:

```ruby
foo[] += 1
```

The AST for that looks like:

<div align="center">
  <img src="/assets/aop/part14-index-operator-write-node-3.svg" alt="index operator write node">
</div>

Note that `IndexOperatorWriteNode` does not have `read_name` or `write_name` fields because it is constant; they are always `[]` and `[]=`, respectively.

## `super` keyword

The `super` keyword in Ruby allows you to call a method that matches the name of the current method on a module higher in the ancestor chain. For example, if you have a class `Foo` that inherits from `Bar`, and both have a method `baz`, you can call `super` from `Foo#baz` to call `Bar#baz`.

### `ForwardingSuperNode`

When `super` is used without any explicit arguments or parentheses (with or without a block), it will "forward" all of the arguments to the current method to the parent method. For example:

```ruby
class Parent
  def test(value) = value * 2
end

class Child < Parent
  def test(value) = super
end

Child.new.test(2) # => 4
```

This can get somewhat complex if you modify the values before they are passed, but it is allowed. For example:

```ruby
class Parent
  def test(value) = value * 2
end

class Child < Parent
  def test(value)
    value *= 2
    super
  end
end

Child.new.test(2) # => 8
```

You can also pass a block to `super` like this and it will still forward arguments, as in:

```ruby
class Parent
  def test(value) = yield value
end

class Child < Parent
  def test(value) = super { |v| v * 2 }
end

Child.new.test(2) # => 4
```

We represent this syntax with a `ForwardingSuperNode`. Here's what the AST looks like for `super {}`:

<div align="center">
  <img src="/assets/aop/part14-forwarding-super-node.svg" alt="forwarding super node">
</div>

You'll notice the only field holds a reference to the optional block node.

### `SuperNode`

When parentheses or explicit arguments are used with `super`, we create a `SuperNode`. Here's an example:

```ruby
class Parent
  def test(value) = value * 2
end

class Child < Parent
  def test(value) = super(value * 2)
end

Child.new.test(2) # => 8
```

The AST for `super(value)` looks like:

<div align="center">
  <img src="/assets/aop/part14-super-node.svg" alt="super node">
</div>

Note that `SuperNode` can also have a block in the same way as `ForwardingSuperNode`.

## Call targeting

Back in [Part 8 - Target writes](/2023/12/08/advent-of-prism-part-8) we showed how you could implicitly write to a variable through various syntax that determined the value at runtime. You can do the same thing with method calls. Let's see how.

### `CallTargetNode`

In part 8, we saw that some syntax (`for` loops, `rescue` clauses, and multiple assignment) allowed us to implicitly write to variables. You can do the same with method calls:

```ruby
foo.bar, = baz
```

In this case we are implicitly calling the `bar=` method with the first value that will be spread from the right-hand side of the `=` operator. We represent this with a `CallTargetNode`. Here's what the AST looks like for the above snippet:

<div align="center">
  <img src="/assets/aop/part14-call-target-node.svg" alt="call target node">
</div>

These fields are mostly familiar to us. Notably we do not have a field for arguments or a block because that cannot be expressed with this syntax.

### `IndexTargetNode`

As with all of the other dualities involving `[]` syntax, there is also a way to target index calls. Here's an example:

```ruby
foo[:bar], = baz
```

In this case we are implicitly calling the `[]=` method with whatever values we put within the brackets and the first value that will be spread from the right-hand side of the `=` operator. We represent this with a `IndexTargetNode`. Here's what the AST looks like for the above snippet:

<div align="center">
  <img src="/assets/aop/part14-index-target-node.svg" alt="index target node">
</div>

For these we have to have a list of arguments, as well as a potential field for a block through the `&` operator.

## Wrapping up

You can make method calls through operator writes, the `super` keyword, and call targeting. These are not especially common in Ruby, so the semantics can surprise people. Here are a couple of things to remember:

* Operator writes where the target is a method call are two method calls, not one.
* The `super` keyword when you do not specify parentheses or arguments forwards all arguments to the parent method.
* Calls can be targeted just like variables, which will implicitly call the same method with a `=` appended.

Tomorrow we'll take a break from the calls themselves and look at how various arguments are handled.
