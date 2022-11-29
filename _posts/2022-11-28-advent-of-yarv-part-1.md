---
layout: post
title: Advent of YARV
subtitle: Part 1 - Pushing onto the stack
---

This blog series is about how the CRuby virtual machine works. If you're new to the series, I recommend starting from [the beginning](/2022/11/28/advent-of-yarv-part-0). This post is about the virtual machine stack, and how to push values onto it.

The first thing to understand about YARV is that it is a [stack-based virtual machine](https://en.wikipedia.org/wiki/Stack_machine). This means that all values are stored on a stack, and all operations are performed on the stack. This is in contrast to a [register-based virtual machine](https://en.wikipedia.org/wiki/Register_machine), where values are stored in registers and operations are performed on registers. The main advantage of a stack-based virtual machine is that it is easier to implement and easier to JIT compile. The main disadvantage is that it is slower than a register-based virtual machine because it requires more memory accesses.

When we say stack, we mean a first-in, first-out data structure. In Ruby, it would be as if you had an array and you could only call the `Array#push` and `Array#pop` methods on it (this isn't strictly true, but we'll get into that later). The value stack is universal to the life of the program (if we ignore recent work on Ractors). This means there's a contract that when methods, blocks, or other structures are executed, they leave the stack as they found it (this will become important later).

I could continue filling this entire page with caveats, but let's just go ahead and dive in to save ourselves the headache. Below are your very first couple of instructions in the YARV instruction set.

- [putnil](#putnil)
- [putobject](#putobject)
- [putstring](#putstring)
- [duparray](#duparray)
- [duphash](#duphash)

## `putnil`

This is one of the simplest instructions in YARV. It pushes the value of `nil` onto the stack. Below are a couple of illustrations to show how this works. The outer boxes show the overall stack. The arrow points to the next empty slot to write in. Inner boxes represent values.

![putnil](/assets/aoy/part1-putnil.svg)

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

This instruction is similar to `putnil`, but it pushes an arbitrary value onto the stack. The instruction itself will hold onto the value (which means its the responsible of the instruction sequence to go and mark it for GC). The value that it holds is a value that can be known at compile-time. You'll see this instruction typically used when booleans, numbers, symbols, or frozen strings appear in your source.

![putobject](/assets/aoy/part1-putobject.svg)

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

![putobject_INT2FIX_0_](/assets/aoy/part1-putobject_INT2FIX_0.svg)

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

![putobject_INT2FIX_1_](/assets/aoy/part1-putobject_INT2FIX_1.svg)

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

This is yet another instruction that pushes an object onto the stack. This time, it pushes an unfrozen string. This is an important attribute: if the string is frozen this instruction will be replaced by `putobject` instructions instead. This is because if you have a frozen string, you can push the same object onto the stack multiple times without having to worry about it being mutated. For the instruction, that also means that when the instruction is executed the string must be duplicated.

![putstring](/assets/aoy/part1-putstring.svg)

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

![duparray](/assets/aoy/part1-duparray.svg)

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

![duphash](/assets/aoy/part1-duphash.svg)

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
* You can always disassemble Ruby source using CRuby by running `ruby --dump=insns`. This outputs disassembled instruction sequences that represent how the virtual machine will function internally. Over the course of this blog series, we'll explain each part of that disassembly so you'll understand what you're looking at in more depth. For now, focus mostly on the names of the instructions in the left-most column.

In the next post we'll talk about manipulating the values of the stack and why that's useful.