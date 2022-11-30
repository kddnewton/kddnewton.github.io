---
layout: post
title: Advent of YARV
subtitle: Part 4 - Creating objects from the stack
meta:
  "twitter:card": summary
  "twitter:title": "Advent of YARV: Part 4"
  "twitter:description": "This post is part of a series about how the YARV virtual machine works."
  "twitter:site": "@kddnewton"
  "twitter:image": https://upload.wikimedia.org/wikipedia/commons/thumb/7/73/Ruby_logo.svg/1200px-Ruby_logo.svg.png
---

This blog series is about how the CRuby virtual machine works. If you're new to the series, I recommend starting from [the beginning](/2022/11/28/advent-of-yarv-part-0). This post is about creating objects from the stack.

There are many instructions that take multiple values from the top of the stack and combine them in some way. This can be done to create various primitive objects such as arrays, hashes, ranges, regular expressions, and strings.

Here are the instructions that create objects from the stack:

- [newarray](#newarray)
- [newarraykwsplat](#newarraykwsplat)
- [newhash](#newhash)
- [newrange](#newrange)
- [toregexp](#toregexp)
- [concatarray](#concatarray)
- [concatstrings](#concatstrings)

## `newarray`

When an array contains values that are not known at compile-time, the array is created at runtime from the values on the top of the stack. (This is as opposed to the `duparray` instruction we introduced earlier where all of the values are known at compile-time.) This instruction takes the number of values to pop off the stack and creates an array from them. For example, with `newarray 3`:

![newarray](/assets/aoy/part4-newarray.svg)

In Ruby:

```ruby
class NewArray
  attr_reader :number

  def initialize(number)
    @number = number
  end

  def call(vm)
    vm.stack.push(vm.stack.pop(number))
  end
end
```

In `[foo, bar, baz]` disassembly:

```
== disasm: #<ISeq:<main>@-e:1 (1,0)-(1,15)> (catch: false)
0000 putself                                                          (   1)[Li]
0001 opt_send_without_block                 <calldata!mid:foo, argc:0, FCALL|VCALL|ARGS_SIMPLE>
0003 putself
0004 opt_send_without_block                 <calldata!mid:bar, argc:0, FCALL|VCALL|ARGS_SIMPLE>
0006 putself
0007 opt_send_without_block                 <calldata!mid:baz, argc:0, FCALL|VCALL|ARGS_SIMPLE>
0009 newarray                               3
0011 leave
```

## `newarraykwsplat`

Very similar to the `newarray` instruction, the `newarraykwsplat` instruction also creates an array from the top values on the stack, with the additional detail that the last value on the stack is a hash that the `**` operator is being used on. This is used to create an array from the positional arguments and a hash from the keyword arguments. For example, with `newarraykwsplat 3`:

![newarraykwsplat](/assets/aoy/part4-newarraykwsplat.svg)

In Ruby:

```ruby
class NewArrayKwSplat
  attr_reader :number

  def initialize(number)
    @number = number
  end

  def call(vm)
    vm.stack.push(vm.stack.pop(number))
  end
end
```

In `[1, 2, **{ foo: "bar" }]` disassembly:

```
== disasm: #<ISeq:<main>@-e:1 (1,0)-(1,24)> (catch: false)
0000 putobject_INT2FIX_1_                                             (   1)[Li]
0001 putobject                              2
0003 putspecialobject                       1
0005 newhash                                0
0007 putobject                              :foo
0009 putstring                              "bar"
0011 newhash                                2
0013 opt_send_without_block                 <calldata!mid:core#hash_merge_kwd, argc:2, ARGS_SIMPLE>
0015 newarraykwsplat                        3
0017 leave
```

## `newhash`

When a hash contains values that are not known at compile-time, the hash is created at runtime from the values on the top of the stack. (This is as opposed to the `duphash` instruction we introduced earlier where all of the values are known at compile-time.) This instruction takes the number of values to pop off the stack and creates a hash from them. The number will always be even, since it transforms them into key-value pairs. For example, with `newhash 4`:

![newhash](/assets/aoy/part4-newhash.svg)

In Ruby:

```ruby
class NewHash
  attr_reader :number

  def initialize(number)
    @number = number
  end

  def call(vm)
    values = vm.stack.pop(number)
    cimbined = values.each_slice(2).to_h
    vm.stack.push(combined)
  end
end
```

In `{ foo: foo, bar: bar }` disassembly:

```
== disasm: #<ISeq:<main>@-e:1 (1,0)-(1,22)> (catch: false)
0000 putobject                              :foo                      (   1)[Li]
0002 putself
0003 opt_send_without_block                 <calldata!mid:foo, argc:0, FCALL|VCALL|ARGS_SIMPLE>
0005 putobject                              :bar
0007 putself
0008 opt_send_without_block                 <calldata!mid:bar, argc:0, FCALL|VCALL|ARGS_SIMPLE>
0010 newhash                                4
0012 leave
```

## `newrange`

newrange - creates a new range from the top 2 elements on the stack

## `toregexp`

toregexp - creates a new regexp from the top n elements on the stack

## `concatarray`

concatarray - concatenates the top two values of the stack into an array

## `concatstrings`

concatstrings - concatenates the top n strings on the stack

## Wrapping up
