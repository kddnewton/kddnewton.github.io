---
layout: post
title: Advent of YARV
subtitle: Part 9 - Local variables (2)
meta:
  "twitter:card": summary
  "twitter:title": "Advent of YARV: Part 9"
  "twitter:description": "This post is part of a series about how the YARV virtual machine works."
  "twitter:site": "@kddnewton"
  "twitter:image": https://upload.wikimedia.org/wikipedia/commons/thumb/7/73/Ruby_logo.svg/1200px-Ruby_logo.svg.png
---

This blog series is about how the CRuby virtual machine works. If you're new to the series, I recommend starting from [the beginning](/2022/11/30/advent-of-yarv-part-0). This post is the second of three posts about local variables.

In the previous post we introduced the concept of local variables, and showed how they are stored in the value stack. We showed how they relate to environment pointers by a negative offset, and can be read or written through parent frames using the `getlocal` and `setlocal` instructions.

There are three more instructions that function extremely similarly to `getlocal` and `setlocal`, except that they deal with a special kind of local variable: a block parameter. Block parameters are local variables that were declared as a block parameter to the current method. For example:

```ruby
def foo(&block)
end
```

In the previous example, `block` is a block parameter. It has a slot in the value stack in the same way as a normal local variable, except that it is lazily evaluated. The VM wants to do everything it can to avoid having to allocate a `Proc` object, which the block will be converted into if it is ever used. To better illustrate this, let's dive into the three instructions that we're discussing today that have to do with accessing block locals.

