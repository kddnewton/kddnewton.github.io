---
layout: post
title: Advent of YARV
subtitle: Part 17 - Method parameters
meta:
  "twitter:card": summary
  "twitter:title": "Advent of YARV: Part 17"
  "twitter:description": "This post is part of a series about how the YARV virtual machine works."
  "twitter:site": "@kddnewton"
  "twitter:image": https://upload.wikimedia.org/wikipedia/commons/thumb/7/73/Ruby_logo.svg/1200px-Ruby_logo.svg.png
---

This blog series is about how the CRuby virtual machine works. If you're new to the series, I recommend starting from [the beginning](/2022/11/30/advent-of-yarv-part-0). This post is about method parameters.

We touched briefly on method parameters when we talked about the `send` instruction, but only addressed how required positional parameters were implemented. Today we're going to dive into each parameter type in more detail. We'll see each of their expectations about the stack and how they're implemented in the virtual machine. As a part of this exploration, we'll also be introduced to two more instructions: `checkkeyword` and `invokeblock`. Let's dive in.

## Required positional parameters

Required positional parameters are the simplest type of parameter. They are also the most common. Let's look at an example:

```ruby
def add(left, right)
  left + right
end
```

When the method is called, the calling instruction sequence is responsible for ensuring that the order of the stack is the receiver of the method, then the value for the `left` parameter, then the value for the `right` parameter. The callee instruction sequence can then treat `left` and `right` as any other local and access them through `getlocal` and its specializations. Here's the disassembly:

```
== disasm: #<ISeq:<main>@test.rb:1 (1,0)-(3,3)> (catch: false)
0000 definemethod                           :add, add                 (   1)[Li]
0003 putobject                              :add
0005 leave

== disasm: #<ISeq:add@test.rb:1 (1,0)-(3,3)> (catch: false)
local table (size: 2, argc: 2 [opts: 0, rest: -1, post: 0, block: -1, kw: -1@-1, kwrest: -1])
[ 2] left@0<Arg>[ 1] right@1<Arg>
0000 getlocal_WC_0                          left@0                    (   2)[LiCa]
0002 getlocal_WC_0                          right@1
0004 opt_plus                               <calldata!mid:+, argc:1, ARGS_SIMPLE>[CcCr]
0006 leave                                                            (   3)[Re]
```

You can see the disassembly shows the local table has `argc: 2`. The rest of the parameter types are their default values, so this means we have two leading required positional parameters.

## Optional positional parameters

Optional positional parameters provide a default value if the caller does not provide one. Let's look at an example:

```ruby
def add(left = 0, right = 0)
  left + right
end
```

When optional positional parameters are present, the default values are encoded at the beginning of the instruction sequence. If the values are not provided, the instructions are executed to push the default values onto the stack. If they are provided, the instructions are skipped.

Each callsite for this method tracks the number of parameters that are being passed to the method and pass that along as metadata. The called instruction sequence uses that information to determine where to jump to to start the instruction sequence. For example:

```
== disasm: #<ISeq:<main>@test.rb:1 (1,0)-(3,3)> (catch: false)
0000 definemethod                           :add, add                 (   1)[Li]
0003 putobject                              :add
0005 leave

== disasm: #<ISeq:add@test.rb:1 (1,0)-(3,3)> (catch: false)
local table (size: 2, argc: 0 [opts: 2, rest: -1, post: 0, block: -1, kw: -1@-1, kwrest: -1])
[ 2] left@0<Opt=0>[ 1] right@1<Opt=3>
0000 putobject_INT2FIX_0_                                             (   1)
0001 setlocal_WC_0                          left@0
0003 putobject_INT2FIX_0_
0004 setlocal_WC_0                          right@1
0006 getlocal_WC_0                          left@0                    (   2)[LiCa]
0008 getlocal_WC_0                          right@1
0010 opt_plus                               <calldata!mid:+, argc:1, ARGS_SIMPLE>[CcCr]
0012 leave                                                            (   3)[Re]
```

