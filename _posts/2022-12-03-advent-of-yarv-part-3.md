---
layout: post
title: Advent of YARV
subtitle: Part 3 - Frames and events
meta:
  "twitter:card": summary
  "twitter:title": "Advent of YARV: Part 3"
  "twitter:description": "This post is part of a series about how the YARV virtual machine works."
  "twitter:site": "@kddnewton"
  "twitter:image": https://upload.wikimedia.org/wikipedia/commons/thumb/7/73/Ruby_logo.svg/1200px-Ruby_logo.svg.png
---

This blog series is about how the CRuby virtual machine works. If you're new to the series, I recommend starting from [the beginning](/2022/11/30/advent-of-yarv-part-0). This post is about frames and events.

## Frames

Whenever YARV is executing instructions, it is executing in the context of a frame. A frame holds all of the information necessary to execute those instructions. That includes:

* the instruction sequence that is being executed
* a pointer to an offset into the instruction sequence that indicates the next instruction to execute
* a pointer to an offset into the stack that indicates where the next value should be written
* the current value of `self`
* the current constant scope[^1]
* any special local variables[^2]

YARV keeps a stack of frames around. Frames push a new "child" frame onto the frame stack when a new instruction sequence should be executed. Child frames are popped off the stack when the instruction sequence has finished executing and the return value is returned to the "parent" frame. Every frame has a parent frame except for the top-level frame, which conveniently has a type of `top`.

Note that this is a different stack from the value stack that we've discussed in the first two posts. The value stack is a stack of values that are used to pass values between instructions. The frame stack is a stack of frames that are used to keep track of the current execution context. It can get confusing since there are actually quite a few stacks in the virtual machine.

Rubyists interact with frames all of the time without necessarily realizing it. For example, in the following code snippet YARV will push a new frame for the block being passed to the `each` method:

```ruby
sum = 0

[1, 2, 3].each do |number|
  double = number * 2
  sum += double

  puts double
end
```

The frame is executed for each of the elements in the array. Notice that some frame types (like the `block` frame type) can interact with their parent frames to look up things like local variables (in this example, the `sum` variable). Other frame types (like the `method` frame type, pushed any time a method is defined) cannot.

Notice also that frames can have their own set of local variables that do not impact the parent frame. In this example, a space will be allocated on the stack for `double` when the block first starts executing, but it will not impact the parent frame's stack pointer. When the block exits, the parent frame's stack pointer will still be below the locals that were allocated, effectively making those values invisible to the parent frame.

That was a lot of information in just text. Let's look at some diagrams to help illustrate the concepts we just discussed.

### Backtraces

Rubyists also interact with the frame stack whenever an error is raised. If you fire up an `irb` session and raise an error, you'll see:

```
irb(main):001:1* class Foo
irb(main):002:2*   def bar
irb(main):003:2*     tap { tap { tap { raise "an error" } } }
irb(main):004:1*   end
irb(main):005:0> end
=> :bar
irb(main):006:0> Foo.new.bar
(irb):3:in `block (3 levels) in bar': an error (RuntimeError)
        from <internal:kernel>:90:in `tap'
        from (irb):3:in `block (2 levels) in bar'
        from <internal:kernel>:90:in `tap'
        from (irb):3:in `block in bar'
        from <internal:kernel>:90:in `tap'
        from (irb):3:in `bar'
        from (irb):6:in `<main>'
        from /.../ruby/lib/ruby/gems/3.2.0+3/gems/irb-1.4.2/exe/irb:11:in `<top (required)>'
        from /.../ruby/bin/irb:25:in `load'
        from /.../ruby/bin/irb:25:in `<main>'
