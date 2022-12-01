---
layout: post
title: Advent of YARV
subtitle: Part 1 - Pushing onto the stack
meta:
  "twitter:card": summary
  "twitter:title": "Advent of YARV: Part 1"
  "twitter:description": "This post is part of a series about how the YARV virtual machine works."
  "twitter:site": "@kddnewton"
  "twitter:image": https://upload.wikimedia.org/wikipedia/commons/thumb/7/73/Ruby_logo.svg/1200px-Ruby_logo.svg.png
---

This blog series is about how the CRuby virtual machine works. If you're new to the series, I recommend starting from [the beginning](/2022/11/28/advent-of-yarv-part-0). This post is about the virtual machine stack, and how to push values onto it.

The first thing to understand about YARV is that it is a [stack-based virtual machine](https://en.wikipedia.org/wiki/Stack_machine). This means that all values are stored on a stack, and all operations are performed on the stack. This is in contrast to a [register-based virtual machine](https://en.wikipedia.org/wiki/Register_machine), where values are stored in registers and operations are performed on registers. The main advantage of a stack-based virtual machine is that it is easier to implement and easier to JIT compile. The main disadvantage is that it is slower than a register-based virtual machine because it requires more memory accesses.

When we say stack, we mean a first-in, first-out data structure. In Ruby, it would be as if you had an array and you could only call the `Array#push` and `Array#pop` methods on it[^1]. The value stack is universal to the life of the program[^2]. This means there's a contract that when methods, blocks, or other structures are executed, they leave the stack as they found it (we'll talk more about this later).

I could fill this entire page with caveats, but let's just go ahead and dive in to save ourselves the headache. Below are your very first couple of instructions in the YARV instruction set.

