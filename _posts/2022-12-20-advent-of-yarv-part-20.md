---
layout: post
title: Advent of YARV
subtitle: Part 20 - Catch tables
meta:
  "twitter:card": summary
  "twitter:title": "Advent of YARV: Part 20"
  "twitter:description": "This post is part of a series about how the YARV virtual machine works."
  "twitter:site": "@kddnewton"
  "twitter:image": https://upload.wikimedia.org/wikipedia/commons/thumb/7/73/Ruby_logo.svg/1200px-Ruby_logo.svg.png
---

This blog series is about how the CRuby virtual machine works. If you're new to the series, I recommend starting from [the beginning](/2022/11/30/advent-of-yarv-part-0). This post is about catch tables.

At this point in the series we've looked at the instructions that implement most of the keywords in Ruby language. We've seen conditionals like `if` and `unless`, loops like `while` and `until`, declarations like `class`, `module`, and `def`, and many others. What we haven't seen yet are the keywords that correspond to control structures that deal with exceptions. This includes:

* `begin`
* `break`
* `else`
* `ensure`
* `next`
* `redo`
* `rescue`
* `retry`
* `return`

As it turns out, all of these keywords are implemented with a single instruction: `throw`. This very powerful instruction has a long history from the Java virtual machine, with some differences. To see how this all works, we need to talk about catch tables.

## Catch tables

Every instruction sequence that we've seen so far has a catch table attached to it. A catch table contains entries corresponding to different kinds of exceptions, and handles them accordingly. You can think of them roughly as an instruction sequence's `rescue` clause. Let's look at an example:

```ruby
begin
  foo
  true
rescue
  false
end
```

Consider the code above. When we execute the `send` corresponding to the `foo` method call, it could potentially raise an error. If it does, we want to jump directly to the `putobject` that corresponds to pushing the `false` onto the stack. This sounds similar to the instructions we introduced with branching, but requires something a little more powerful. Where before we were only branching within the current instruction sequence, now we can branch to a completely different instruction sequence. This is where catch tables come in.

```
== disasm: #<ISeq:<main>@test.rb:1 (1,0)-(6,3)> (catch: true)
== catch table
| catch type: rescue st: 0000 ed: 0006 sp: 0000 cont: 0007
| == disasm: #<ISeq:rescue in <main>@test.rb:4 (4,0)-(5,7)> (catch: true)
| local table (size: 1, argc: 0 [opts: 0, rest: -1, post: 0, block: -1, kw: -1@-1, kwrest: -1])
| [ 1] $!@0
| 0000 getlocal_WC_0                          $!@0                      (   5)
| 0002 putobject                              StandardError
| 0004 checkmatch                             3
| 0006 branchunless                           11
| 0008 putobject                              false[Li]
| 0010 leave
| 0011 getlocal_WC_0                          $!@0
| 0013 throw                                  0
| catch type: retry  st: 0006 ed: 0007 sp: 0000 cont: 0000
|------------------------------------------------------------------------
0000 putself                                                          (   2)[Li]
0001 opt_send_without_block                 <calldata!mid:foo, argc:0, FCALL|VCALL|ARGS_SIMPLE>
0003 pop
0004 putobject                              true                      (   3)[Li]
0006 nop                                                              (   1)
0007 leave                                                            (   3)
```

The code example above disassembles into the YARV instruction sequences seen here. You'll notice that the main instruction sequence has the statement `catch: true`. This indicates that there are entries in its catch table. In this case it has two entries: one for `rescue` and one for `retry`. A catch table entry has the following fields:

```c
struct iseq_catch_table_entry {
  enum rb_catch_type type;
  rb_iseq_t *iseq;

  unsigned int start;
  unsigned int end;
  unsigned int cont;
  unsigned int sp;
};
```

Each entry has a type, an optional instruction sequence pointer, and four integers. The integers indicate how the catch table entry should recover from the thrown error. The `start` and `end` fields indicate the range of instructions that the catch table entry applies to. The `cont` field indicates the instruction that should be executed after the catch table entry has been executed. The `sp` field indicates the stack pointer that should be used after the catch table entry has been executed. When the catch table entry is found to be applicable, the VM will jump to the instruction indicated by `cont` and set the stack pointer to the value indicated by `sp`.