In the above disassembly you see the instruction sequence knows it has two optional parameters in `opts: 2`. It lists them as  `left@0<Opt=0>` and `right@1<Opt=3>`. This means that if no parameters are passed, the instruction sequence should start executing at offset `0`. If only one parameter is passed, the instruction sequence should start executing at offset `3`. If both are passed, it knows to jump past both default value instructions and start executing at offset `6`.

## Rest positional parameters

Rest positional parameters are a way to capture all of the remaining positional parameters into an array. Let's look at an example:

```ruby
def add(value, *others)
  value + others.sum
end
```

When rest positional parameters are present, the method call setup code will create an array and push it onto the stack. The called instruction sequence will then use `getlocal` and its specializations to access the array. Here's the disassembly:

```
== disasm: #<ISeq:<main>@test.rb:1 (1,0)-(3,3)> (catch: false)
0000 definemethod                           :add, add                 (   1)[Li]
0003 putobject                              :add
0005 leave

== disasm: #<ISeq:add@test.rb:1 (1,0)-(3,3)> (catch: false)
local table (size: 2, argc: 1 [opts: 0, rest: 1, post: 0, block: -1, kw: -1@-1, kwrest: -1])
[ 2] value@0<Arg>[ 1] others@1<Rest>
0000 getlocal_WC_0                          value@0                   (   2)[LiCa]
0002 getlocal_WC_0                          others@1
0004 opt_send_without_block                 <calldata!mid:sum, argc:0, ARGS_SIMPLE>
0006 opt_plus                               <calldata!mid:+, argc:1, ARGS_SIMPLE>[CcCr]
0008 leave                                                            (   3)[Re]
```

You can see that `argc` is set to `1` because that's the minimum number of values required to call the method. The value of `rest` is set to `1` because that's the offset into the parameter list where the rest parameters start.

## Post positional parameters

When you have a rest positional parameter, you can optionally have required positional parameters after the rest that are called post positional parameters. For example:

```ruby
def add(*values, final)
  values.sum + final
end
```

When post positional parameters are present, the values before will be gathered up into an array and the values after will be pushed onto the stack. Here's the disassembly:

```
== disasm: #<ISeq:<main>@test.rb:1 (1,0)-(3,3)> (catch: false)
0000 definemethod                           :add, add                 (   1)[Li]
0003 putobject                              :add
0005 leave

== disasm: #<ISeq:add@test.rb:1 (1,0)-(3,3)> (catch: false)
local table (size: 2, argc: 0 [opts: 0, rest: 0, post: 1, block: -1, kw: -1@-1, kwrest: -1])
[ 2] values@0<Rest>[ 1] final@1<Post>
0000 getlocal_WC_0                          values@0                  (   2)[LiCa]
0002 opt_send_without_block                 <calldata!mid:sum, argc:0, ARGS_SIMPLE>
0004 getlocal_WC_0                          final@1
0006 opt_plus                               <calldata!mid:+, argc:1, ARGS_SIMPLE>[CcCr]
0008 leave                                                            (   3)[Re]
```

You can see it lists the number of `post` parameters as `1`.

## Required keyword parameters

Required keyword parameters are the simplest kind of keyword parameters. Here's an example:

```ruby
def add(left:, right:)
  left + right
end
```

The called instruction sequence expects that the keyword parameters will be present on the stack in the same order as they were declared in the method. This means that if you have a caller that does `add(right: 1, left: 2)` then the code that sets up the method call must performs a couple of swaps in memory. YARV does this by sorting the array of values and then copying them directly back onto the stack. Here's the disassembly:

```
== disasm: #<ISeq:<main>@test.rb:1 (1,0)-(3,3)> (catch: false)
0000 definemethod                           :add, add                 (   1)[Li]
0003 putobject                              :add
0005 leave

== disasm: #<ISeq:add@test.rb:1 (1,0)-(3,3)> (catch: false)
local table (size: 3, argc: 0 [opts: 0, rest: -1, post: 0, block: -1, kw: 2@2, kwrest: -1])
[ 3] left@0     [ 2] right@1    [ 1] ?@2
0000 getlocal_WC_0                          left@0                    (   2)[LiCa]
0002 getlocal_WC_0                          right@1
0004 opt_plus                               <calldata!mid:+, argc:1, ARGS_SIMPLE>[CcCr]
0006 leave                                                            (   3)[Re]
```

