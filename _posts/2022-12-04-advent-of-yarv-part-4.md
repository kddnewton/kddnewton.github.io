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

This blog series is about how the CRuby virtual machine works. If you're new to the series, I recommend starting from [the beginning](/2022/11/30/advent-of-yarv-part-0). This post is about creating objects from the stack.

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

<div align="center">
  <img src="/assets/aoy/part4-newarray.svg" alt="newarray">
</div>

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

Very similar to the `newarray` instruction, the `newarraykwsplat` instruction also creates an array from the top values on the stack, with the additional detail that the last entry in the array is a hash that the `**` operator is being used on. This is used to create an array from the positional arguments and a hash from the keyword arguments. For example, with `newarraykwsplat 3`:

<div align="center">
  <img src="/assets/aoy/part4-newarraykwsplat.svg" alt="newarraykwsplat">
</div>

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

<div align="center">
  <img src="/assets/aoy/part4-newhash.svg" alt="newhash">
</div>

In Ruby:

```ruby
class NewHash
  attr_reader :number

  def initialize(number)
    @number = number
  end

  def call(vm)
    value = vm.stack.pop(number).each_slice(2).to_h
    vm.stack.push(value)
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

When a range has bounds that are not known at compile-time, the range is created at runtime with the top two values on the stack. (This is as opposed to when the values _are_ known, in which case the `putobject` instruction can be used.) The bounds are popped off the stack, and the resulting range is pushed on. A flag is also given as an operand, which indicates if the range includes or excludes the upper bound. For example with `newrange 0`:

<div align="center">
  <img src="/assets/aoy/part4-newrange.svg" alt="newrange">
</div>

In Ruby:

```ruby
class NewRange
  attr_reader :exclude_end

  def initialize(exclude_end)
    @exclude_end = exclude_end
  end

  def call(vm)
    lower, upper = vm.stack.pop(2)
    vm.stack.push(Range.new(lower, upper, exclude_end == 1))
  end
end
```

In `foo..bar` disassembly:

```
== disasm: #<ISeq:<main>@-e:1 (1,0)-(1,8)> (catch: false)
0000 putself                                                          (   1)[Li]
0001 opt_send_without_block                 <calldata!mid:foo, argc:0, FCALL|VCALL|ARGS_SIMPLE>
0003 putself
0004 opt_send_without_block                 <calldata!mid:bar, argc:0, FCALL|VCALL|ARGS_SIMPLE>
0006 newrange                               0
0008 leave
```

## `toregexp`

When a regular expression contains values that are not known at compile-time (for example, any kind of interpolation), the regular expression gets created at runtime with a variable number of values on the top of the stack. (This is as opposed to when the values _are_ known, in which case the `putobject` instruction can be used.) The instruction accepts two operands. The first is an integer that represents the options that will be passed to the regular expression when it is constructed (e.g., case insensitivity, multiline mode, etc.). The second is an integer that represents the number of values to pop off the stack and join together. For example, with `toregexp 0, 3`:

<div align="center">
  <img src="/assets/aoy/part4-toregexp.svg" alt="toregexp">
</div>

In Ruby:

```ruby
class ToRegExp
  attr_reader :options, :length

  def initialize(options, length)
    @options = options
    @length = length
  end

  def call(vm)
    parts = vm.stack.pop(length)
    vm.stack.push(Regexp.new(parts.join, options))
  end
end
```

In `/foo #{bar} baz/i` disassembly:

```
== disasm: #<ISeq:<main>@-e:1 (1,0)-(1,17)> (catch: false)
0000 putobject                              "foo "                    (   1)[Li]
0002 putself
0003 opt_send_without_block                 <calldata!mid:bar, argc:0, FCALL|VCALL|ARGS_SIMPLE>
0005 dup
0006 objtostring                            <calldata!mid:to_s, argc:0, FCALL|ARGS_SIMPLE>
0008 anytostring
0009 putobject                              " baz"
0011 toregexp                               1, 3
0014 leave
```

## `concatarray`

When the `*` operator is used to splat an object into an array literal, the object is converted to an array and then concatenated with the array literal. All of the elements that occur before the `*` operator are used will first be converted into an array using the `newarray` or `duparray` instruction. Then, once that array is on the stack, the object that the `*` is being used on will be pushed onto the stack. Then the `concatarray` instruction will be used. `concatarray` will pop both the array and the object off the stack, and then push the result of concatenating the two.

If the object is not already an array, then it will be converted into an array using the `#to_a` method. If the `#to_a` method doesn't return an array, then it will raise a `TypeError`.

<div align="center">
  <img src="/assets/aoy/part4-concatarray.svg" alt="concatarray">
</div>

In Ruby:

```ruby
class ConcatArray
  def call(vm)
    array, object = vm.stack.pop(2)
    vm.stack.push([*array, *object])
  end
end
```

In `[foo, bar, *baz]` disassembly:

```
== disasm: #<ISeq:<main>@-e:1 (1,0)-(1,16)> (catch: false)
0000 putself                                                          (   1)[Li]
0001 opt_send_without_block                 <calldata!mid:foo, argc:0, FCALL|VCALL|ARGS_SIMPLE>
0003 putself
0004 opt_send_without_block                 <calldata!mid:bar, argc:0, FCALL|VCALL|ARGS_SIMPLE>
0006 newarray                               2
0008 putself
0009 opt_send_without_block                 <calldata!mid:baz, argc:0, FCALL|VCALL|ARGS_SIMPLE>
0011 concatarray
0012 leave
```

## `concatstrings`

The `concatstrings` instruction is very similar to the `toregexp` instruction, in that it pops a number of values off the top of the stack and joins them into a string. This instruction is only used when the string contains interpolation. If it does not, the `putstring` instruction is used when the string is not frozen and the `putobject` instruction is used when it is. The instruction accepts one operand, which is the number of values to pop off the stack and join together. For example, with `concatstrings 3`:

<div align="center">
  <img src="/assets/aoy/part4-concatstrings.svg" alt="concatstrings">
</div>

In Ruby:

```ruby
class ConcatStrings
  attr_reader :number

  def initialize(number)
    @number = number
  end

  def call(vm)
    vm.stack.push(vm.stack.pop(number).join)
  end
end
```

In `"foo #{bar} baz"` disassembly:

```
== disasm: #<ISeq:<main>@-e:1 (1,0)-(1,16)> (catch: false)
0000 putobject                              "foo "                    (   1)[Li]
0002 putself
0003 opt_send_without_block                 <calldata!mid:bar, argc:0, FCALL|VCALL|ARGS_SIMPLE>
0005 dup
0006 objtostring                            <calldata!mid:to_s, argc:0, FCALL|ARGS_SIMPLE>
0008 anytostring
0009 putobject                              " baz"
0011 concatstrings                          3
0013 leave
```

## Wrapping up

There you have it. That's seven more instructions that we've discussed in the YARV instruction set. All of these instructions pop a number of values off the stack and combine them into a resulting object that is then pushed back onto the stack. Here are some things to remember from this post:

* There is a big different in the instructions selected when objects are known at compile-time versus when they are not. When you use frozen strings, for instance, a lot of the instructions seen in this post will be replaced by more efficient versions. This was one of the motivations for the `frozen_string_literal` pragma.
* A lot of these instructions are replacements for constructors. For example, `newarray` could be replaced by a `duparray` instruction and then a series of `opt_ltlt` instructions. `newrange` could be replaced with a single `send` instruction. However, these instructions are more efficient because they don't require a method call.

In the next post we'll talk about five instructions that take the top object on the stack and change its type.
