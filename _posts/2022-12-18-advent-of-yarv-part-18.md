---
layout: post
title: Advent of YARV
subtitle: Part 18 - Super methods
meta:
  "twitter:card": summary
  "twitter:title": "Advent of YARV: Part 18"
  "twitter:description": "This post is part of a series about how the YARV virtual machine works."
  "twitter:site": "@kddnewton"
  "twitter:image": https://upload.wikimedia.org/wikipedia/commons/thumb/7/73/Ruby_logo.svg/1200px-Ruby_logo.svg.png
---

This blog series is about how the CRuby virtual machine works. If you're new to the series, I recommend starting from [the beginning](/2022/11/30/advent-of-yarv-part-0). This post is about super methods.

For the most part, invoking super methods is very similar to calling normal methods. In this way, `invokesuper` (the instruction used to invoke a super method) is very similar to `send`. There are, however, a couple of key differences.

Let's look at the definition of the `send`:

```c
/* invoke method. */
DEFINE_INSN
send
(CALL_DATA cd, ISEQ blockiseq)
(...)
(VALUE val)
// attr rb_snum_t sp_inc = sp_inc_of_sendish(cd->ci);
// attr rb_snum_t comptime_sp_inc = sp_inc_of_sendish(ci);
{
    VALUE bh = vm_caller_setup_arg_block(ec, GET_CFP(), cd->ci, blockiseq, false);
    val = vm_sendish(ec, GET_CFP(), cd, bh, mexp_search_method);

    if (val == Qundef) {
        RESTORE_REGS();
        NEXT_INSN();
    }
}
```

And now the `invokesuper` instruction:

```c
/* super(args) # args.size => num */
DEFINE_INSN
invokesuper
(CALL_DATA cd, ISEQ blockiseq)
(...)
(VALUE val)
// attr rb_snum_t sp_inc = sp_inc_of_sendish(cd->ci);
// attr rb_snum_t comptime_sp_inc = sp_inc_of_sendish(ci);
{
    VALUE bh = vm_caller_setup_arg_block(ec, GET_CFP(), cd->ci, blockiseq, true);
    val = vm_sendish(ec, GET_CFP(), cd, bh, mexp_search_super);

    if (val == Qundef) {
        RESTORE_REGS();
        NEXT_INSN();
    }
}
```

You'll notice they're incredibly similar. The two differences are the final argument to `vm_caller_setup_arg_block` which tells that function to forward the block handler if a block wasn't explicitly given, and the final argument to `vm_sendish` which tells that function how to search for the method to call.

## Explicit arguments

There are two ways to invoke super methods. If you pass any arguments or use parentheses, then Ruby assumes you are specifying the entire method signature. Let's look at an example:

```ruby
class Foo
  def perform(left, right)
    left + right
  end
end

class Bar < Foo
  def perform(left, right)
    super(left, right)
  end
end
```

The `Bar#perform` method disassembles to:

```
== disasm: #<ISeq:perform@test.rb:8 (8,2)-(10,5)> (catch: false)
local table (size: 2, argc: 2 [opts: 0, rest: -1, post: 0, block: -1, kw: -1@-1, kwrest: -1])
[ 2] left@0<Arg>[ 1] right@1<Arg>
0000 putself                                                          (   9)[LiCa]
0001 getlocal_WC_0                          left@0
0003 getlocal_WC_0                          right@1
0005 invokesuper                            <calldata!argc:2, FCALL|ARGS_SIMPLE|SUPER>, nil
0008 leave                                                            (  10)[Re]
```

You can see that the call data operand to `invokesuper` has the flag `SUPER` and an argument count of 2. This tells the VM that the method being invoked is a super method and that it has two arguments. The second operand is `nil`, since it has no block instruction sequence.

## Implicit arguments

The second way to invoke super methods is to use no parentheses or arguments. In these cases, Ruby assumes you are passing all of the same arguments as you received in the current method. For example:

```ruby
class Foo
  def perform(left, right)
    left + right
  end
end

class Bar < Foo
  def perform(left, right)
    super
  end
end
```

The `Bar#perform` method now disassembles to:

```
== disasm: #<ISeq:perform@test.rb:8 (8,2)-(10,5)> (catch: false)
local table (size: 2, argc: 2 [opts: 0, rest: -1, post: 0, block: -1, kw: -1@-1, kwrest: -1])
[ 2] left@0<Arg>[ 1] right@1<Arg>
0000 putself                                                          (   9)[LiCa]
0001 getlocal_WC_0                          left@0
0003 getlocal_WC_0                          right@1
0005 invokesuper                            <calldata!argc:2, FCALL|ARGS_SIMPLE|SUPER|ZSUPER>, nil
0008 leave                                                            (  10)[Re]
```

You can see the disassembly now includes the `ZSUPER` flag, which stands for "zero super". This tells the VM that no arguments were passed and to assume the behavior of forwarding all of the arguments.

## Wrapping up

In this post we covered the `invokesuper` instruction. We saw that it is effectively the same as the `send` instruction but with a different method lookup algorithm. A couple of things to remember from this post:

* Invoking super methods is effectively the same thing as a regular method call.
* There are two ways to invoke super methods: with explicit arguments or with implicit arguments.

In the next post we'll keep to the trend of looking at one instruction at a time and take a look at the `defined` instruction.
