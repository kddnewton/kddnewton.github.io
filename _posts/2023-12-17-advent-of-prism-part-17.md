---
layout: post
title: Advent of Prism
subtitle: Part 17 - Scopes
meta:
  "twitter:card": summary
  "twitter:title": "Advent of Prism: Part 17"
  "twitter:description": "This post is part of a series about how the prism Ruby parser works."
  "twitter:site": "@kddnewton"
  "twitter:image": https://upload.wikimedia.org/wikipedia/commons/thumb/7/73/Ruby_logo.svg/1200px-Ruby_logo.svg.png
---

This blog series is about how the prism Ruby parser works. If you're new to the series, I recommend starting from [the beginning](/2023/11/30/advent-of-prism-part-0). This post is about nodes that introduce a new scope.

"Scope" is a term that gets somewhat abused in programming languages. It can mean quite a lot of things. Our definition for today refers to local variables. For today's post when we say "scope" we mean a new set of local variables. Let's have a look at the nodes that introduce new scopes.

## `DefNode`

When you define a method using the `def` keyword, we represent it with a `DefNode`. Here's an example:

```ruby
def foo
  1
end
```

This code is represented by the following AST:

<div align="center">
  <img src="/assets/aop/part17-def-node-1.svg" alt="def node">
</div>

There are a lot of fields on these nodes (more than any other in the AST!). The important ones here are:

* `name` - the name of the method
* `locals` - the local table for the method
* `body` - the body of the method

### Explicit receiver

In the first example, the implicit owner of this new method is the current value of `self`. That can be made explicit, however, with an expression that ends in a `.` or `::`. Here's an example:

```ruby
def self.foo
  1
end
```

In this case the owner will be the singleton class of the current value of `self`. It does not need to be limited to the `self` keyword, though. It can be almost any Ruby expression (especially when wrapped in parentheses), as in:

```ruby
def Object.foo
  1
end

Object.foo # => 1
```

The AST for the first explicit receiver example looks like:

<div align="center">
  <img src="/assets/aop/part17-def-node-2.svg" alt="def node">
</div>

Here we get even more fields, but the important one is `receiver` which points to the expression on which the method should be defined.

Other parses have split this node up into two different nodes: one with an implicit receiver and one with an explicit receiver. We felt like this could be annoying for consuming tools because processing all method definitions is a very common task. We wanted them to be able to do it in one place.

### Single-line

The `def` keyword can also be used to define a method on a single line. Here's an example:

```ruby
def foo = 1
```

In this case the body of the method is the expression that follows the `=` sign. This is semantically equivalent to the following:

```ruby
def foo
  1
end
```