You can see that the `kw` value is set to `2@2` which means there are two keyword parameters and two are required. You can also see that there is a mysterious `?` local variable. This is a special local variable that is used to store the keyword argument hash.

## Optional keyword parameters

Optional keyword parameters are a way to provide a default value for a keyword parameter. Here's an example:

```ruby
def add(left: 0, right: 0)
  left + right
end
```

Note that the default value can be any expression at all, and it can make quite a difference in the compiled code. In the case above, the default values are both `0`. `0` (along with other small integers, floats, symbols, `true`/`false`/`nil`, and strings), can be embedded directly into the keyword argument hash. For example, here's the disassembly:

```
== disasm: #<ISeq:<main>@test.rb:1 (1,0)-(3,3)> (catch: false)
0000 definemethod                           :add, add                 (   1)[Li]
0003 putobject                              :add
0005 leave

== disasm: #<ISeq:add@test.rb:1 (1,0)-(3,3)> (catch: false)
local table (size: 3, argc: 0 [opts: 0, rest: -1, post: 0, block: -1, kw: 2@0, kwrest: -1])
[ 3] left@0     [ 2] right@1    [ 1] ?@2
0000 getlocal_WC_0                          left@0                    (   2)[LiCa]
0002 getlocal_WC_0                          right@1
0004 opt_plus                               <calldata!mid:+, argc:1, ARGS_SIMPLE>[CcCr]
0006 leave                                                            (   3)[Re]
```

If the default value is something that can't be embedded like a method call, then the called instruction sequence will need to have extra instructions to set up the keyword parameters. For example:

```ruby
def add(left: additive_identity, right: additive_identity)
  left + right
end
```

This disassembles to:

```
== disasm: #<ISeq:<main>@test.rb:1 (1,0)-(3,3)> (catch: false)
0000 definemethod                           :add, add                 (   1)[Li]
0003 putobject                              :add
0005 leave

== disasm: #<ISeq:add@test.rb:1 (1,0)-(3,3)> (catch: false)
local table (size: 3, argc: 0 [opts: 0, rest: -1, post: 0, block: -1, kw: 2@0, kwrest: -1])
[ 3] left@0     [ 2] right@1    [ 1] ?@2
0000 checkkeyword                           3, 0                      (   1)
0003 branchif                               10
0005 putself
0006 opt_send_without_block                 <calldata!mid:additive_identity, argc:0, FCALL|VCALL|ARGS_SIMPLE>
0008 setlocal_WC_0                          left@0
0010 checkkeyword                           3, 1
0013 branchif                               20
0015 putself
0016 opt_send_without_block                 <calldata!mid:additive_identity, argc:0, FCALL|VCALL|ARGS_SIMPLE>
0018 setlocal_WC_0                          right@1
0020 getlocal_WC_0                          left@0                    (   2)[LiCa]
0022 getlocal_WC_0                          right@1
0024 opt_plus                               <calldata!mid:+, argc:1, ARGS_SIMPLE>[CcCr]
0026 leave                                                            (   3)[Re]
```

Here we're taking a similar approach that we took for optional positional parameters. We're checking to see if a value was passed for the parameter. If it was, we'll skip past the instructions that set up the default value. Otherwise we'll execute the instructions to push the default value onto the stack. The instruction that checks if a value was passed for a keyword parameter is `checkkeyword`.

### `checkkeyword`

The `checkkeyword` instruction takes two operands. The first operand is the index in the local table for the keyword argument hash. This is the hash that we're going to use to look up the keywords that were passed at the callsite. It will be used to calculate an offset from the environment pointer like any other local. The second operand is the index in the list of keywords that this keyword corresponds to.

