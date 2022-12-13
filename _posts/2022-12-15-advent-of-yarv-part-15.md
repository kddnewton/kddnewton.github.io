---
layout: post
title: Advent of YARV
subtitle: Part 15 - Defining classes and modules
meta:
  "twitter:card": summary
  "twitter:title": "Advent of YARV: Part 15"
  "twitter:description": "This post is part of a series about how the YARV virtual machine works."
  "twitter:site": "@kddnewton"
  "twitter:image": https://upload.wikimedia.org/wikipedia/commons/thumb/7/73/Ruby_logo.svg/1200px-Ruby_logo.svg.png
---

This blog series is about how the CRuby virtual machine works. If you're new to the series, I recommend starting from [the beginning](/2022/11/30/advent-of-yarv-part-0). This post is about defining classes and modules.

So far in this blog series we have looked at instructions that all operate within the current frame. We're about to break that trend by looking at our first instruction that pushes its own frame onto the stack. This instruction is `defineclass`, and it's used to define classes, singleton classes, and modules.

`defineclass` has three operands, pops two values off the stack, and pushes a single value back on, so it is the most complex instruction we've seen so far. The operands are:

* `ID id`: This is the name of the class or module being defined. If we're defining a singleton class (e.g., using the `class << self` syntax) then it will be the symbol `:singleton_class`.
* `ISEQ class_iseq`: This is the instruction sequence that will be executed to define the class or module. It will be executed inside the context of a new `class` frame that `defineclass` pushes onto the frame stack.
* `rb_num_t flags`: This is a bitfield that contains various flags about the instruction. For the most part this is basically an enum that tells the instruction if it's defining a class, singleton class, or module. It also includes a boolean flag that tells the instruction if the constant being defined is scoped and if there is a superclass in the case that this is defining a class.

The two values that are popped off the stack are the constant base (an idea we introduced when we looked at constants) and the superclass. In the case of a module or singleton class the second value will always be `nil`. Once the values are popped, the VM will call `vm_push_frame`, which is the internal function that pushes a new frame onto the stack. It will push the `class` frame and all of the instructions for the new context will be executed inside that frame.

It's important to note that this instruction can both create and reopen classes. If the class doesn't exist, it will be created. If the class does exist but the superclass is different, it will raise an error. If the class exists and the superclass is either not present or is the same, it will be reopened.

## Defining unscoped classes

Let's take a look at some disassembly examples for `defineclass` instructions. First let's look at defining an unscoped class:

```ruby
class Foo
  self
end
```

Note that in this example I'm purposefully choosing to use `self` here to illustrate that it will be executed in the context of the newly created class.

```
== disasm: #<ISeq:<main>@test.rb:1 (1,0)-(3,3)> (catch: false)
0000 putspecialobject                       3                         (   1)[Li]
0002 putnil
0003 defineclass                            :Foo, <class:Foo>, 0
0007 leave

== disasm: #<ISeq:<class:Foo>@test.rb:1 (1,0)-(3,3)> (catch: false)
0000 putself                                                          (   2)[LiCl]
0001 leave                                                            (   3)[En]
```

You can see that YARV is pushing on the constant base for the current frame and then `nil` to indicate that there is no superclass. The `defineclass` instruction is then called with the name `:Foo`, the instruction sequence for the class (represented as `<class:Foo>` which corresponds to the name of the other instruction sequence), and the flags `0`. The flags are `0` because this is an unscoped class with no superclass.

## Defining scoped classes

Now how about a class with a superclass that is scoped? Here's our Ruby:

```ruby
class Foo::Bar::Baz < Object
  self
end
```

And here is our disassembly:

```
== disasm: #<ISeq:<main>@test.rb:1 (1,0)-(3,3)> (catch: false)
0000 opt_getconstant_path                   <ic:0 Foo::Bar>           (   1)[Li]
0002 opt_getconstant_path                   <ic:1 Object>
0004 defineclass                            :Baz, <class:Baz>, 24
0008 leave

== disasm: #<ISeq:<class:Baz>@test.rb:1 (1,0)-(3,3)> (catch: false)
0000 putself                                                          (   2)[LiCl]
0001 leave                                                            (   3)[En]
```

You can see that first it's going to fetch the parent constant `Foo::Bar` that is going to own the `Foo::Bar::Baz` class. This functions as the constant base and is pushed onto the stack. Next it fetches the `Object` constant, which functions as the parent class and is pushed onto the stack. `defineclass` is called with the name `:Baz`, the instruction sequence for the class (represented as `<class:Baz>`), and the flags `24`. The flags are `24` because this is a scoped class (`8`) with a superclass (`16`).

## Defining singleton classes

Next, let's look at defining singleton classes:

```ruby
class << self
  self
end
```

Here's the disassembly:

```
== disasm: #<ISeq:<main>@test.rb:1 (1,0)-(3,3)> (catch: false)
0000 putself                                                          (   1)[Li]
0001 putnil
0002 defineclass                            :singletonclass, singleton class, 1
0006 leave

== disasm: #<ISeq:singleton class@test.rb:1 (1,0)-(3,3)> (catch: false)
0000 putself                                                          (   2)[LiCl]
0001 leave                                                            (   3)[En]
```

You can see that the constant base is pushed onto the stack which is the value that corresponds to the expression after the `<<` operator. Next we push `nil` onto the stack to indicate that there is no superclass. `defineclass` is called with the name `:singletonclass`, the instruction sequence for the singleton class (represented as `singleton class`), and the flags `1`. The flags are `1` because that value corresponds to creating a singleton class.

Note that anything could be in place of the first `self` in that example. If we were instead to replace it with `Object`, then it would look remarkably similar in the disassembly:

```
== disasm: #<ISeq:<main>@test.rb:1 (1,0)-(3,3)> (catch: false)
0000 opt_getconstant_path                   <ic:0 Object>             (   1)[Li]
0002 putnil
0003 defineclass                            :singletonclass, singleton class, 1
0007 leave

== disasm: #<ISeq:singleton class@test.rb:1 (1,0)-(3,3)> (catch: false)
0000 putself                                                          (   2)[LiCl]
0001 leave                                                            (   3)[En]
```

The only difference here is that the constant base is `Object` instead of `self`.

## Defining modules

Finally, let's look at defining a module:

```ruby
module Foo
  self
end
```

A simple module that is unscoped. Here's the disassembly:

```
== disasm: #<ISeq:<main>@test.rb:1 (1,0)-(3,3)> (catch: false)
0000 putspecialobject                       3                         (   1)[Li]
0002 putnil
0003 defineclass                            :Foo, <module:Foo>, 2
0007 leave

== disasm: #<ISeq:<module:Foo>@test.rb:1 (1,0)-(3,3)> (catch: false)
0000 putself                                                          (   2)[LiCl]
0001 leave                                                            (   3)[En]
```

Again the constant base is pushed onto the stack, followed by `nil` to indicate that there is no superclass. `defineclass` is called with the name `:Foo`, the instruction sequence for the module (represented as `<module:Foo>`), and the flags `2`. The flags are `2` because that's the value that corresponds to defining a module.

## Wrapping up

Today we looked at the `defineclass` instruction and its various forms. We saw that it is used to define classes, modules, and singleton classes. A couple of things to remember from this post:

* Classes, modules, and singleton classes are all defined with the `defineclass` instruction.
* Singleton classes can be defined at any time using the `class <<` syntax with any given expression.

In the next post we'll look at defining methods.
