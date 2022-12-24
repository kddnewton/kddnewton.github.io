---
layout: post
title: Advent of YARV
subtitle: Part 0 - Introduction
meta:
  "twitter:card": summary
  "twitter:title": "Advent of YARV: Part 0"
  "twitter:description": "This post is part of a series about how the YARV virtual machine works."
  "twitter:site": "@kddnewton"
  "twitter:image": https://upload.wikimedia.org/wikipedia/commons/thumb/7/73/Ruby_logo.svg/1200px-Ruby_logo.svg.png
---

Since I started working on the YJIT team at Shopify, I've been learning more and more about the CRuby virtual machine known as YARV. A lot of the details of how YARV works are not well documented or the documentation is difficult to find. As such, I decided to write a series of blog posts about how YARV works internally as a Christmas present to both the Ruby community and myself. I hope that this series will help others understand how YARV works and provide a better understanding of CRuby internals. This is the blog series I wish I had had access to when I first started working on CRuby.

In theory, I'll post a new post every morning describing different aspects of the virtual machine. I've divided them up into sections such that each post builds on the foundation of the others, so if you're catching up, I encourage you to start from the beginning. We'll wrap up on Christmas just in time for Ruby 3.2.0 to be released, which is what this series is targeting.

All of the information presented here is to the best of my knowledge. That being said, there are folks that are more knowledgeable, and if I've made a mistake or missed something I would very much appreciate feedback! Below are links to the individual posts.

* [Part 1 - Pushing onto the stack](/2022/12/01/advent-of-yarv-part-1)
* [Part 2 - Manipulating the stack](/2022/12/02/advent-of-yarv-part-2)
* [Part 3 - Frames and events](/2022/12/03/advent-of-yarv-part-3)
* [Part 4 - Creating objects from the stack](/2022/12/04/advent-of-yarv-part-4)
* [Part 5 - Changing object types on the stack](/2022/12/05/advent-of-yarv-part-5)
* [Part 6 - Calling methods (1)](/2022/12/06/advent-of-yarv-part-6)
* [Part 7 - Calling methods (2)](/2022/12/07/advent-of-yarv-part-7)
* [Part 8 - Local variables (1)](/2022/12/08/advent-of-yarv-part-8)
* [Part 9 - Local variables (2)](/2022/12/09/advent-of-yarv-part-9)
* [Part 10 - Local variables (3)](/2022/12/10/advent-of-yarv-part-10)
* [Part 11 - Class and instance variables](/2022/12/11/advent-of-yarv-part-11)
* [Part 12 - Global variables](/2022/12/12/advent-of-yarv-part-12)
* [Part 13 - Constants](/2022/12/13/advent-of-yarv-part-13)
* [Part 14 - Branching](/2022/12/14/advent-of-yarv-part-14)
* [Part 15 - Defining classes and modules](/2022/12/15/advent-of-yarv-part-15)
* [Part 16 - Defining methods](/2022/12/16/advent-of-yarv-part-16)
* [Part 17 - Method parameters](/2022/12/17/advent-of-yarv-part-17)
* [Part 18 - Super methods](/2022/12/18/advent-of-yarv-part-18)
* [Part 19 - Defined](/2022/12/19/advent-of-yarv-part-19)
* [Part 20 - Catch tables](/2022/12/20/advent-of-yarv-part-20)
* [Part 21 - Once](/2022/12/21/advent-of-yarv-part-21)
* [Part 22 - Pattern matching](/2022/12/22/advent-of-yarv-part-22)
* [Part 23 - Primitive](/2022/12/23/advent-of-yarv-part-23)
* [Part 24 - Wrap up](/2022/12/24/advent-of-yarv-part-24)

## Exploring

As the blog series progresses, there are a couple of ways of exploring YARV bytecode that I'll demonstrate. I'll preface them here though, so that you have a preview and know what I'm referring to when I mention them.

The first way to explore YARV is to disassemble its bytecode using the Ruby CLI. You can do this by running `ruby --dump=insns path/to/file.rb`. This will print the disassembled bytecode corresponding to the given file to stdout. For example, if you were to dump the instructions for `2 + 3` by running `ruby --dump=insns -e '2 + 3'`, you would get:

```
== disasm: #<ISeq:<main>@-e:1 (1,0)-(1,5)> (catch: false)
0000 putobject                              2                         (   1)[Li]
0002 putobject                              3
0004 opt_plus                               <calldata!mid:+, argc:1, ARGS_SIMPLE>[CcCr]
0006 leave
```

Don't worry if you don't know what any of that means. By the end of this series, we'll have covered every single character in that output.

The second way is to compile YARV bytecode from source using the `RubyVM::InstructionSequence` class. You can do this from within a Ruby file or an `irb` session. You can get the same output as the `--dump=insns` flag by running:

```ruby
iseq = RubyVM::InstructionSequence.compile_file("path/to/file.rb")
puts iseq.disasm
```

