### Pushing frames

That was a lot of information in just text. Let's look at some diagrams to help illustrate the concepts we just discussed. If you recall from the previous posts, in all of the examples where we showed the stack, we also included an arrow to the next empty slot. This arrow is actually the stack pointer for the top frame. In those examples, we omitted the environment pointer, but we'll include it here now. Let's take a look at a very contrived example:

```ruby
def add32(value)
  value + 32
end

def celsius2fahrenheit(value)
  factor = 1.8
  add32(value * factor)
end

celsius2fahrenheit(100)
```

Let's walk through what the value stack and frame stack look like up to the point where we make the first method call (to `celsius2fahrenheit`). First, let's disassemble just the top-level instruction sequence so that we can see the instructions. Don't worry about the implementation of the instructions we don't know yet, we're going to gloss over a couple of details and come back later once we've seen them.

```
== disasm: #<ISeq:<main>@test.rb:1 (1,0)-(10,23)> (catch: false)
0000 definemethod                           :add32, add32             (   1)[Li]
0003 definemethod                           :celsius2fahrenheit, celsius2fahrenheit(   5)[Li]
0006 putself                                                          (  10)[Li]
0007 putobject                              100
0009 opt_send_without_block                 <calldata!mid:celsius2fahrenheit, argc:1, FCALL|ARGS_SIMPLE>
0011 leave
```

Now that we've disassembled, let's trace the frame and value stacks through the execution of this instruction sequence right up to the point where the first method is called.

<div align="center">
  <img src="/assets/aoy/part3-step1.svg" alt="Stacks up to the first method call">
</div>

The left column is the frame stack. The right column is the value stack. Notice that the `<main>` frame has two pointers. The one on top is the stack pointer for the next slot to write to. The one on the bottom is the environment pointer representing the base of the frame. We've made the pointers point _between_ slots on the stack because semantically they're pointing to an offset. If you were to write to one of the pointers, it would overwrite the slot just above it.

Next, we're going to execute the `opt_send_without_block` instruction. First, this is going to pop the receiver and arguments off the stack (by changing where the stack pointer is).[^3] Then, this will push a frame onto the frame stack when we call `celsius2fahrenheit`. The instruction sequence for that method will then be executed. Let's disassemble it first:

```ruby
== disasm: #<ISeq:celsius2fahrenheit@test.rb:5 (5,0)-(8,3)> (catch: false)
local table (size: 2, argc: 1 [opts: 0, rest: -1, post: 0, block: -1, kw: -1@-1, kwrest: -1])
[ 2] value@0<Arg>[ 1] factor@1
0000 putobject                              1.8                       (   6)[LiCa]
0002 setlocal_WC_0                          factor@1
0004 putself                                                          (   7)[Li]
0005 getlocal_WC_0                          value@0
0007 getlocal_WC_0                          factor@1
0009 opt_mult                               <calldata!mid:*, argc:1, ARGS_SIMPLE>[CcCr]
0011 opt_send_without_block                 <calldata!mid:add32, argc:1, FCALL|ARGS_SIMPLE>
0013 leave                                                            (   8)[Re]
```

Now let's continue our diagrams up to the point where `add32` is called.

<div align="center">
  <img src="/assets/aoy/part3-step2.svg" alt="Stacks up to the second method call">
</div>

At this point we have two frames on the frame stack, and our value stack is all set up to call `add32` via the `opt_send_without_block` instruction. First, let's disassemble that method to see the instructions.

```
== disasm: #<ISeq:add32@test.rb:1 (1,0)-(3,3)> (catch: false)
local table (size: 1, argc: 1 [opts: 0, rest: -1, post: 0, block: -1, kw: -1@-1, kwrest: -1])
[ 1] value@0<Arg>
0000 getlocal_WC_0                          value@0                   (   2)[LiCa]
0002 putobject                              32
0004 opt_plus                               <calldata!mid:+, argc:1, ARGS_SIMPLE>[CcCr]
0006 leave                                                            (   3)[Re]
```

Next, let's walk through the modifications to the frame and value stack as we execute the instructions for `add32` just up to the point where the `leave` instruction will be executed.

<div align="center">
  <img src="/assets/aoy/part3-step3.svg" alt="Stacks before the first leave">
</div>

At this point, we're about to execute our first `leave` instruction. This will pop the `add32` frame off the frame stack, pop the return value off the value stack, and write the return value to the parent frame's stack pointer. Below is an illustration that shows the frame and value stacks after that `leave` instruction has been executed.

<div align="center">
  <img src="/assets/aoy/part3-step4.svg" alt="Stacks after the first leave">
</div>

Notice that this actually _increased_ the stack pointer of the parent frame. This is why the `leave` instruction is said to both push and pop a value from the stack. It does, it's just not at the same point. Now let's execute the second leave.

<div align="center">
  <img src="/assets/aoy/part3-step5.svg" alt="Stacks after the second leave">
</div>

Again, the parent frame (in this case the `<main>` frame) has its stack pointer increased. This is because the `leave` instruction is pushing a value of `212` onto the stack. The last instruction to execute is the final `leave` instruction, which finishes the execution of the program.