In terms of the parser there are some eccentricities. For example based on the existing precedence, `def foo = bar rescue baz` would normally be parsed as `(def foo = bar) rescue baz`, but there is a different path through the parser that allows `def foo = bar rescue baz` to be parsed as `def foo = (bar rescue baz)`. There is also a [current debate](https://bugs.ruby-lang.org/issues/19392) on allowing `and/or` to be used in these kinds of methods as well.

The AST for this example looks like:

<div align="center">
  <img src="/assets/aop/part17-def-node-3.svg" alt="def node">
</div>

You'll notice that none of our examples today have any parameters on the methods. That's because the subject of tomorrow's post is parameters. We'll come back to them.

### Rescues

We haven't gotten to rescues yet, but it's important that we mention them here because you can use them in the body of a method definition. Here's an example:

```ruby
def foo
  bar
rescue
  1
end
```

This code says to execute the `bar` method call, rescue any errors that inherit from `StandardError`, and then return `1` in the case an error was thrown. These rescue clauses can be chained together, and they can be combined with `else` and `ensure` clauses. We'll see more of this when we get to the post on rescues. The important piece of this to note for today is that in the event that some of these clauses are present, the `body` field will be replaced by a `BeginNode` instead of a `StatementsNode`. As an illustration, the AST for the above example is:

<div align="center">
  <img src="/assets/aop/part17-def-node-4.svg" alt="def node">
</div>

## `ClassNode`

Classes that are defined with the `class` keyword are represented by a `ClassNode`. Here's an example:

```ruby
class Foo
end
```

This code is represented by the following AST:

<div align="center">
  <img src="/assets/aop/part17-class-node.svg" alt="class node">
</div>

This simplistic class has the following important fields:

* `constant_path` - a pointer to the expression after the `class` keyword before the body
* `locals` - the local table for the class
* `name` - the name of the class. This could easily be derived from the `constant_path` node, but it requires descending down the tree in order to find the leaf node. We cache it here because all compilers need to know the name of the class in order to generate the correct name for the frame pushed by the class.

Classes can also have superclasses and a body. Here's an example:

```ruby
class Foo < Bar
  1
end
```

This is represented by the following AST:

<div align="center">
  <img src="/assets/aop/part17-class-node-2.svg" alt="class node">
</div>

It's important to note two things from this example. First, `Bar` does not need to be a constant or constant path. It can be the result of any method call that you want. For example:

```ruby
superclass = Object
class Foo < superclass
end
```

This works just fine, and in fact is equivalent to the first example in this post. The second thing to note is that any code can be placed inside of `Foo`, not just method definitions or method calls. In our example we have a single `1` as the body of the class. That actually changes the return value of the entire `class .. end` expression to be `1`.

As with method definitions, classes can also have rescue clauses. That would look like:

```ruby
class Foo
  bar
rescue
end
```

We'll cover this more when we get to rescues.

The last piece of this to note is that classes can be defined on a constant path and not just a constant. For example:

```ruby
class Foo::Bar::Baz
end
```

This will look up the `Foo::Bar` constant path, define a class, and then assign that class to the `Baz` constant on that namespace. The AST for this example looks like:

<div align="center">
  <img src="/assets/aop/part17-class-node-3.svg" alt="class node">
</div>

## `ModuleNode`

Modules that are defined using the `module` keyword are represented by a `ModuleNode`. Here's an example:

```ruby
module Foo
end
```

The AST for this example looks like:

<div align="center">
  <img src="/assets/aop/part17-module-node.svg" alt="module node">
</div>

Parsing these expressions is effectively a simpler form of parsing classes. The also have a constant path, a local table, and a body. They can also be combined with `rescue` clauses in the same way. As with classes, they can have any expressions in their body, not just method definitions or method calls.

## `SingletonClassNode`

The final scope that we're going to talk about today are singleton class expressions. These expressions allow you to execute code within the singleton class of an object. For example:

```ruby
class << self
  1
end
```

This code is represented by the following AST:

<div align="center">
  <img src="/assets/aop/part17-singleton-class-node.svg" alt="singleton class node">
</div>

These nodes have a pointer to the expression that is used to find the singleton class, a pointer to the body of expressions that should be executed within the singleton class, and a local table. As with classes and modules, the body can be any expression, not just method definitions or method calls. Also as with classes and modules, they can be combined with `rescue` clauses.

It's important to remember that `self` is not the only singleton class you can enter into. For example, let's say you wanted to define a method on `Object`:

```ruby
class << Object
  def foo
    1
  end
end

Object.foo
```

Now if you wanted to remove that method, you could:

```ruby
class << Object
  undef foo
end
```

Entering into a singleton class of an object can be very powerful, especially when combined with metaprogramming.

## Wrapping up

As you can imagine, these four nodes are very common in Ruby code, so it's important to understand their semantics. Here are some things to remember from today's post:

* `def`, `class`, `module`, and `class <<` can be combined with `rescue`, `else`, and `ensure` clauses
* The superclass of a class can be any expression
* The receiver of a method definition can be any expression
* You can enter into the singleton class of any object, not just `self`

After discussing method definitions today, tomorrow we'll be rounding out method definitions by looking at method parameters.
