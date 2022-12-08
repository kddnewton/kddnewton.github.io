---
layout: post
title: Advent of YARV
subtitle: Part 8 - Local variables (1)
meta:
  "twitter:card": summary
  "twitter:title": "Advent of YARV: Part 8"
  "twitter:description": "This post is part of a series about how the YARV virtual machine works."
  "twitter:site": "@kddnewton"
  "twitter:image": https://upload.wikimedia.org/wikipedia/commons/thumb/7/73/Ruby_logo.svg/1200px-Ruby_logo.svg.png
---

This blog series is about how the CRuby virtual machine works. If you're new to the series, I recommend starting from [the beginning](/2022/11/30/advent-of-yarv-part-0). This post is the first of three posts about local variables.

Local variables are everywhere in our Ruby code, and most of the time you don't have to think too hard about them. They're the easiest to work with because they're so immediate. Generally the entire lifetime of a local variable fits neatly onto your screen; from the time they are initialized to the time where they fall out of scope.

Scope is the key word here. What does it mean for a local variable to be "in scope"? In Ruby, there are a couple of different scopes that can be found, which correspond to the frames that are executing them. We've discussed frames and the frame stack before, but let's take a look at them again.

Recall that when a method is executed, a `method` frame is pushed onto the frame stack corresponding to the instruction sequence that describes the body of that method. Similarly, when a block is executed, a `block` frame is pushed onto the frame stack corresponding to the instruction sequence that describes the body of the block. How are these two frames different? In two ways:

* The value of `self` will be different. `block` frames inherit their parent frame's `self` value, while `method` frames use the value of `self` that corresponds to the receiver of the method.
* The scoping will be different. Generally, `block` frames are allowed to see their parent frame's local variables, while `method` frames do not.

We'll see how `block` frames (along with `rescue` and `ensure` frames) can access their parent frame's local variables in the instructions in this post.

