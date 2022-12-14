---
layout: post
title: Advent of YARV
subtitle: Part 21 - Once
meta:
  "twitter:card": summary
  "twitter:title": "Advent of YARV: Part 21"
  "twitter:description": "This post is part of a series about how the YARV virtual machine works."
  "twitter:site": "@kddnewton"
  "twitter:image": https://upload.wikimedia.org/wikipedia/commons/thumb/7/73/Ruby_logo.svg/1200px-Ruby_logo.svg.png
---

This blog series is about how the CRuby virtual machine works. If you're new to the series, I recommend starting from [the beginning](/2022/11/30/advent-of-yarv-part-0). This post is about the `once` instruction.

There are two kinds of Ruby syntax that will execute a piece of code only once in the lifetime of the program. Those are regular expressions with the `o` flag and post-executions hooks with the `END {}` block. Let's look at each in turn.

## Regular expression `o` flag

In Ruby, if we use the `o` flag, the regular expression will only be compiled once. For example:

```ruby
/xxx #{@foo} xxx/o
```

In the code above, if the value of `foo` were to change after the regular expression were created, the regular expression would not be recompiled. This is because the `o` flag tells the regular expression engine to compile the regular expression once and then use the same compiled regular expression for all subsequent matches. In YARV, the code above disassembles to:

```
== disasm: #<ISeq:<main>@-e:1 (1,0)-(1,18)> (catch: false)
0000 once                                   block in <main>, <is:0>   (   1)[Li]
0003 leave

== disasm: #<ISeq:block in <main>@-e:1 (1,0)-(1,18)> (catch: false)
0000 putobject                              "xxx "                    (   1)
0002 getinstancevariable                    :@foo, <is:0>
0005 dup
0006 objtostring                            <calldata!mid:to_s, argc:0, FCALL|ARGS_SIMPLE>
0008 anytostring
0009 putobject                              " xxx"
0011 toregexp                               0, 3
0014 leave
```

You can see in the example above that there is another instruction sequence that is created for the regular expression. The value on the top of the stack at the end of the embedded instruction sequence will always be the regular expression so that it is pushed onto the stack by the `leave` instruction when the `once` instruction is executed.

## END {} blocks

In Ruby, when you use an `END {}` block, the code in the block will be executed once at the end of the program. For example:

```ruby
END { puts "Hello" }
```

In YARV, the code above disassembles to:

```
== disasm: #<ISeq:<main>@-e:1 (1,0)-(1,20)> (catch: false)
0000 once                                   block in <main>, <is:0>   (   1)[Li]
0003 leave

== disasm: #<ISeq:block in <main>@-e:0 (0,0)-(-1,-1)> (catch: false)
0000 putspecialobject                       1                         (   1)
0002 send                                   <calldata!mid:core#set_postexe, argc:0, FCALL>, block in <main>
0005 leave

== disasm: #<ISeq:block in <main>@-e:1 (1,0)-(1,20)> (catch: false)
0000 putself                                                          (   1)[LiBc]
0001 putstring                              "Hello"
0003 opt_send_without_block                 <calldata!mid:puts, argc:1, FCALL|ARGS_SIMPLE>
0005 leave                                  [Br]
```

You can see that there are two extra instruction sequences compiled for the `END {}` block. The first is the instruction sequence used by the `once` instruction to execute only once. The second is the block that is executed inside the `END {}` block.

## `once`

The `once` instruction has two operands. The first is the instruction sequence that will only get executed once. The second is a cache that holds both the value that is a result of executing the instruction sequence and a pointer to the thread that is executing the instruction sequence.

When the `once` instruction is executed, it first checks the status of its cache. If the cache's thread pointer is null, then it schedules the instruction sequence to be executed. If it has a pointer, then it waits for it to finish executing. If the pointer is set to the value of `1`, then it does not execute the instruction sequence since this is the value used to mark it as having successfully run.

In order to execute the instruction sequence the `once` instruction pushes a `plain` frame onto the frame stack that is associated with the instruction sequence. Once the frame has finished executing the `once` instruction will set the cache's thread pointer to the value of `1`. The `leave` instruction at the end of the instruction sequence will have already written the return value onto the stack, so the `once` instruction will copy that into the cache for reuse if it is called again.

## Wrapping up

In this post we looked at the `once` instruction, a rather esoteric instruction used to implement some of the less commonly-used pieces of Ruby syntax. A couple of things to remember from this post:

* The `o` flag on regular expressions will only interpolate once for the lifetime of the program.
* The `once` instruction is used to implement the `o` flag on regular expressions and the `END {}` block.

In the next post we'll look at Ruby 2.7's pattern matching syntax and how that is compiled.