```

This is a backtrace. It shows the frames that were being executed when the error was raised. The first frame is the one that raised the error. The rest of the frames are the ancestors of that frame all of the way up to the top where the error was caught. If the error were not caught, the program would have exited.

### Types of frames

We've already introduced three kinds of frames in this post, but to be thorough, here is a list of all of the different kinds of frames that YARV can push onto the frame stack:

* `top` - the top level frame of any execution
* `method` - a frame for a method definition
* `block` - a frame for a block
* `class` - a frame for a class, module, or singleton class definition
* `rescue` - a frame for a `rescue` block
* `ensure` - a frame for an `ensure` block
* `eval` - a frame pushed when calling `eval`
* `main` - a frame for the main script being executed
* `plain` - a unique frame used with the `once` instruction

We'll talk more about frames when we get to classes, methods, and local variables. For now, there's just one more piece of frames that we need to talk about before going on to events: the `leave` instruction.

## `leave`

The `leave` instruction is used to pop a frame off the frame stack and return the value on the top of the stack. You'll notice that it exists in every disassembly example we've provided so far. That's because at the end of executing the `top` frame, a `leave` instruction finishes the execution of the program. If we compile our example from above into YARV and then disassemble it, we'll see:

```
== disasm: #<ISeq:<main>@<compiled>:1 (1,0)-(8,3)> (catch: false)
local table (size: 1, argc: 0 [opts: 0, rest: -1, post: 0, block: -1, kw: -1@-1, kwrest: -1])
[ 1] sum@0
0000 putobject_INT2FIX_0_                                             (   1)[Li]
0001 setlocal_WC_0                          sum@0
0003 duparray                               [1, 2, 3]                 (   3)[Li]
0005 send                                   <calldata!mid:each, argc:0>, block in <main>
0008 leave

== disasm: #<ISeq:block in <main>@<compiled>:3 (3,15)-(8,3)> (catch: false)
local table (size: 2, argc: 1 [opts: 0, rest: -1, post: 0, block: -1, kw: -1@-1, kwrest: -1])
[ 2] number@0<Arg>[ 1] double@1
0000 getlocal_WC_0                          number@0                  (   4)[LiBc]
0002 putobject                              2
0004 opt_mult                               <calldata!mid:*, argc:1, ARGS_SIMPLE>[CcCr]
0006 setlocal_WC_0                          double@1
0008 getlocal_WC_1                          sum@0                     (   5)[Li]
0010 getlocal_WC_0                          double@1
0012 opt_plus                               <calldata!mid:+, argc:1, ARGS_SIMPLE>[CcCr]
0014 setlocal_WC_1                          sum@0
0016 putself                                                          (   7)[Li]
0017 getlocal_WC_0                          double@1
0019 opt_send_without_block                 <calldata!mid:puts, argc:1, FCALL|ARGS_SIMPLE>
0021 leave                                                            (   8)[Br]
```

Both the `top` frame and the `block` frame have a `leave` instruction at the end. The `top` frame's `leave` instruction is what finishes the execution of the program. The `block` frame's `leave` instruction is what finishes the execution of the block and returns the top value on the stack to the parent frame. It does this by writing to the parent frame's stack pointer instead of the current frame's stack pointer. Internally to CRuby, you'll find the lines that do this are:

```c
// leave in insns.def
if (vm_pop_frame(ec, GET_CFP(), GET_EP())) {
  return val;
}