If the catch table entry is a `rescue` or `ensure` type, then it has its own instruction sequence attached that should be executed. These entries will push a new frame (of `rescue` or `ensure` type) onto the stack frame to execute these instruction sequences.

If the catch table entry is a `break` type, then it will use the instruction sequence pointer to determine which frame to walk back to. This is used to implement the `break` keyword.

Other catch table entries will not have an instruction sequence pointer, and will just use their `cont` and `sp` fields to determine how to recover from the thrown error.

## Entries

Let's look at a couple of examples of catch table entries compiled into instruction sequences.

### `rescue`

In Ruby:

```ruby
begin
  foo
  true
rescue
  false
ensure
  cleanup
end
```

In YARV:

```
== disasm: #<ISeq:<main>@test.rb:1 (1,0)-(8,3)> (catch: true)
== catch table
| catch type: rescue st: 0000 ed: 0006 sp: 0000 cont: 0007
| == disasm: #<ISeq:rescue in <main>@test.rb:4 (4,0)-(5,7)> (catch: true)
| local table (size: 1, argc: 0 [opts: 0, rest: -1, post: 0, block: -1, kw: -1@-1, kwrest: -1])
| [ 1] $!@0
| 0000 getlocal_WC_0                          $!@0                      (   5)
| 0002 putobject                              StandardError
| 0004 checkmatch                             3
| 0006 branchunless                           11
| 0008 putobject                              false[Li]
| 0010 leave
| 0011 getlocal_WC_0                          $!@0
| 0013 throw                                  0
| catch type: retry  st: 0006 ed: 0007 sp: 0000 cont: 0000
| catch type: ensure st: 0000 ed: 0007 sp: 0001 cont: 0011
| == disasm: #<ISeq:ensure in <main>@test.rb:7 (7,2)-(7,9)> (catch: true)
| local table (size: 1, argc: 0 [opts: 0, rest: -1, post: 0, block: -1, kw: -1@-1, kwrest: -1])
| [ 1] $!@0
| 0000 putself                                                          (   7)[Li]
| 0001 opt_send_without_block                 <calldata!mid:cleanup, argc:0, FCALL|VCALL|ARGS_SIMPLE>
| 0003 pop
| 0004 getlocal_WC_0                          $!@0
| 0006 throw                                  0
|------------------------------------------------------------------------
0000 putself                                                          (   2)[Li]
0001 opt_send_without_block                 <calldata!mid:foo, argc:0, FCALL|VCALL|ARGS_SIMPLE>
0003 pop
0004 putobject                              true                      (   3)[Li]
0006 nop                                                              (   4)
0007 putself                                                          (   7)[Li]
0008 opt_send_without_block                 <calldata!mid:cleanup, argc:0, FCALL|VCALL|ARGS_SIMPLE>
0010 pop
0011 leave                                                            (   3)
```

This is the same example as above with the addition of the `ensure` clause. The catch table has a `rescue` entry that applies to the `putself` instruction up to the `nop` instruction. When an exception is caught it will execute the nested instruction sequence. That instruction sequence will check if the exception is a `StandardError` and if so, push `false` onto the stack and return. Otherwise, it will rethrow the exception.

### `retry`