For example, in the above disassembly you see `checkkeyword 3, 0` which means check in the keyword arguments hash at index `3` for whether or not the keyword that corresponds to index `0` (`left` in this case) was passed. If it was, then push `true` onto the stack, otherwise push `false`.

## Rest keyword parameters

When the `**` operator is seen in the declaration for a method, you get a rest keyword parameter. This parameter will be a hash that contains all of the keyword arguments that were passed to the method that weren't explicitly declared. Here's an example:

```ruby
def add(**values)
  values.values.sum
end
```

Here's the disassembly:

```
== disasm: #<ISeq:<main>@test.rb:1 (1,0)-(3,3)> (catch: false)
0000 definemethod                           :add, add                 (   1)[Li]
0003 putobject                              :add
0005 leave

== disasm: #<ISeq:add@test.rb:1 (1,0)-(3,3)> (catch: false)
local table (size: 1, argc: 0 [opts: 0, rest: -1, post: 0, block: -1, kw: -1@-1, kwrest: 0])
[ 1] values@0<Kwrest>
0000 getlocal_WC_0                          values@0                  (   2)[LiCa]
0002 opt_send_without_block                 <calldata!mid:values, argc:0, ARGS_SIMPLE>
0004 opt_send_without_block                 <calldata!mid:sum, argc:0, ARGS_SIMPLE>
0006 leave                                                            (   3)[Re]
```

You can see that `kwrest` which is normally `-1` is `0`. This means that the rest keyword parameter is at index `0` in the list of arguments. It is up to the method call set up code to ensure that this hash is set up properly.

## Block parameters

Finally, we get to the last type of parameter: block parameters. For example:

```ruby
def add(&block)
  yield + 1
end
```

Here's the disassembly:

```
== disasm: #<ISeq:<main>@test.rb:1 (1,0)-(3,3)> (catch: false)
0000 definemethod                           :add, add                 (   1)[Li]
0003 putobject                              :add
0005 leave

== disasm: #<ISeq:add@test.rb:1 (1,0)-(3,3)> (catch: false)
local table (size: 1, argc: 0 [opts: 0, rest: -1, post: 0, block: 0, kw: -1@-1, kwrest: -1])
[ 1] block@0<Block>
0000 invokeblock                            <calldata!argc:0, ARGS_SIMPLE>(   2)[LiCa]
0002 putobject_INT2FIX_1_
0003 opt_plus                               <calldata!mid:+, argc:1, ARGS_SIMPLE>[CcCr]
0005 leave                                                            (   3)[Re]
```

You can see in the disassembly that `block` is set to `0` when it is normally `-1`. This means that the block argument is at index `0` in the list of arguments. It is up to the method call set up code to ensure that this block is set up properly.

There are two ways to invoke a block. We already saw the first way earlier in the series when we went over the `getblockparamproxy` instruction, which is to call `#call` directly on the block. The other way is through the `yield` keyword, as in this example. When you call `yield`, YARV will compile in the `invokeblock` instruction.

### `invokeblock`

The `invokeblock` instruction takes one operand, which is a call data structure. This instruction is remarkably similar to `opt_send_without_block` in that it is effectively invoking a method without a block. `invokeblock` will walk up the frame stack until it finds a `method` frame and then execute the instruction sequence associated with the block that originally invoked that frame. The result of the block invocation will be pushed onto the stack.

## Wrapping up

Today we looked at all of the different kinds of parameters that can be present on method calls. These declarations can also be found on blocks and lambdas. We looked at how each parameter is encoded into the instruction sequence and how the method call set up code ensures that the parameters are set up properly. A few things to remember from this post:

* Called methods expect the stack to line up to their parameter declarations. The method call set up code is responsible for ensuring that this is the case.
* When keyword arguments don't align with keyword parameters, the method call set up code will sort them in place and copy them back onto the stack.
* Optional arguments can be encoded as instructions added to the method body with branches around them to skip the default value setup if a value was passed.

In the next post we'll look at the last kind of method call: calling super methods.