- [putnil](#putnil)
- [putobject](#putobject)
- [putstring](#putstring)
- [duparray](#duparray)
- [duphash](#duphash)

## `putnil`

This is one of the simplest instructions in YARV. It pushes the value of `nil` onto the stack. Below are a couple of illustrations to show how this works. The outer boxes show the overall stack. The arrow points to the next empty slot to write in. Inner boxes represent values.

<div align="center">
  <img src="/assets/aoy/part1-putnil.svg" alt="putnil">
</div>

If this were translated into Ruby, it would look like:

```ruby
class PutNil
  def call(vm)
    vm.stack.push(nil)
  end
end
```

To see this instruction in context, you can disassemble `nil` by running `ruby --dump=insns -e 'nil'`:

```
== disasm: #<ISeq:<main>@-e:1 (1,0)-(1,3)> (catch: false)
0000 putnil                                                           (   1)[Li]
0001 leave
```

## `putobject`

This instruction is similar to `putnil`, but it pushes an arbitrary value onto the stack. The instruction itself will hold onto the value[^3]. The value that it holds is a value that can be known at compile-time. Compile-time is the time when the Ruby program is being compiled into bytecode from source. This is as opposed to runtime, when the program is being executed. Oftentimes we will say something is "known at compile-time" if it is a value that does not depend on anything dynamic (e.g., an array that holds only integers, not references to local variables). You'll see this instruction typically used when booleans, numbers, symbols, or frozen strings appear in your source.

<div align="center">
  <img src="/assets/aoy/part1-putobject.svg" alt="putobject">
</div>

If this were translated into Ruby, it would look like:

```ruby
class PutObject
  attr_reader :object

  def initialize(object)
    @object = object
  end

  def call(vm)
    vm.stack.push(object)
  end
end
```

To see this instruction in context, you can disassemble `5` by running `ruby --dump=insns -e '5'`:

```
== disasm: #<ISeq:<main>@-e:1 (1,0)-(1,1)> (catch: false)
0000 putobject                              5                         (   1)[Li]
0002 leave
```

Notice that in the second column, the 5 can be seen. In the disassembled output objects that appear after the name of the instruction are called operands. Operands are values that are used by the instruction to perform its operation. In this case, the operand is the value that is being pushed onto the stack.


### `putobject_INT2FIX_0_`

This instruction is a specialization of the `putobject` instruction. It gets created if you have the `operands_unification` compiler option turned on (which is on by default). It is used to push the number `0` onto the stack. It turns out that this is common enough to warrant its own instruction. YARV isn't saving anything in speed by doing this (you still have to write the value to the stack) but it saves on memory by having this instruction not have to have an operand because the operand is always `0`.

<div align="center">
  <img src="/assets/aoy/part1-putobject_INT2FIX_0_.svg" alt="putobject_INT2FIX_0_">
</div>

If this were translated into Ruby, it would look like:

```ruby
class PutObjectINT2FIX0
  def call(vm)
    vm.stack.push(0)
  end
end
```

To see this instruction in context, you can disassemble `0` by running `ruby --dump=insns -e '0'`:

```
== disasm: #<ISeq:<main>@-e:1 (1,0)-(1,1)> (catch: false)
0000 putobject_INT2FIX_0_                                             (   1)[Li]
0001 leave
```

Notice that there is no operand in the second column, which is the point of this instruction.

### `putobject_INT2FIX_1_`

This is the exact same thing as `putobject_INT2FIX_0_`, except that it pushes the integer `1` onto the stack.

<div align="center">
  <img src="/assets/aoy/part1-putobject_INT2FIX_1_.svg" alt="putobject_INT2FIX_1_">
</div>

If this were translated into Ruby, it would look like:

```ruby
class PutObjectINT2FIX1
  def call(vm)
    vm.stack.push(1)
  end
end
```

To see this instruction in context, you can disassemble `1` by running `ruby --dump=insns -e '1'`:

```
== disasm: #<ISeq:<main>@-e:1 (1,0)-(1,1)> (catch: false)
0000 putobject_INT2FIX_1_                                             (   1)[Li]
0001 leave
```

## `putstring`

This is yet another instruction that pushes an object onto the stack. This time, it pushes an unfrozen string. This is an important attribute: if the string is frozen this instruction will be replaced by a `putobject` instruction instead. This is because if you have a frozen string, you can push the same object onto the stack multiple times without having to worry about it being mutated. That also means that when the instruction is executed the string must be duplicated.

<div align="center">
  <img src="/assets/aoy/part1-putstring.svg" alt="putstring">
</div>

If this were translated into Ruby, it would look like:

```ruby
class PutString
  attr_reader :object

  def initialize(object)
    @object = object
  end

  def call(vm)
    vm.stack.push(object.dup)
  end
end
```

To see this instruction in context, you can disassemble `"foo"` by running `ruby --dump=insns -e '"foo"'`:

```
== disasm: #<ISeq:<main>@-e:1 (1,0)-(1,5)> (catch: false)
0000 putstring                              "foo"                     (   1)[Li]
0002 leave
```

## `duparray`

This instruction dups and pushes an array onto the stack. This instruction is typically used when you have an array literal in your source code whose values are all known at compile-time.

<div align="center">
  <img src="/assets/aoy/part1-duparray.svg" alt="duparray">
</div>

If this were translated into Ruby, it would look like:

```ruby
class DupArray
  attr_reader :object

  def initialize(object)
    @object = object
  end

  def call(vm)
    vm.stack.push(object.dup)
  end
end
```

To see this instruction in context, you can disassemble `[1, 2, 3]` by running `ruby --dump=insns -e '[1, 2, 3]'`:

```
== disasm: #<ISeq:<main>@-e:1 (1,0)-(1,9)> (catch: false)
0000 duparray                               [1, 2, 3]                 (   1)[Li]
0002 leave
```

## `duphash`

This instruction dups and pushes a hash onto the stack. This instruction is typically used when you have a hash literal in your source code whose values are all known at compile-time. In this way it is very similar to `duparray`.

<div align="center">
  <img src="/assets/aoy/part1-duphash.svg" alt="duphash">
</div>

If this were translated into Ruby, it would look like:

```ruby
class DupHash
  attr_reader :object

  def initialize(object)
    @object = object
  end

  def call(vm)
    vm.stack.push(object.dup)
  end
end
```

To see this instruction in context, you can disassemble `{ a: 1, b: 2, c: 3 }` by running `ruby --dump=insns -e '{ a: 1, b: 2, c: 3 }'`:

```
== disasm: #<ISeq:<main>@-e:1 (1,0)-(1,20)> (catch: false)
0000 duphash                                {:a=>1, :b=>2, :c=>3}     (   1)[Li]
0002 leave
```

## Wrapping up

There you have it! In this post we talked about the first five instructions (along with two specializations) of the YARV virtual machine. A couple of things to take away from this first foray into YARV:

* YARV is a stack-based virtual machine. This means instructions push and pop values from the stack to communicate with each other.
* Some instructions require operands. Operands are values known at compile-time that are passed into the instruction when it is first created. These operands are used to determine what the instruction does. The combination of an instruction and its operands effectively comprise a curried function.
* Some instructions exist as specializations of other instructions, typically to optimize for common cases. One such optimization is to remove the need for certain operands to save on memory (as with saw with `putobject_INT2FIX_0_`).
* The virtual machine has a contract such that it expects a frame to clean up after itself. If a value is going to be pushed, there should be an equivalent pop for it to be removed from the stack.

In the next post we'll talk about manipulating the values of the stack and why that's useful.

---

[^1]: _Some_ instructions will access values lower in the stack, but for the most part everything is accessed from the top.
[^2]: There has been work to make Ractors have their own value stack, but we're ignoring that work for now.
[^3]: Having the instruction sequence hold onto actual Ruby values means that they are responsible for marking those values for garbage collection. This can have an interesting impact on memory consumption as these values will live until the instruction sequence is collected. For more on how this can be bad, see here: [mikel/mail#1342](https://github.com/mikel/mail/issues/1342).
