---
layout: post
title: Advent of YARV
subtitle: Part 5 - Changing object types on the stack
meta:
  "twitter:card": summary
  "twitter:title": "Advent of YARV: Part 5"
  "twitter:description": "This post is part of a series about how the YARV virtual machine works."
  "twitter:site": "@kddnewton"
  "twitter:image": https://upload.wikimedia.org/wikipedia/commons/thumb/7/73/Ruby_logo.svg/1200px-Ruby_logo.svg.png
---

This blog series is about how the CRuby virtual machine works. If you're new to the series, I recommend starting from [the beginning](/2022/11/30/advent-of-yarv-part-0). This post is about changing object types on the stack.

There are occasions where the use of particular syntax results in the need for a specific type of object. For example, when you're interpolating an object into a string, you need to convert the object to a string. When you're creating a list of symbols, you need to convert the elements into symbols. There are five instructions that are used to convert objects to other types in response to syntax:

- [objtostring](#objtostring)
- [anytostring](#anytostring)
- [intern](#intern)
- [expandarray](#expandarray)
- [splatarray](#splatarray)

## Call data

As a quick aside before we jump into the instructions, we need to first talk about calldata structs. We're about to see our first instruction that uses a calldata struct, and we need to understand what they are before we can understand how the instructions work. Call data structs represent all of the information of a specific call site (a place in source where a method is called). It contains the following fields:

* `mid`: The name of the method to call. `mid` stands for "method ID" (`ID` is the internal symbol name used for a Ruby symbol).
* `argc`: The number of arguments being passed to the method.[^1]
* `flags`: A set of boolean flags stored in a bitmap that provide metadata about the call site. Those flags include:
  * `VM_CALL_ARGS_SPLAT` - indicates that positional arguments were using the `*` operator
  * `VM_CALL_ARGS_BLOCKARG` - indicates that a block was passed through the `&` operator
  * `VM_CALL_FCALL` - indicates that a method was called without an explicit receiver
  * `VM_CALL_VCALL` - indicates that a method was called without any arguments or parentheses
  * `VM_CALL_ARGS_SIMPLE` - indicates that no splat, block argument, block, or keyword was given at a call site
  * `VM_CALL_BLOCKISEQ` - indicates that a call site specifies a block using braces or keywords
  * `VM_CALL_KWARG` - indicates that a call site specifies keyword arguments
  * `VM_CALL_KW_SPLAT` - indicates that a call site specifies keyword arguments using the `**` operator
  * `VM_CALL_TAILCALL` - indicates that a call site is using the tail call optimization[^2]
  * `VM_CALL_SUPER` - indicates that the method being called is the super method
  * `VM_CALL_ZSUPER` - indicates that the method being called is the super method and no arguments were passed, meaning the arguments from the current method should be used
  * `VM_CALL_OPT_SEND` - an internal flag used by `BasicObject#__send__` and `Kernel#send`
  * `VM_CALL_KW_SPLAT_MUT` - a specialization of `KW_SPLAT` where it can be modified because it was just allocated
* `kwarg`: An array of symbols indicating which keyword arguments were found at the call site.

These objects are established while the instruction sequences are being compiled, and then referenced while the instruction sequences are being executed.

## `objtostring`

When an object is being interpolated[^3], the object is converted to a string using the `objtostring` instruction. This instruction takes the object from the top of the stack and replaces it with the string representation of the object by calling `#to_s` on it. Because it's an instruction that's calling a method, it takes a calldata operand.

<div align="center">
  <img src="/assets/aoy/part5-objtostring.svg" alt="objtostring">
</div>

In Ruby:

```ruby
class ObjToString
  attr_reader :calldata

  def initialize(calldata)
    @calldata = calldata
  end

  def call(vm)
    vm.stack.push(vm.stack.pop.to_s)
  end
end
```

In `"foo #{bar}"` disassembly:

```
== disasm: #<ISeq:<main>@-e:1 (1,0)-(1,12)> (catch: false)
0000 putobject                              "foo "                    (   1)[Li]
0002 putself
0003 opt_send_without_block                 <calldata!mid:bar, argc:0, FCALL|VCALL|ARGS_SIMPLE>
0005 dup
0006 objtostring                            <calldata!mid:to_s, argc:0, FCALL|ARGS_SIMPLE>
0008 anytostring
0009 concatstrings                          2
0011 leave
```

## `anytostring`

When `#to_s` is called on an object, the method could potentially have been defined by a developer to return something that is not a string. That's where the `anytostring` instruction comes in. `anytostring` pops two objects off the stack. The first object is the object that was returned from the `#to_s` call in the `objtostring` instruction. The second object is the original object that was being converted to a string. If the first object is a string, it's pushed back onto the stack. If it's not a string, the second object is converted into a string internally and pushed onto the stack.[^4]

<div align="center">
  <img src="/assets/aoy/part5-anytostring.svg" alt="anytostring">
</div>

In Ruby:

```ruby
class AnyToString
  def call(vm)
    original, value = vm.pop(2)

    if value.is_a?(String)
      vm.push(value)
    else
      vm.push("#<#{original.class.name}>")
    end
  end
end
```

In `"foo #{bar}"` disassembly:

```
== disasm: #<ISeq:<main>@-e:1 (1,0)-(1,12)> (catch: false)
0000 putobject                              "foo "                    (   1)[Li]
0002 putself
0003 opt_send_without_block                 <calldata!mid:bar, argc:0, FCALL|VCALL|ARGS_SIMPLE>
0005 dup
0006 objtostring                            <calldata!mid:to_s, argc:0, FCALL|ARGS_SIMPLE>
0008 anytostring
0009 concatstrings                          2
0011 leave
```

## `intern`

There are two ways to convert objects into symbols in Ruby that involve syntax and not method calls. Those are through dynamic symbols (e.g., `:"#{foo}"`) and symbol lists (e.g., `%I[foo #{bar} baz]`). In these cases, the `intern` instruction is used to convert the object into a symbol. This instruction pops an object off the stack and pushes its symbol representation back on. The object being popped is always a string, by virtue of the sequence of instructions (this always follows `anytostring` or `concatstrings`, which as we know always leave strings on the top of the stack).

<div align="center">
  <img src="/assets/aoy/part5-intern.svg" alt="intern">
</div>

In Ruby:

```ruby
class Intern
  def call(vm)
    vm.push(vm.stack.pop.intern)
  end
end
```

In `%I[foo #{bar}]` disassembly:

```
== disasm: #<ISeq:<main>@-e:1 (1,0)-(1,14)> (catch: false)
0000 putobject                              :foo                      (   1)[Li]
0002 putobject                              ""
0004 putself
0005 opt_send_without_block                 <calldata!mid:bar, argc:0, FCALL|VCALL|ARGS_SIMPLE>
0007 dup
0008 objtostring                            <calldata!mid:to_s, argc:0, FCALL|ARGS_SIMPLE>
0010 anytostring
0011 concatstrings                          2
0013 intern
0014 newarray                               2
0016 leave
```

## `expandarray`

When multiple assignment is used in Ruby, the values on the right side of the assignment need to be spread out to be assigned to the variables on the left side. This is done using the `expandarray` instruction. This instruction pops a single value off the stack, converts it to an array if it isn't already one using the `#to_ary` method, and then pushes the values from the array back onto the stack. The number of values pushed back onto the stack is determined by the first operand. If there aren't enough values in the array, `nil` is pushed onto the stack for each missing value. There is additionally a flag to indicate if the assignment used a `*` operator and if the array needs to be in reverse order because of the order of assignment targets.

<div align="center">
  <img src="/assets/aoy/part5-expandarray.svg" alt="expandarray">
</div>

In Ruby:

```ruby
class ExpandArray
  attr_reader :number, :flags

  def initialize(number, flags)
    @number = number
    @flags = flags
  end

  def call(vm)
    array = Array(vm.stack.pop).dup

    splat = flags & 0x01 > 0
    postarg = flags & 0x02 > 0

    if number + (splat ? 1 : 0) == 0
      # no space left on stack
    elsif postarg
      # post: ..., nil ,ary[-1], ..., ary[0..-num] # top

      # If there are not enough values in the array, nil is pushed onto the
      # stack for each of the missing values.
      if number > array.size
        (number - array.size).times { vm.stack.push(nil) }
      end

      # Now, push on each of the values from the array, starting from the end.
      [number, array.size].min.times { vm.stack.push(array.pop) }

      # Finally, if there is a splat, push the remaining values from the array
      # onto the stack as a single array.
      vm.stack.push(array) if splat
    else
      # normal: ary[num..-1], ary[num-2], ary[num-3], ..., ary[0] # top

      # First, build up an array of values that correspond to the number of
      # values that are expected on the stack.
      values = []
      [number, array.size].min.times { values.push(array.shift) }

      # Now, if there aren't enough values from the array, append on enough nils
      # to fill the required amount.
      if number > values.size
        (number - values.size).times { values.push(nil) }
      end

      # Push on the remaining values from the array if there is a splat.
      values.push(array) if splat

      # Finally, push on the values from the array in reverse order.
      values.reverse_each { |item| vm.stack.push(item) }
    end
  end
end
```

In `foo, *bar = 1, 2, 3` disassembly:

```
== disasm: #<ISeq:<main>@-e:1 (1,0)-(1,19)> (catch: false)
local table (size: 2, argc: 0 [opts: 0, rest: -1, post: 0, block: -1, kw: -1@-1, kwrest: -1])
[ 2] foo@0      [ 1] bar@1
0000 duparray                               [1, 2, 3]                 (   1)[Li]
0002 dup
0003 expandarray                            1, 1
0006 setlocal_WC_0                          foo@0
0008 setlocal_WC_0                          bar@1
0010 leave
```

## `splatarray`

When the `*` operator is used to splat an object (for example into an assignment, an array literal, or a method call), the `splatarray` instruction is used. Its responsibility is to convert the object into an array if it isn't already one using the `#to_a` method. If the object is already an array, it is left as is. If the object is not an array, it is converted into an array with a single element. The resulting array is then pushed back onto the stack. This instruction also accepts a single operand that indicates whether or not the object needs to be duplicated before being converted into an array.

<div align="center">
  <img src="/assets/aoy/part5-splatarray.svg" alt="splatarray">
</div>

In Ruby:

```ruby
class SplatArray
  attr_reader :flag

  def initialize(flag)
    @flag = flag
  end

  def call(vm)
    top_of_stack = vm.stack.pop
    value = top_of_stack.is_a?(Array) ? top_of_stack : top_of_stack.to_a

    vm.stack.push(flag > 0 ? value.dup : value)
  end
end
```

In `foo(*bar)` disassembly:

```
== disasm: #<ISeq:<main>@-e:1 (1,0)-(1,9)> (catch: false)
0000 putself                                                          (   1)[Li]
0001 putself
0002 opt_send_without_block                 <calldata!mid:bar, argc:0, FCALL|VCALL|ARGS_SIMPLE>
0004 splatarray                             false
0006 opt_send_without_block                 <calldata!mid:foo, argc:1, ARGS_SPLAT|FCALL>
0008 leave
```

## Wrapping up

In this post, we looked at the instructions that are used to change the type of object on the top of the stack in response to the use of specific syntax. Some things to remember from this post:

* Call data are operands that gets retained by instructions that perform method calls. They contain all of the information pertaining to the caller.
* There are a lot of cases where Ruby syntax will require a change of type. Sometimes this results in method calls like `#to_s` or `#to_a`. (You can see a list of these kinds of implicit conversions in a [blog post](https://kddnewton.com/2021/09/09/ruby-type-conversion.html) I wrote last year.)

In the next post, we will look at just one instruction: `send`. This instruction is used to perform almost all method calls in Ruby, and warrants its own post entirely.

---

[^1]: An important distinction here needs to be made that this is the number of arguments _being passed_, not necessarily the number the called method expects.
[^2]: [Tail calls](https://en.wikipedia.org/wiki/Tail_call) are a way of optimizing recursive functions by not creating a new frame for each call. Instead, the frame is reused. This is possible because the return value of a function is the last thing that happens in the function. In Ruby, we only see tail calls when we either are calling a method on a block object that we specify as a parameter using the `&` operator or when arguments are getting forwarded using the `...` operator.
[^3]: There are a surprising number of pieces of syntax that support interpolation. There are of course string literals, but also dynamic symbols, regular expressions, heredocs, and command strings.
[^4]: Any time you interpolate an object both `objtostring` and `anytostring` will be added to the instruction sequence. This gets into a discussion beyond the scope of this blog series but that is interesting to consider: do you have more, less complicated instructions that potentially take up more space or do you have fewer, more complicated instructions that take up less space?
