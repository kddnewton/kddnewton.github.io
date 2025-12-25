---
layout: post
title: Advent of YARV
subtitle: Part 13 - Constants
meta:
  "twitter:card": summary
  "twitter:title": "Advent of YARV: Part 13"
  "twitter:description": "This post is part of a series about how the YARV virtual machine works."
  "twitter:site": "@kddnewton"
  "twitter:image": https://upload.wikimedia.org/wikipedia/commons/thumb/7/73/Ruby_logo.svg/1200px-Ruby_logo.svg.png
---

This blog series is about how the CRuby virtual machine works. If you're new to the series, I recommend starting from [the beginning](/2022/11/30/advent-of-yarv-part-0). This post is about constants.

Constants in Ruby exist in their own tree. Accessing them involves looking them up by walking up the tree according to your current constant nesting. The details of that specific algorithm are outside the scope of this post, but you can read more about it in the [Ruby documentation](https://ruby-doc.org/3.1.2/syntax/modules_and_classes_rdoc.html). You can access constants from one of three starting points:

* An absolute path, as in `::Foo`
* A path relative to a variable, as in `foo::Bar`
* A path relative to the current nesting, as in `Foo::Bar`

In the first two cases, you know exactly where to start looking. For an absolute path it's the top level, which means starting from the `Object` constant and working your way down the tree. For a path relative to a variable, you start at the constant that the variable points to (it will raise a `TypeError` if the variable is not a class or module).

In the third case you need to walk up the tree from the current nesting. The nesting is stored as a part of the current frame, so walking up the tree involves walking up the frame stack. The starting point in this case is called the constant base. This needs to be pushed onto the stack to maintain the same stack order as the other two cases.

We'll see today how the virtual machine handles all three cases, and how it can be optimized to avoid the constant lookup when it can be cached.

* [getconstant](#getconstant)
* [setconstant](#setconstant)
* [putspecialobject](#putspecialobject)
* [opt_getconstant_path](#opt_getconstant_path)

## `getconstant`

The instruction that performs the constant lookup is called `getconstant`. It has a single operand, which is the name of the constant to find. `getconstant` pops two values off the stack. The first is the constant base, which is the starting point for the lookup. It expects that this object will point to a class or module.

Let's start with the first two cases, an absolute path or a path relative to a variable. In these cases you either start from the top level (which means the `Object` class will be pushed onto the stack) or you start at a given constant (which means the class or module will already be on the stack as a result of a different instruction). In either case, the constant base is on the stack in the correct place.

In the last case, the constant base is pushed onto the stack by pushing on `nil` with `putnil`. The second popped value is a boolean that indicates whether or not the constant base is allowed to be `nil`. If it is, then it will search the current lexical scope. If it is not, then it will instead call the `#const_missing` method.[^1]

If the value is successfully found, it is pushed onto the stack, otherwise `nil` is pushed. For example, with `getconstant :Foo`:

<div align="center">
  <img src="/assets/aoy/part13-getconstant.svg" alt="getconstant">
</div>

We'll look at two disassembly examples. The first will be for an absolute path, as in `::Foo::Bar::Baz`:[^2]

```
== disasm: #<ISeq:<main>@-e:1 (1,0)-(1,15)> (catch: false)
0000 putnil                                                           (   1)[Li]
0001 pop
0002 putobject                              Object
0004 putobject                              true
0006 getconstant                            :Foo
0008 putobject                              false
0010 getconstant                            :Bar
0012 putobject                              false
0014 getconstant                            :Baz
0016 leave
```

The second will be for a path relative to a variable, as in `foo::Bar::Baz`:

```
== disasm: #<ISeq:<main>@-e:1 (1,0)-(1,13)> (catch: false)
0000 putself                                                          (   1)[Li]
0001 send                                   <calldata!mid:foo, argc:0, FCALL|VCALL|ARGS_SIMPLE>, nil
0004 putobject                              false
0006 getconstant                            :Bar
0008 putobject                              false
0010 getconstant                            :Baz
0012 leave
```

Notice that in both examples the instructions form a chain of a class/module, then a `putobject` with a boolean, then a `getconstant`.

## `setconstant`

Setting a constant is somewhat different from looking one up. You cannot set a chain of constants in Ruby, only a single constant. This means the `::Foo::Bar::Baz = 1` really breaks down to looking up `::Foo::Bar`, then setting the `:Baz` constant on that class or module. This is what the `setconstant` instruction does.

`setconstant` accepts a single operand, which is the name of the constant to set. It pops two values off the stack. The top value on the stack is expected to be the constant base. The next value down is expected to be the value to set. For example, with `setconstant :Foo`:

<div align="center">
  <img src="/assets/aoy/part13-setconstant.svg" alt="setconstant">
</div>

In `::Foo::Bar::Baz = 1` disassembly:

```
== disasm: #<ISeq:<main>@-e:1 (1,0)-(1,19)> (catch: false)
0000 putnil                                                           (   1)[Li]
0001 pop
0002 putobject                              Object
0004 putobject                              true
0006 getconstant                            :Foo
0008 putobject                              false
0010 getconstant                            :Bar
0012 putobject                              1
0014 swap
0015 topn                                   1
0017 swap
0018 setconstant                            :Baz
0020 leave
```

In `foo::Bar::Baz = 1` disassembly:

```
== disasm: #<ISeq:<main>@-e:1 (1,0)-(1,17)> (catch: false)
0000 putself                                                          (   1)[Li]
0001 send                                   <calldata!mid:foo, argc:0, FCALL|VCALL|ARGS_SIMPLE>, nil
0004 putobject                              false
0006 getconstant                            :Bar
0008 putobject                              1
0010 swap
0011 topn                                   1
0013 swap
0014 setconstant                            :Baz
0016 leave
```

## `putspecialobject`

Because the constant base is expected to be on the stack, there are occasions where it needs to be pushed on from a value relative to the current context. This is done with the `putspecialobject` instruction.

`putspecialobject` has a single operand which is an entry in the `vm_special_object_type` enum. Each value in that enum corresponds to a special object that can be pushed onto the stack for the purpose of maintaining the expectations of other instructions. As we saw with the `setconstant` instruction, it expects the constant base to be on the stack. As we saw in the previous post on calling methods, it expects the receiver to be on the stack. This instruction fills those expectations.

There are three entries in total, and we'll look at them in turn.

### `VM_SPECIAL_OBJECT_VMCORE`

The first type of special object is `VM_SPECIAL_OBJECT_VMCORE`. This has the value of `1` in the enumeration, so you will see `putspecialobject 1` in the disassembly. This value corresponds to pushing the special `RubyVM::FrozenCore` object onto the stack. (Note that you won't be able to actually find that constant in Ruby because it's purposefully hidden.)

`RubyVM::FrozenCore` has a few methods on it to execute functions internal to CRuby. It allows YARV to send methods to it like it were any other Ruby object using the `send` instruction (or any of its specializations). The methods that it has defined on it include:

* `core#set_method_alias` - used when the `alias` keyword is used
* `core#set_variable_alias` - used when the `alias` keyword is used with a global variable
* `core#undef_method` - used when the `undef` keyword is used
* `core#set_postexe` - used when the `END {}` syntax is used
* `core#hash_merge_ptr` - used to merge two hashes together
* `core#hash_merge_kwd` - used to merge the `**` syntax into a hash
* `core#raise` - used to raise an exception from within pattern matching
* `core#sprintf` - used to create a string from a format string and arguments from within pattern matching
* `proc`/`lambda` - used to create procs and lambdas
* `make_shareable` - used to create a shared object for Ractors
* `make_shareable_copy` - used to create a shared object for Ractors
* `enable_shareable` - used to mark an object as shareable for Ractors

### `VM_SPECIAL_OBJECT_CBASE`

The second type of special object is `VM_SPECIAL_OBJECT_CBASE`. This has the value of `2` in the enumeration, so you will see `putspecialobject 2` in the disassembly. This value corresponds to pushing the constant base corresponding to the current frame onto the stack. It does this by looking at the constant reference for the current frame and finding the value of `self`, then finding its class.

### `VM_SPECIAL_OBJECT_CONST_BASE`

The third and last type of special object is `VM_SPECIAL_OBJECT_CONST_BASE`. This has a value of `3` in the enumeration, so you will see `putspecialobject 3` in the disassembly. This is almost always the exact same value as `CBASE`, except that it skips `eval` frames.

This is the value that we care about in this blog post. Because the `setconstant` instruction expects the constant base to be on the stack, and we don't have it already from a previous instruction because we're looking up a relative path, the `putspecialobject` instruction is used to look up the context from the frame and push the constant base onto the stack.

For example, in `Foo = 1` disassembly:

```
== disasm: #<ISeq:<main>@-e:1 (1,0)-(1,7)> (catch: false)
0000 putobject_INT2FIX_1_                                             (   1)[Li]
0001 dup
0002 putspecialobject                       3
0004 setconstant                            :Foo
0006 leave
```

Here `setconstant` knows it expects the constant base to be on the stack, so it is pushed on with the `putspecialobject` instruction, which will push the constant base based on the current context onto the stack.

## `opt_getconstant_path`

The last instruction that we will be looking at today is an optimization that [John Hawthorn made](https://github.com/ruby/ruby/pull/6187) to simplify the whole chain of instructions that were previously in place to lookup a constant. Where before you would see the chain that we already looked at, now you see a single `opt_getconstant_path` instruction.

This instruction has a single operand which does a lot of heavy-lifting. It is an `iseq_inline_constant_cache` struct, which contains two values. The first is the value of the constant, which is cached after first lookup.[^3] The second is an array of symbols corresponding to the constant chain. For example, in `Foo::Bar::Baz`, the array would contain `[:Foo, :Bar, :Baz]`.[^4]

When the cache is first compiled, it is registered with the virtual machine for every symbol in the array. The VM contains a cache-busting mechanism where any time something changes in the VM that corresponds to a constant, it invalidates any cache that contains a segment corresponding to that name. For example, if you were to run `Foo = 1`, then any inline cache used by a `opt_getconstant_path` instruction that had `:Foo` in its list would be invalidated.

The instruction performs the same lookup (actually using the same path through the code) as `getconstant`. As its name suggests, this only works for absolute constant paths (`::Foo`) or paths relative to the current nesting (`Foo`); it will not be used for paths relative to a variable (`foo::Bar`). Since each part is known at compilation time, the constant base does not need to be on the stack as would be the case for `getconstant`. Once the final value has been found, it is pushed onto the stack. For example, in `Foo::Bar::Baz` disassembly:

```
== disasm: #<ISeq:<main>@-e:1 (1,0)-(1,13)> (catch: false)
0000 opt_getconstant_path                   <ic:0 Foo::Bar::Baz>      (   1)[Li]
0002 leave
```

## Wrapping up

Today we looked at all of the instructions that have to do with constants in Ruby. We saw how to get and set them, as well as looking at some optimizations that are in place to cache constant lookup. Some things to remember from this post:

* Constants exist in a tree. Looking them up involves walking the tree from some starting point.
* Some instructions have expectations about the order of values on the stack that need to be met before the instruction can execute. Other instructions like `putspecialobject` are in place to match those expectations.

This concludes our look at variables in Ruby. Tomorrow we'll look at instructions that allow the VM to skip other instructions to allow branching logic.

---

[^1]: You may be asking yourself why a value is pushed onto the stack to indicate that the constant is allowed to be `nil`, if that boolean flag is known at compile-time. This as opposed to making it an operand to the `getconstant` instruction. It turns out that's a [good question](https://github.com/ruby/ruby/pull/5709).
[^2]: I'm purposefully compiling this without optimizations turned on in order to demonstrate the `getconstant` instruction. Under regular circumstances, the compiler will optimize this to use `opt_getconstant_path` instead.
[^3]: Technically, it also contains the class reference in order to be sure that doesn't change as well, but don't worry about that for now. You can think of it as just the value of the constant.
[^4]: In order to avoid having to hold the size of the array as well, the array is null-terminated.