You can see in the example that the catch table also has an entry for `retry`. This entry indicates that it only applies to the `nop` to `leave` instructions (so this won't actually happen). If it were to happen, it would jump back to the `putself` instruction at offset 0.

### `ensure`

There is also a catch table entry in the example above of the `ensure` type. It indicates that it applies from the `putself` up to the subsequent `putself`. This code will be executed even if an exception is raised.

### `break`

In Ruby:

```ruby
[1, 2, 3].each do |value|
  break if value == 2
end
```

In YARV:

```
== disasm: #<ISeq:<main>@test.rb:1 (1,0)-(3,3)> (catch: true)
== catch table
| catch type: break  st: 0000 ed: 0005 sp: 0000 cont: 0005
| == disasm: #<ISeq:block in <main>@test.rb:1 (1,15)-(3,3)> (catch: true)
| == catch table
| | catch type: redo   st: 0001 ed: 0014 sp: 0000 cont: 0001
| | catch type: next   st: 0001 ed: 0014 sp: 0000 cont: 0014
| |------------------------------------------------------------------------
| local table (size: 1, argc: 1 [opts: 0, rest: -1, post: 0, block: -1, kw: -1@-1, kwrest: -1])
| [ 1] value@0<Arg>
| 0000 nop                                                              (   1)[Bc]
| 0001 getlocal_WC_0                          value@0                   (   2)[Li]
| 0003 putobject                              2
| 0005 opt_eq                                 <calldata!mid:==, argc:1, ARGS_SIMPLE>[CcCr]
| 0007 branchunless                           13
| 0009 putnil
| 0010 throw                                  2
| 0012 leave                                                            (   3)[Br]
| 0013 putnil                                                           (   2)
| 0014 leave                                                            (   3)[Br]
|------------------------------------------------------------------------
0000 duparray                               [1, 2, 3]                 (   1)[Li]
0002 send                                   <calldata!mid:each, argc:0>, block in <main>
0005 leave
```

This example has a `break` entry in the catch table. This entry applies from the `nop` instruction to the `opt_eq` instruction. When the `break` is executed, it will jump to the `leave` instruction at offset 5 in the parent instruction sequence.

### `redo`

You can see that the nested instruction sequence used to pass to the `each` block also has its own catch table. This catch table has a `redo` entry that applies to the `getlocal` instruction up to the `leave` instruction. If a `redo` is executed, it will jump back to the `getlocal` instruction at offset 1.

### `next`

You can also see that the nested instruction sequence has a `next` entry in its catch table. It applies to the `getlocal` instruction up to the `leave` instruction. If a `next` is executed, it will jump to the `leave` instruction at offset 14.

## `nop`

You may have noticed that in a lot of the examples above, the `nop` instruction keeps showing up. This operation stands for "no operation" and quite literally does nothing. It has no operands, and neither pushes or pops from either the value or frame stack. It is purely there for padding to allow catch table entries a location to jump to.

## `throw`

Finally, now that we understand the background for the `throw` instruction, we can discuss the instruction itself. The `throw` instruction has a single operand which is a number. That number represents both the type of exception to throw and any flags compiled at that location (there is actually only one flag, which is `VM_THROW_NO_ESCAPE_FLAG`). It pops a single value off the stack which is the value being thrown. It then pushes the result of throwing the exception onto the stack.

The type of exception to throw loosely corresponds to the keyword that caused the instruction to be compiled. It is represented by an enum, with the mapping as follows:

```c
enum ruby_tag_type {
  RUBY_TAG_NONE = 0x0,
  RUBY_TAG_RETURN = 0x1,
  RUBY_TAG_BREAK = 0x2,
  RUBY_TAG_NEXT = 0x3,
  RUBY_TAG_RETRY = 0x4,
  RUBY_TAG_REDO = 0x5,
  RUBY_TAG_RAISE = 0x6,
  RUBY_TAG_THROW = 0x7,
  RUBY_TAG_FATAL = 0x8,
  RUBY_TAG_MASK = 0xf
}
```

To truly understand how this instruction works, you can use this enum to decode the kind of exception being thrown and then walk up the frame stack until you find a corresponding entry. The entry will tell you where to jump to. This is what the `vm_throw` function does in YARV.

## Wrapping up

In this post we talked about catch tables and the `nop` and `throw` instructions. We saw how Ruby implements error handling and recovering from errors. A couple of things to remember from this post:

* Catch tables are a set of recovery mechanisms that are attached to instruction sequences.
* YARV recovers from errors by walking up the frame stack until it finds a catch table entry that corresponds to the type of exception being thrown.
* The `throw` instruction pops a value off the stack and throws an exception with the given type.

In the next post we'll look at a very esoteric instruction used to implement some very esoteric syntax: the `once` instruction.