The third way is to serialize the instruction sequences to arrays using the `#to_a` method. This is useful for debugging and understanding the structure of the instruction sequences. It can also be used to emulate the behavior of the virtual machine by giving you access to symbols and other Ruby objects. To get a serialized instruction sequence, you can run:

```ruby
iseq = RubyVM::InstructionSequence.compile_file("path/to/file.rb")
pp iseq.to_a
```

For an example, if we were to again compile `2 + 3` and serialize it to an array, we would get:

```ruby
irb(main):001:0> RubyVM::InstructionSequence.compile("2 + 3").to_a
=> 
["YARVInstructionSequence/SimpleDataFormat",                        
 3,
 2,
 1,
 {:arg_size=>0,
  :local_size=>0,
  :stack_max=>2,
  :node_id=>4,
  :code_location=>[1, 0, 1, 5],
  :node_ids=>[0, 1, 3, -1]},
 "<compiled>",
 "<compiled>",
 "<compiled>",
 1,
 :top,
 [],
 {},
 [],
 [1,
  :RUBY_EVENT_LINE,
  [:putobject, 2],
  [:putobject, 3],
  [:opt_plus, {:mid=>:+, :flag=>16, :orig_argc=>1}],
  [:leave]]]
```

Again, we will go over what each of the elements in this array means in the series.

Finally, to really explore how YARV works, it helps to actually emulate its execution. As I go along in this series, I'll be translating the YARV instructions into Ruby code. This is to help you understand how the instructions work, assuming you read Ruby more easily than you read C. I'm not going to show you all of the code, as that would end up distracting from the main point of the series. However, if you're interested in seeing how this can all fit together, you can check out the following links:

* [Evaluating Ruby in Ruby](https://iliabylich.github.io/2020/01/25/evaluating-ruby-in-ruby.html) - Ilya Bylich's excellent work on emulating YARV. This was the inspiration for a lot of work I ended up doing in side projects and this series.
* [kddnewton/yarv](https://github.com/kddnewton/yarv) - A project that I and others at Shopify worked on for a HackDays that emulates YARV in Ruby. The main purpose of the project was to document all of the instructions and their behavior. You can see that result [here](https://kddnewton.com/yarv).
* [ruby-syntax-tree/syntax_tree:lib/syntax_tree/yarv.rb](https://github.com/ruby-syntax-tree/syntax_tree/blob/1ebf0a56d1f1a63045074fec948bd3ec7fcbab45/lib/syntax_tree/yarv.rb) - The Syntax Tree project can both compile and emulate YARV using Ruby. If you want to dig into all of the various bits of YARV, this is a great place to start.

## Glossary

This series explores a virtual machine, a non-trivial piece of technology. As such, there are many terms that are used to describe different aspects of its execution and structure. I'll try to define them here as I reference them in various posts here so that you can come back here to look them up if you're not familiar with them or if you forget.

Call data
: Information about a specific call site in Ruby that is retained by instructions that perform method calls.

Call site
: A location in the source code where a method is called.

Callee
: The method that is being called by another method.

Caller
: The method that is calling another method.

Compile-time
: The time when the Ruby program is being compiled into bytecode from source. This is as opposed to runtime, when the program is being executed. Oftentimes we will say something is "known at compile-time" if it is a value that does not depend on anything dynamic (e.g., an array that holds only integers, not references to local variables).

CRuby
: The main Ruby implementation at [ruby/ruby](https://github.com/by/ruby) that is written in C.

Environment pointer
: A pointer held by a frame that points to the bottom of the stack used by the frame. Importantly this pointer is found after the arguments to the frame and the local variables declared within the frame.

Frame
: A data structure that holds the state of the virtual machine at a given point in time.

Instruction
: A single operation that the virtual machine can perform. This is often abbreviated as `insn`.

Instruction sequence
: A list of instructions that the virtual machine can perform. This is often abbreviated as `iseq`.

Instruction set
: The set of instructions that the virtual machine can perform.

Operand
: A value that is used by an instruction. These values are known at compile-time and are built into the instruction sequences.

Program counter
: A pointer to the current instruction in an instruction sequence. This is also referred to as an instruction pointer.

Receiver
: The object that a method is being called on.

Reify
: To make concrete. In the context of lazy evaluation, it means to evaluate a value that was previously deferred.

Stack
: A data structure that holds values that are being used by the virtual machine. This is also referred to as the value stack. Confusingly, this is both the name of the type of data structure and the data structure itself.

Stack pointer
: A pointer held by a frame that points to the next slot in the stack to be written to. This is often abbreviated as `sp`.

Tracepoint
: A publication/subscription system for virtual machine events. Users can create tracepoints to get notified when certain events occur.

Virtual machine
: A piece of software that emulates a computer.

YARV
: The virtual machine that is used by CRuby. It stands for "Yet Another Ruby Virtual Machine".