* [getblockparam](#getblockparam)
* [getblockparamproxy](#getblockparamproxy)
* [setblockparam](#setblockparam)

## `getblockparam`

`getblockparam` looks exactly the same as `getlocal` on the surface. It has two operands: the index and level of the local variable it is accessing. Its goal is to push the value of the local variable at the given index and level onto the value stack. The difference is that it is only used to access block parameters, and it will lazily evaluate the block parameter if it has not been evaluated yet.

First, let's take a look at the code that describes how to implement the `getlocal` instruction:

```c
/* Get local variable (pointed by `idx' and `level').
     'level' indicates the nesting depth from the current block.
 */
DEFINE_INSN
getlocal
(lindex_t idx, rb_num_t level)
()
(VALUE val)
{
    const VALUE *ep = vm_get_ep(GET_EP(), level);
    val = *(ep - idx);
    RB_DEBUG_COUNTER_INC(lvar_get);
    (void)RB_DEBUG_COUNTER_INC_IF(lvar_get_dynamic, level > 0);
}
```

For the purposes of this post, you can ignore all but the first two lines of the body of the function. It's performing the negative offset that we discussed to access the local, then setting that value to `val` which will be pushed onto the value stack.

Now, let's take a look at the code that describes how to implement the `getblockparam` instruction:

```c
/* Get a block parameter. */
DEFINE_INSN
getblockparam
(lindex_t idx, rb_num_t level)
()
(VALUE val)
{
    const VALUE *ep = vm_get_ep(GET_EP(), level);
    VM_ASSERT(VM_ENV_LOCAL_P(ep));

    if (!VM_ENV_FLAGS(ep, VM_FRAME_FLAG_MODIFIED_BLOCK_PARAM)) {
        val = rb_vm_bh_to_procval(ec, VM_ENV_BLOCK_HANDLER(ep));
        vm_env_write(ep, -(int)idx, val);
        VM_ENV_FLAGS_SET(ep, VM_FRAME_FLAG_MODIFIED_BLOCK_PARAM);
    }
    else {
        val = *(ep - idx);
        RB_DEBUG_COUNTER_INC(lvar_get);
        (void)RB_DEBUG_COUNTER_INC_IF(lvar_get_dynamic, level > 0);
    }
}
```

Does this look familiar? It should! It's almost identical to the `getlocal` instruction. Here's a diff to help show the differences:

```diff
5c3
< getlocal
---
> getblockparam
10a9,16
>     VM_ASSERT(VM_ENV_LOCAL_P(ep));
> 
>     if (!VM_ENV_FLAGS(ep, VM_FRAME_FLAG_MODIFIED_BLOCK_PARAM)) {
>         val = rb_vm_bh_to_procval(ec, VM_ENV_BLOCK_HANDLER(ep));
>         vm_env_write(ep, -(int)idx, val);
>         VM_ENV_FLAGS_SET(ep, VM_FRAME_FLAG_MODIFIED_BLOCK_PARAM);
>     }
>     else {
13a20
>     }
```

The only difference is that it checks if the block parameter has been reified into a `Proc` yet. If it has not, it will reify it using the `rb_vm_bh_to_procval` function and store the result in the local variable slot. If it has, it will just read the value from the local variable slot. For example, with an unreified block parameter and `getblockparam 0, 0`:

<div align="center">
  <img src="/assets/aoy/part9-getblockparam.svg" alt="getblockparam">
</div>

In Ruby[^1]:

```ruby
class GetBlockParam
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

In `def foo(&bar) = bar` disassembly:

```
== disasm: #<ISeq:<main>@-e:1 (1,0)-(1,19)> (catch: false)
0000 definemethod                           :foo, foo                 (   1)[Li]
0003 putobject                              :foo
0005 leave

== disasm: #<ISeq:foo@-e:1 (1,0)-(1,19)> (catch: false)
local table (size: 1, argc: 0 [opts: 0, rest: -1, post: 0, block: 0, kw: -1@-1, kwrest: -1])
[ 1] bar@0<Block>
0000 getblockparam                          bar@0, 0                  (   1)[Ca]
0003 leave                                  [Re]
```

Notice in the local table that it has `block: 0`. This means that the block parameter is at index 0 within the list of arguments. If a block parameter were not present, it would say `block: -1`.

## `getblockparamproxy`

Going even further to avoid allocating a `Proc`, the `getblockparamproxy` instruction is used to push a static proxy object onto the stack that only responds to `#call`. This addresses the common case that when you're reifying a block parameter, the majority of the time you're just calling `#call` and not doing much else to it. For example:

```ruby
def foo(&bar)
  for baz in [1, 2, 3] do
    bar.call(baz)
  end
end
```

In the example above, we're explicitly calling the `#call` method on the block object, but not doing anything else to it. In this case YARV can see that and avoid allocating the `Proc` object and instead jump straight into executing the block code. Note that this only happens if that same `VM_FRAME_FLAG_MODIFIED_BLOCK_PARAM` flag that we saw earlier is unset. If it is set, then the `Proc` object has already been allocated and go ahead and read the value.

The instruction is structured the same as `getblockparam` and `getlocal`, with an index and level associated with it. Its role is to find the local and check if it has been reified. If it has, then it will push the value onto the stack. If it has not, then it will push a proxy object onto the stack.

<div align="center">
  <img src="/assets/aoy/part9-getblockparamproxy.svg" alt="getblockparamproxy">
</div>

In Ruby[^2]:

```ruby
class GetBlockParamProxy
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

In the disassembly for the example above:

```
== disasm: #<ISeq:<main>@test.rb:1 (1,0)-(5,3)> (catch: false)
0000 definemethod                           :foo, foo                 (   1)[Li]
0003 putobject                              :foo
0005 leave

== disasm: #<ISeq:foo@test.rb:1 (1,0)-(5,3)> (catch: false)
local table (size: 2, argc: 0 [opts: 0, rest: -1, post: 0, block: 0, kw: -1@-1, kwrest: -1])
[ 2] bar@0<Block>[ 1] baz@1
0000 duparray                               [1, 2, 3]                 (   2)[LiCa]
0002 send                                   <calldata!mid:each, argc:0>, block in foo
0005 leave                                                            (   5)[Re]

== disasm: #<ISeq:block in foo@test.rb:2 (2,2)-(4,5)> (catch: false)
local table (size: 1, argc: 1 [opts: 0, rest: -1, post: 0, block: -1, kw: -1@-1, kwrest: -1])
[ 1] ?@0<Arg>
0000 getlocal_WC_0                          ?@0                       (   2)
0002 setlocal_WC_1                          baz@1
0004 nop                                    [Bc]
0005 getblockparamproxy                     bar@0, 1                  (   3)[Li]
0008 getlocal_WC_1                          baz@1
0010 opt_send_without_block                 <calldata!mid:call, argc:1, ARGS_SIMPLE>
0012 leave                                                            (   4)[Br]
```

## `setblockparam`

Finally, we have the `setblockparam` instruction. This is used to set the value of a block parameter. It is used in the place of a `setlocal` instruction in order to both set the value of the local and also set the `VM_FRAME_FLAG_MODIFIED_BLOCK_PARAM` flag on the frame. To illustrate this, let's look at the definition of `setlocal`:

```c
/* Set a local variable (pointed to by 'idx') as val.
     'level' indicates the nesting depth from the current block.
 */
DEFINE_INSN
setlocal
(lindex_t idx, rb_num_t level)
(VALUE val)
()
{
    const VALUE *ep = vm_get_ep(GET_EP(), level);
    vm_env_write(ep, -(int)idx, val);
    RB_DEBUG_COUNTER_INC(lvar_set);
    (void)RB_DEBUG_COUNTER_INC_IF(lvar_set_dynamic, level > 0);
}
```

And now let's look at the definition of `setblockparam`:

```c
/* Set block parameter. */
DEFINE_INSN
setblockparam
(lindex_t idx, rb_num_t level)
(VALUE val)
()
{
    const VALUE *ep = vm_get_ep(GET_EP(), level);
    VM_ASSERT(VM_ENV_LOCAL_P(ep));

    vm_env_write(ep, -(int)idx, val);
    RB_DEBUG_COUNTER_INC(lvar_set);
    (void)RB_DEBUG_COUNTER_INC_IF(lvar_set_dynamic, level > 0);

    VM_ENV_FLAGS_SET(ep, VM_FRAME_FLAG_MODIFIED_BLOCK_PARAM);
}
```

You'll see they're effectively the same function, with `setblockparam` additionally setting `VM_FRAME_FLAG_MODIFIED_BLOCK_PARAM`. The value that is sets is popped off the top of the stack. This is how it looks when it is executed:

<div align="center">
  <img src="/assets/aoy/part9-setblockparam.svg" alt="setblockparam">
</div>

In Ruby:

```ruby
class SetBlockParam
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

In the disassembly for `def foo(&bar) = bar = -> { 1 }`:

```
== disasm: #<ISeq:<main>@-e:1 (1,0)-(1,30)> (catch: false)
0000 definemethod                           :foo, foo                 (   1)[Li]
0003 putobject                              :foo
0005 leave

== disasm: #<ISeq:foo@-e:1 (1,0)-(1,30)> (catch: false)
local table (size: 1, argc: 0 [opts: 0, rest: -1, post: 0, block: 0, kw: -1@-1, kwrest: -1])
[ 1] bar@0<Block>
0000 putspecialobject                       1                         (   1)[Ca]
0002 send                                   <calldata!mid:lambda, argc:0, FCALL>, block in foo
0005 dup
0006 setblockparam                          bar@0, 0
0009 leave                                  [Re]

== disasm: #<ISeq:block in foo@-e:1 (1,24)-(1,30)> (catch: false)
0000 putobject_INT2FIX_1_                                             (   1)[LiBc]
0001 leave                                  [Br]
```

## Wrapping up

In this post we looked at three instructions: `getblockparam`, `getblockparamproxy`, and `setblockparam`. We saw how these instructions are used to implement lazily evaluated block parameters. A couple of things to remember from this post:

* Block parameters require space on the stack just as any other parameters.
* YARV does everything it can to not reify block parameters into `Proc` objects to avoid the overhead of creating a `Proc` object. Instead, it can either avoid doing any work if the block is never used or push a proxy object if only the `#call` method is called on it.

In the next post we'll finish out our tour of local variables with two very special instructions.

---

[^1]: We're cheating a little here and assuming our toy VM doesn't perform the same lazy evaluation as YARV does.
[^2]: Again, we're cheating here. At some point I may add the lazy evaluation to the VM, but this serves the purpose for now of demonstrating the local lookup, which is enough.
