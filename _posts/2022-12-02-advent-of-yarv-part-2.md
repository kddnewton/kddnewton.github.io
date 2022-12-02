---
layout: post
title: Advent of YARV
subtitle: Part 2 - Manipulating the stack
meta:
  "twitter:card": summary
  "twitter:title": "Advent of YARV: Part 2"
  "twitter:description": "This post is part of a series about how the YARV virtual machine works."
  "twitter:site": "@kddnewton"
  "twitter:image": https://upload.wikimedia.org/wikipedia/commons/thumb/7/73/Ruby_logo.svg/1200px-Ruby_logo.svg.png
---

This blog series is about how the CRuby virtual machine works. If you're new to the series, I recommend starting from [the beginning](/2022/11/30/advent-of-yarv-part-0). This post is about manipulating the virtual machine stack.

Now that we're a little more familiar with the virtual machine stack and how to push values onto it, we'll show a couple of instructions to do manipulations such as popping, duplicating, and swapping values.

- [pop](#pop)
- [adjuststack](#adjuststack)
- [dup](#dup)
- [dupn](#dupn)
- [setn](#setn)
- [topn](#topn)
- [swap](#swap)

## `pop`

To keep all of the various stack pointers valid, it's important that frames that push values onto the stack also pop them. This instruction is the simplest version of that, in that it pops a single value off the stack and discards it.

<div align="center">
  <img src="/assets/aoy/part2-pop.svg" alt="pop">
</div>

In Ruby:

```ruby
class Pop
  def call(vm)
    vm.stack.pop
  end
end
```

In `foo ||= 1` disassembly:

```
== disasm: #<ISeq:<main>@-e:1 (1,0)-(1,9)> (catch: false)
local table (size: 1, argc: 0 [opts: 0, rest: -1, post: 0, block: -1, kw: -1@-1, kwrest: -1])
[ 1] foo@0
0000 getlocal_WC_0                          foo@0                     (   1)[Li]
0002 dup
0003 branchif                               10
0005 pop
0006 putobject_INT2FIX_1_
0007 dup
0008 setlocal_WC_0                          foo@0
0010 leave
```

## `adjuststack`

There are some nodes in the syntax tree that get compiled into sets of instructions that push multiple values onto the stack that then need to be popped off. Instead of inserting multiple `pop` instructions in a row, there's a single `adjuststack` instruction that pops multiple values off the stack. The instruction has an operand that tells it the number of values to pop. For example, with `adjuststack 2`:

<div align="center">
  <img src="/assets/aoy/part2-adjuststack.svg" alt="adjuststack">
</div>

In Ruby:

```ruby
class AdjustStack
  attr_reader :number

  def initialize(number)
    @number = number
  end

  def call(vm)
    vm.stack.pop(number)
  end
end
```

In `foo[0] ||= 1` disassembly:

```
== disasm: #<ISeq:<main>@-e:1 (1,0)-(1,12)> (catch: false)
0000 putnil                                                           (   1)[Li]
0001 putself
0002 opt_send_without_block                 <calldata!mid:foo, argc:0, FCALL|VCALL|ARGS_SIMPLE>
0004 putobject_INT2FIX_0_
0005 dupn                                   2
0007 opt_aref                               <calldata!mid:[], argc:1, ARGS_SIMPLE>[CcCr]
0009 dup
0010 branchif                               20
0012 pop
0013 putobject_INT2FIX_1_
0014 setn                                   3
0016 opt_aset                               <calldata!mid:[]=, argc:2, ARGS_SIMPLE>[CcCr]
0018 pop
0019 leave
0020 setn                                   3
0022 adjuststack                            3
0024 leave
```

## `dup`

There are times when we need multiple copies of the same object on the top of the stack. For example, if you're going to assign a local variable and then use the value, you need to duplicate the value before assigning it. This instruction duplicates the top value on the stack and pushes the duplicate onto the stack.

<div align="center">
  <img src="/assets/aoy/part2-dup.svg" alt="dup">
</div>

In Ruby:

```ruby
class Dup
  def call(vm)
    vm.stack.push(vm.stack.last.dup)
  end
end
```

In `$foo = 1` disassembly:

```
== disasm: #<ISeq:<main>@-e:1 (1,0)-(1,8)> (catch: false)
0000 putobject_INT2FIX_1_                                             (   1)[Li]
0001 dup
0002 setglobal                              :$foo
0004 leave
```

## `dupn`

This instruction is similar to `dup`, but it duplicates multiple values from the top of the stack. It's used when there are multiple stack values that you need copies of. For example, with `dupn 2`:

<div align="center">
  <img src="/assets/aoy/part2-dupn.svg" alt="dupn">
</div>

In Ruby:

```ruby
class DupN
  attr_reader :number

  def initialize(number)
    @number = number
  end

  def call(vm)
    values = vm.stack.pop(number)
    vm.stack.push(*values)
    vm.stack.push(*values.map(&:dup))
  end
end
```

In `Foo::Bar ||= true` disassembly:

```
== disasm: #<ISeq:<main>@-e:1 (1,0)-(1,17)> (catch: false)
0000 opt_getconstant_path                   <ic:0 Foo>                (   1)[Li]
0002 dup
0003 defined                                constant-from, :Bar, true
0007 branchunless                           18
0009 dup
0010 putobject                              true
0012 getconstant                            :Bar
0014 dup
0015 branchif                               25
0017 pop
0018 putobject                              true
0020 dupn                                   2
0022 swap
0023 setconstant                            :Bar
0025 swap
0026 pop
0027 leave
```

## `setn`

We haven't gotten to method calls yet, but it's useful to get a quick understanding of them before discussing `setn`. The YARV calling convention is to have the receiver and all of the arguments pushed onto the stack, and then to call `send`. The order of arguments matters, as that's how they get assigned to parameters in the method's frame. As such, it's helpful to be able to set specific slots in the stack to specific values, which is the function of `setn`. `setn` takes a single number parameter and sets the value at that index from the top of the stack to the value at the top of the stack. For example, with `setn 2`:

<div align="center">
  <img src="/assets/aoy/part2-setn.svg" alt="setn">
</div>

In Ruby:

```ruby
class SetN
  attr_reader :number

  def initialize(number)
    @number = number
  end

  def call(vm)
    value = vm.stack.pop
    vm.stack[-number] = value
    vm.stack.push(value)
  end
end
```

In `{}[:key] = "value"` disassembly:

```
== disasm: #<ISeq:<main>@-e:1 (1,0)-(1,18)> (catch: false)
0000 putnil                                                           (   1)[Li]
0001 newhash                                0
0003 putobject                              :key
0005 putstring                              "value"
0007 setn                                   3
0009 opt_aset                               <calldata!mid:[]=, argc:2, ARGS_SIMPLE>[CcCr]
0011 pop
0012 leave
```

## `topn`

As discussed with `setn`, the order of the stack is important for method calls. It can also be important when calling branching instructions. As a quick overview before the post comes out, branching instructions allow the virtual machine to skip executing sets of instructions under certain conditions. For most branching instructions, they involve testing a certain value against some predicate, where the value is always at the top of the stack. This is where `topn` comes in. It takes a single number parameter and pushes the value at that index from the top of the stack onto the top of the stack. For example, with `topn 2`:

<div align="center">
  <img src="/assets/aoy/part2-topn.svg" alt="topn">
</div>

In Ruby:

```ruby
class TopN
  attr_reader :number

  def initialize(number)
    @number = number
  end

  def call(vm)
    vm.stack.push(vm.stack[-number - 1])
  end
end
```

In `Foo::Bar += 1` disassembly:

```
== disasm: #<ISeq:<main>@-e:1 (1,0)-(1,13)> (catch: false)
0000 opt_getconstant_path                   <ic:0 Foo>                (   1)[Li]
0002 dup
0003 putobject                              true
0005 getconstant                            :Bar
0007 putobject_INT2FIX_1_
0008 opt_plus                               <calldata!mid:+, argc:1, FCALL|ARGS_SIMPLE>[CcCr]
0010 swap
0011 topn                                   1
0013 swap
0014 setconstant                            :Bar
0016 leave
```

## `swap`

As a final instruction for this post on manipulating the stack, we have `swap`. This instruction swaps the top two values on the stack. This is useful for reordering arguments for method calls or instructions.

<div align="center">
  <img src="/assets/aoy/part2-swap.svg" alt="swap">
</div>

In Ruby:

```ruby
class Swap
  def call(vm)
    left, right = vm.stack.pop(2)
    vm.stack.push(right, left)
  end
end
```

In `defined?([[]])` disassembly:

```
== disasm: #<ISeq:<main>@-e:1 (1,0)-(1,14)> (catch: true)
== catch table
| catch type: rescue st: 0001 ed: 0003 sp: 0000 cont: 0005
| == disasm: #<ISeq:defined guard in <main>@-e:0 (0,0)-(-1,-1)> (catch: false)
| local table (size: 1, argc: 0 [opts: 0, rest: -1, post: 0, block: -1, kw: -1@-1, kwrest: -1])
| [ 1] $!@0
| 0000 putnil
| 0001 leave
|------------------------------------------------------------------------
0000 putnil                                                           (   1)[Li]
0001 putobject                              "expression"
0003 swap
0004 pop
0005 leave
```

## Wrapping up

Our second post in the blog series has come to a close. In this post we talked about seven more instructions in the YARV instruction set. Here are some things to remember from this post:

* The order of the stack matters quite a bit. It determines the order of arguments, which value is going to be returned from blocks and methods, and which values will be used by subsequent instructions.
* Various instructions exist to manipulate the stack. Most of these could be modeled with multiple `putobject` and `pop` instructions, but it's much more efficient to have dedicated instructions.

In the next post we'll take a quick break from introducing instructions and instead introduce the concepts of frames and events.