// vm_pop_frame in vm_insnhelper.c
ec->cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp);
```

As you can imagine, `leave` is going to show up quite a bit in this blog series, as it is arguably the most important instruction.

## Events

The second half of this post is about events. Ruby has a built-in way to hook into the execution of a program and get notified when certain things happen. This is the tracepoint mechanism. It is used by profilers, debuggers, and other tools. It is also used by the Ruby interpreter itself to implement the `TracePoint` class. YARV has to know about these events, as some of them are dispatched when certain instructions are executed.

For example, if you disassemble `0`, you'll see:

```
== disasm: #<ISeq:<main>@-e:1 (1,0)-(1,1)> (catch: false)
0000 putobject_INT2FIX_0_                                             (   1)[Li]
0001 leave
```

Over on the far right, you see `(   1)[Li]`. The `(   1)` indicates that this instruction executes on line `1` of the program. The `[Li]` indicates that before this instruction executes, a `line` event will be dispatched.

For a more complex example, disassemble `1 + \n  2`:

```
== disasm: #<ISeq:<main>@test.rb:1 (1,0)-(2,3)> (catch: false)
0000 putobject_INT2FIX_1_                                             (   1)[Li]
0001 putobject                              2                         (   2)
0003 opt_plus                               <calldata!mid:+, argc:1, ARGS_SIMPLE>(   1)[CcCr]
0005 leave
```

Here you'll see that each of the first three instructions has its own line number. Because the operator for the plus instruction is on the first line, the `opt_plus` instruction is considered to be on line `1` even though the argument to the `+` method is on line `2`. Also notice that only one `line` event is being dispatched in this instruction sequence. `line` events are only dispatched between statements, not between individual expressions (I'm very purposefully vague here because there are numerous exceptions).

In our previous example you can also see the `Cc` and `Cr` flags. Those correspond to the `c_call` and `c_return` events, which indicate when a C function is called and returned from. These flags are attached as information on the instruction itself stored in the instruction sequence. In the disassembly, they will appear after the name of the instruction and its operands. In the `RubyVM::InstructionSequence#to_a` output, they will show up as symbols in the list of instructions.

The total list of events that you'll see in an instruction sequence are:

* `RUBY_EVENT_LINE` - dispatched when a new line is about to be executed
* `RUBY_EVENT_C_CALL` - dispatched when entering into a C function
* `RUBY_EVENT_C_RETURN` - dispatched when returning from a C function
* `RUBY_EVENT_CALL` - dispatched when entering into a ruby method
* `RUBY_EVENT_RETURN` - dispatched when returning from a ruby method
* `RUBY_EVENT_B_CALL` - dispatched when entering into a block
* `RUBY_EVENT_B_RETURN` - dispatched when returning from a block
* `RUBY_EVENT_CLASS` - dispatched when entering into a class, module, or singleton class definition
* `RUBY_EVENT_END` - dispatched when returning from a class, module, or singleton class definition

To be complete though, there are some additional events that will get fired internally by the interpreter, but that you won't see in the instruction sequence. The remaining events are:

* `RUBY_EVENT_RAISE` - dispatched when an exception is raised
* `RUBY_EVENT_A_CALL` - dispatched when `RUBY_EVENT_CALL`, `RUBY_EVENT_B_CALL`, or `RUBY_EVENT_C_CALL` is dispatched
* `RUBY_EVENT_A_RETURN` - dispatched when `RUBY_EVENT_RETURN`, `RUBY_EVENT_B_RETURN`, or `RUBY_EVENT_C_RETURN` is dispatched
* `RUBY_EVENT_THREAD_BEGIN` - dispatched when a new thread is created
* `RUBY_EVENT_THREAD_END` - dispatched when a thread is terminated
* `RUBY_EVENT_FIBER_SWITCH` - dispatched when the current fiber is switched
* `RUBY_EVENT_SCRIPT_COMPILED` - dispatched when new Ruby code is compiled with eval, load, or require

## Wrapping up

In this post we talked about two very important concepts: the frame stack and events. We also talked about the `leave` instruction and how that interacts with the frame stack. Here are a couple of things to remember from this post:

* A frame is an object that executes the instructions in an instruction sequence and stores all of the information necessary to do so.
* Frames exist in a stack and are pushed on by various instructions. They are always popped by the `leave` instruction (slight caveat that the `throw` instruction can also pop frames, but we'll get there later).
* Ruby dispatches events whenever certain actions are taken by the virtual machine. These events can be used to implement tooling that hooks into the execution of a Ruby program. These events can be attached to instructions to dispatch when the instruction is executed.

In the next post we'll go back to introducing more instructions. We will focus on instructions that combine multiple values on the top of the stack into one new value.

---

[^1]: The constant scope that is held by the frame is similar to but not quite the same as the values returned by [Module::nesting](https://docs.ruby-lang.org/en/master/Module.html#method-c-nesting).
[^2]: We'll talk more about special local variables when we get to the `getspecial` and `setspecial` instructions. It refers to local variables that are more akin to global variables in that they are not stored on the stack.
