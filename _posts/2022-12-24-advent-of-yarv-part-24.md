---
layout: post
title: Advent of YARV
subtitle: Part 24 - Wrap up
meta:
  "twitter:card": summary
  "twitter:title": "Advent of YARV: Part 24"
  "twitter:description": "This post is part of a series about how the YARV virtual machine works."
  "twitter:site": "@kddnewton"
  "twitter:image": https://upload.wikimedia.org/wikipedia/commons/thumb/7/73/Ruby_logo.svg/1200px-Ruby_logo.svg.png
---

This blog series is about how the CRuby virtual machine works. If you're new to the series, I recommend starting from [the beginning](/2022/11/30/advent-of-yarv-part-0). This is the last post in the series.

At this point, we've actually covered every instruction in the YARV instruction set that gets compiled in by default. There are four instructions, however, that can be optionally compiled in. This last post will cover those instructions.

## `opt_call_c_function`

Back in 2007, the `opt_call_c_function` instruction was introduced. By default this isn't compiled into the Ruby binary, but you can turn it on by defining `SUPPORT_CALL_C_FUNCTION`. It has a single operand which is a function pointer to a C function. The function should accept a pointer to the execution context and a pointer to the current frame and return a pointer to a control frame. In C, this would look like:

```c
typedef rb_control_frame_t *
  (*rb_insn_func_t)(rb_execution_context_t *, rb_control_frame_t *);
```

This instruction can do literally anything it wants to the state of the virtual machine, and as such is both enormously powerful and dangerous.

## `reput`

The `reput` instruction is used when `OPT_STACK_CACHING` is defined. The usage of stack caching is entirely out of scope of this blog series, but the `reput` instruction itself at the moment does nothing. If you want to read more about stack caching or see it in action, here are a couple of links:

* [Compile reput instruction](https://github.com/ruby/ruby/blob/d20bd06a/compile.c#L4031)
* [Create stack caching instructions](https://github.com/ruby/ruby/blob/d20bd06a/tool/ruby_vm/views/opt_sc.inc.erb)
* [Stack caching for interpreters](https://dl.acm.org/doi/10.1145/223428.207165)

## `answer`

The `answer` instruction is used when `OPT_SUPPORT_JOKE` is defined. It's a simple instruction that pushes the answer to life, the universe, and everything onto the stack. That is to say, it pushes the integer `42` onto the stack. This instruction will get compiled into the instruction sequence if the compiler finds a method call to `the_answer_to_life_the_universe_and_everything` without an explicit receiver.

## `bitblt`

The `bitblt` instruction is also used when `OPT_SUPPORT_JOKE` is defined. It's another simple instruction that pushes a string onto the stack. The string is `"a bit of bacon, lettuce and tomato"`. This instruction will get compiled into the instruction sequence if the compiler finds a method call to `bitblt` without an explicit receiver.

## Wrapping up

That's it! That's the entire blog series. I hope you enjoyed it and learned as much as I did. Below are some things that we learned in this series that I think are worth highlighting:

* In this series we covered every piece of YARV disassembly, albeit spread out over many different posts. If you're confused about a particular piece of disassembly, you should be able to find it in this series.
* Most instructions in YARV are relatively simple. They add or remove from the value or frame stack, they call methods, or they jump around. By combining these relatively simple instructions, we can create much more complicated behavior. At its core, however, you will still be able to follow the logic of the program.
* Instruction sequences and their instructions are just another representation of the same Ruby code that you write, much like a syntax tree. Different representations have different utility, but they still represent the same core concepts. If you can write Ruby code and understand it, then you can understand the underlying instructions.

Now here are a couple of things that we _didn't_ cover in this series. I think it's important to point these things out so that you know what you're missing, but also what you can look up next:

* We briefly touched on how instruction sequences get compiled, but never looked at how the syntax tree gets translated into instruction sequences. For that matter we never looked at how the syntax tree gets created in the first place.
* We never looked at how garbage collection pertains to instruction sequences, but they can in fact be reclaimed. This is an important aspect of the virtual machine because various actions need to be taken when an instruction sequence is reclaimed.
* We never talked about JIT compilers. Over the past 5 years, this has become a massive place of research in the Ruby community, namely with YJIT and MJIT. If you've read this far into the series, you'll have quite a good basis for understanding how both of these JIT compilers work.
* We only briefly talked about tracepoint. Tracepoint is a very powerful tool for debugging and profiling Ruby code. It does things like rewriting instruction sequences with trace variants of their instructions, which can be pretty invasive. I skipped this because it could probably be its own blog series.

Thank you so very much for reading. I was very excited to share this information with you. I hope you have a very happy holiday season and new year. If you have any feedback or just want to say hi, feel free to drop me a line on [Twitter](https://twitter.com/kddnewton).