* [getlocal](#getlocal)
* [setlocal](#setlocal)
* [putself](#putself)

## `getlocal`

Each instruction sequence keeps a list of declared local variables. These variables can be either arguments or plain locals. When a frame corresponding to the instruction sequence is pushed onto the stack, the frame allocates space on the stack for each plain local variable. Therefore, when you're accessing a local variable, you're really accessing a value in the stack. The location where the value is stored is compiled along with the instruction sequence and stored as a negative offset from the environment pointer.

For example, let's say we have the following method:

```ruby
def double(value)
  factor = 2
  value * factor
end
```

When the method is first called, a `method` frame is pushed onto the frame stack. The top value on the stack will be the `value` argument, and just below that will be the receiver. As we discussed in the post on `send`, the caller will then move its stack pointer below the receiver. The callee (the receiver of the `double` method) will then establish its two pointers.

The instruction sequence for the `method` frame corresponding to the `double` method knows that it has two locals: `value` (at index 0) and `factor` (at index 1). It also knows that `value` is an argument, so it will already be on the stack when the method is called. Therefore the `method` frame will allocate a single space for the `factor` local. The `method` frame will then set its environment pointer to be just above this space. Whenever the VM wants to access the `value` local, it will look for the value stack slot at[^1]:

```ruby
environment_pointer - (locals_length - local_index)
```

As discussed, `block` frames can access their parent frame's local variables. The value for `environment_pointer` in the previous equation was the current frame's environment pointer, but in reality it could be any frame's environment pointer. This is the manner in which `block` frames can access their parent frame's local variables: by substituting in their parent's environment pointer. For example, in the following code:

```ruby
value = 5
yield_self do
  factor = 2
  value * factor
end
```

In this case, the value stack is set up slightly differently, with the bottom of the stack being the integer `5` corresponding to the `value` variable, then the value of `self` for the parent frame. The parent frame has its environment pointer pointing just above the `value` local. This time, the `block` frame only has the `factor` local because the `value` local belongs to the parent frame. The `block` frame will set its environment pointer to be just above the `factor` local. When it wants to access the `value` local, it will look for the value stack slot using the same formula as before but with the parent frame's environment pointer.

The `getlocal` instruction therefore has two operands: the index of the local variable (the `local_index` from our formula above) and the level of the frame to look for the local variable in (i.e., how much parent frames to traverse to find the correct environment pointer). The instruction will get the value of the local at the given index and level and push the value onto the value stack. For example, with the previous code and `getlocal 0, 1`:

<div align="center">
  <img src="/assets/aoy/part8-getlocal.svg" alt="getlocal">
</div>

In Ruby:

```ruby
class GetLocal
  attr_reader :index, :level

  def initialize(index, level)
    @index = index
    @level = level
  end

  def call(vm)
    frame = vm.frames[-(level + 1)]
    offset = frame.ep - (frame.locals.length - index)
    vm.stack.push(vm.stack[offset])
  end
end
```

In the disassembly of the block example from above:

```
== disasm: #<ISeq:<main>@test.rb:1 (1,0)-(5,3)> (catch: false)
local table (size: 1, argc: 0 [opts: 0, rest: -1, post: 0, block: -1, kw: -1@-1, kwrest: -1])
[ 1] value@0
0000 putobject                              5                         (   1)[Li]
0002 setlocal                               value@0, 0
0005 putself                                                          (   2)[Li]
0006 send                                   <calldata!mid:yield_self, argc:0, FCALL>, block in <main>
0009 leave

== disasm: #<ISeq:block in <main>@test.rb:2 (2,11)-(5,3)> (catch: false)
local table (size: 1, argc: 0 [opts: 0, rest: -1, post: 0, block: -1, kw: -1@-1, kwrest: -1])
[ 1] factor@0
0000 putobject                              2                         (   3)[LiBc]
0002 setlocal                               factor@0, 0
0005 getlocal                               value@0, 1                (   4)[Li]
0008 getlocal                               factor@0, 0
0011 send                                   <calldata!mid:*, argc:1, ARGS_SIMPLE>, nil
0014 leave                                                            (   5)[Br]
```

You can see that in the disassembly it's kind enough the show you the name of the local variable in the first operand to `getlocal` in addition to its index, even though the actual instruction only stores the index.

You can also see in the disassembly that there's an additional line in the output for frames that include local variables. This line always beings with `local table` and it shows the number and kind of every local variable. We'll dig more into some of the details of the names and numbers on this line in future posts, but for now you can focus on the `size: 1` in the previous example. This means that it knows that it has `1` local variable that will be declared within the instruction sequence and that it needs to allocate space for.

### `getlocal_WC_0`

Because it's so common to access a local variable on the current frame, the `getlocal_WC_0` specialization exists. This instruction only has one operand, the index of the local variable, with an assumed level of 0 (meaning the current frame). This saves on space in the instruction sequence.

In Ruby:

```ruby
class GetLocalWC0
  attr_reader :index

  def initialize(index)
    @index = index
  end

  def call(vm)
    frame = vm.frames.last
    offset = frame.ep - (frame.locals.length - index)
    vm.stack.push(vm.stack[offset])
  end
end
```

In `foo = 0; foo` disassembly:

```
== disasm: #<ISeq:<main>@-e:1 (1,0)-(1,12)> (catch: FALSE)
local table (size: 1, argc: 0 [opts: 0, rest: -1, post: 0, block: -1, kw: -1@-1, kwrest: -1])
[ 1] foo@0
0000 putobject_INT2FIX_0_                                             (   1)[Li]
0001 setlocal_WC_0                          foo@0
0003 getlocal_WC_0                          foo@0
0005 leave
```

### `getlocal_WC_1`

Similarly, the `getlocal_WC_1` specialization exists for accessing a local variable on the parent frame. This instruction only has one operand, the index of the local variable, with an assumed level of 1 (meaning the parent frame). This saves on space in the instruction sequence.

In Ruby:

```ruby
class GetLocalWC1
  attr_reader :index

  def initialize(index)
    @index = index
  end

  def call(vm)
    frame = vm.frames[-2]
    offset = frame.ep - (frame.locals.length - index)
    vm.stack.push(vm.stack[offset])
  end
end
```

In `foo = 0; tap { foo }` disassembly:

```
== disasm: #<ISeq:<main>@-e:1 (1,0)-(1,20)> (catch: FALSE)
local table (size: 1, argc: 0 [opts: 0, rest: -1, post: 0, block: -1, kw: -1@-1, kwrest: -1])
[ 1] foo@0
0000 putobject_INT2FIX_0_                                             (   1)[Li]
0001 setlocal_WC_0                          foo@0
0003 putself
0004 send                                   <calldata!mid:tap, argc:0, FCALL>, block in <main>
0007 leave

== disasm: #<ISeq:block in <main>@-e:1 (1,13)-(1,20)> (catch: FALSE)
0000 getlocal_WC_1                          foo@0                     (   1)[LiBc]
0002 leave                                  [Br]
```

Notice here that the child frame named `block in <main>` has no locals of its own, therefore there's no `local table` line in the disassembly.

## `setlocal`

The `setlocal` instruction is very similar to the `getlocal` instruction. It has the same operands, and will find the same value stack slot using the same formula. The difference is that instead of getting a copy of the value and pushing it onto the top of the stack, it will instead pop a value off the top of the stack and write it to the value stack slot. For example, in the following Ruby code:

```ruby
value = 5
tap { value = 10 }
```

Within the block, the `value` local is being written to, even though the block doesn't own that local variable. The `setlocal` instruction is responsible for that. With `setlocal 0, 1`, this looks like:

<div align="center">
  <img src="/assets/aoy/part8-setlocal.svg" alt="setlocal">
</div>

In Ruby:

```ruby
class SetLocal
  attr_reader :index, :level

  def initialize(index, level)
    @index = index
    @level = level
  end

  def call(vm)
    frame = vm.frames[-(level + 1)]
    offset = frame.ep - (frame.locals.length - index)
    vm.stack[offset] = vm.stack.pop
  end
end
```

In the disassembly for the example code above:

```
== disasm: #<ISeq:<main>@-e:1 (1,0)-(1,29)> (catch: FALSE)
local table (size: 1, argc: 0 [opts: 0, rest: -1, post: 0, block: -1, kw: -1@-1, kwrest: -1])
[ 1] value@0
0000 putobject                              5                         (   1)[Li]
0002 setlocal                               value@0, 0
0005 putself
0006 send                                   <calldata!mid:tap, argc:0, FCALL>, block in <main>
0009 leave

== disasm: #<ISeq:block in <main>@-e:1 (1,15)-(1,29)> (catch: FALSE)
0000 putobject                              10                        (   1)[LiBc]
0002 dup
0003 setlocal                               value@0, 1
0006 leave                                  [Br]
```

### `setlocal_WC_0`

Much like `getlocal_WC_0`, `setlocal_WC_0` is a specialization of `setlocal` that sets a local on the current frame. Its only operand is the index of the local variable, which saves on space in the instruction sequence.

In Ruby:

```ruby
class SetLocalWC0
  attr_reader :index

  def initialize(index)
    @index = index
  end

  def call(vm)
    frame = vm.frames.last
    offset = frame.ep - (frame.locals.length - index)
    vm.stack[offset] = vm.stack.pop
  end
end
```

In `value = 5` disassembly:

```
== disasm: #<ISeq:<main>@-e:1 (1,0)-(1,9)> (catch: FALSE)
local table (size: 1, argc: 0 [opts: 0, rest: -1, post: 0, block: -1, kw: -1@-1, kwrest: -1])
[ 1] value@0
0000 putobject                              5                         (   1)[Li]
0002 dup
0003 setlocal_WC_0                          value@0
0005 leave
```

### `setlocal_WC_1`

Similarly, the `setlocal_WC_1` specialization exists for setting a local variable on the parent frame. This instruction only has one operand, the index of the local variable, with an assumed level of 1 (meaning the parent frame). This saves on space in the instruction sequence.

In Ruby:

```ruby
class SetLocalWC1
  attr_reader :index

  def initialize(index)
    @index = index
  end

  def call(vm)
    frame = vm.frames[-2]
    offset = frame.ep - (frame.locals.length - index)
    vm.stack[offset] = vm.stack.pop
  end
end
```

In `value = 5; tap { value = 10 }` disassembly:

```
== disasm: #<ISeq:<main>@-e:1 (1,0)-(1,29)> (catch: FALSE)
local table (size: 1, argc: 0 [opts: 0, rest: -1, post: 0, block: -1, kw: -1@-1, kwrest: -1])
[ 1] value@0
0000 putobject                              5                         (   1)[Li]
0002 setlocal_WC_0                          value@0
0004 putself
0005 send                                   <calldata!mid:tap, argc:0, FCALL>, block in <main>
0008 leave

== disasm: #<ISeq:block in <main>@-e:1 (1,15)-(1,29)> (catch: FALSE)
0000 putobject                              10                        (   1)[LiBc]
0002 dup
0003 setlocal_WC_1                          value@0
0005 leave                                  [Br]
```

## `putself`

There's one more instruction in this post that we need to discuss. While not technically a local variable, `self` is a kind of implicit local to any given scope. The `putself` instruction is responsible for pushing the current `self` onto the value stack. It has no operands. It finds the value of `self` by asking the current frame in the frame stack. For example, in the following Ruby code:

```ruby
self
```

would push the `main` object onto the value stack. However in the following Ruby code:

```ruby
class Foo
  def bar
    self
  end
end
```

calling the `Foo#bar` method would push a `method` frame onto the stack that would have a `self` pointing to the instance of `Foo` that this method got called on. Therefore the `self` that got pushed would be the instance of `Foo`.

<div align="center">
  <img src="/assets/aoy/part8-putself.svg" alt="putself">
</div>

In Ruby:

```ruby
class PutSelf
  def call(vm)
    vm.stack.push(vm.frames.last._self)
  end
end
```

In `self` disassembly:

```
== disasm: #<ISeq:<main>@-e:1 (1,0)-(1,4)> (catch: FALSE)
0000 putself                                                          (   1)[Li]
0001 leave
```

## Wrapping up

In this post we've covered the `getlocal`, `setlocal`, and `putself` instructions along with their specializations. We've also covered how the frame stack is used to find the correct local variable to get or set. A couple of things to remember from this post:

* Locals are stored in the value stack, not in some separate table. The term "local table" refers to the metadata about the local variables, not the actual values.
* Accessing local variables means calculating a negative offset from a frame's environment pointer. The frame whose environment pointer is being used in that calculation is determined by the level of the local variable.
* A value for `self` is stored in each frame. The `putself` instruction pushes the current `self` onto the value stack.

In the next post we'll look at some special local variables that handle block locals.

---

[^1]: Technically, a couple of other things are pushed onto the stack when a method is called, so this calculation is a little different to account for those extra slots. We're ignoring those for now to keep the math consistent between different frame types.
