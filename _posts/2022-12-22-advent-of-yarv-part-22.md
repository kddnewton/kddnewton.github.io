---
layout: post
title: Advent of YARV
subtitle: Part 22 - Pattern matching
meta:
  "twitter:card": summary
  "twitter:title": "Advent of YARV: Part 22"
  "twitter:description": "This post is part of a series about how the YARV virtual machine works."
  "twitter:site": "@kddnewton"
  "twitter:image": https://upload.wikimedia.org/wikipedia/commons/thumb/7/73/Ruby_logo.svg/1200px-Ruby_logo.svg.png
---

This blog series is about how the CRuby virtual machine works. If you're new to the series, I recommend starting from [the beginning](/2022/11/30/advent-of-yarv-part-0). This post is about pattern matching.

Pattern matching was introduced as a syntax in Ruby 2.7. Since then it has grown to include a couple more variants like single-line matching with the `=>` or `in` operators and the find pattern for arrays. Originally, pattern matching was implemented as a library. When it was decided to be merged in to the language, it was rewritten to run as YARV instruction sequences.

Because of this, it seems very different from the rest of the language. In other features, the compiler generally generates fewer, more powerful instructions. In pattern matching, the compiler generates a lot more instructions. As a result, there weren't many instructions added for pattern matching. The instructions it does use though are pretty extensive.

Let's look at an example. In the following Ruby code we're asserting that the value of `foo` matches the string `"bar"`. If it does, it will return `nil`. If it doesn't, it will raise an error.

```ruby
foo => "bar"
```

Below is the YARV instruction sequence for this code.

```
== disasm: #<ISeq:<main>@-e:1 (1,0)-(1,12)> (catch: false)
0000 putnil                                                           (   1)[Li]
0001 putnil
0002 putobject                              false
0004 putnil
0005 putnil
0006 putself
0007 opt_send_without_block                 <calldata!mid:foo, argc:0, FCALL|VCALL|ARGS_SIMPLE>
0009 dup
0010 putstring                              "bar"
0012 dupn                                   2
0014 checkmatch                             2
0016 dup
0017 branchif                               37
0019 putspecialobject                       1
0021 putobject                              "%p === %p does not return true"
0023 topn                                   3
0025 topn                                   5
0027 opt_send_without_block                 <calldata!mid:core#sprintf, argc:3, ARGS_SIMPLE>
0029 setn                                   6
0031 putobject                              false
0033 setn                                   8
0035 pop
0036 pop
0037 setn                                   2
0039 pop
0040 pop
0041 branchif                               89
0043 putspecialobject                       1
0045 topn                                   4
0047 branchif                               65
0049 putobject                              NoMatchingPatternError
0051 putspecialobject                       1
0053 putobject                              "%p: %s"
0055 topn                                   4
0057 topn                                   7
0059 opt_send_without_block                 <calldata!mid:core#sprintf, argc:3, ARGS_SIMPLE>
0061 opt_send_without_block                 <calldata!mid:core#raise, argc:2, ARGS_SIMPLE>
0063 jump                                   85
0065 putobject                              NoMatchingPatternKeyError
0067 putspecialobject                       1
0069 putobject                              "%p: %s"
0071 topn                                   4
0073 topn                                   7
0075 opt_send_without_block                 <calldata!mid:core#sprintf, argc:3, ARGS_SIMPLE>
0077 topn                                   7
0079 topn                                   9
0081 opt_send_without_block                 <calldata!mid:new, argc:3, kw:[matchee,key], KWARG>
0083 opt_send_without_block                 <calldata!mid:core#raise, argc:1, ARGS_SIMPLE>
0085 adjuststack                            7
0087 putnil
0088 leave
0089 adjuststack                            6
0091 putnil
0092 leave
```

You can see why we left this to the end of the blog series. Believe it or not, there is actually only one instruction in that entire list that we haven't covered yet, which is `checkmatch`. We'll get to it in a moment. In the meantime, you can see that there is quite a lot happening here.

Let's break it up into different sections. Below is the same set of instructions, but broken out into sections whenever a branching instruction is encountered or wherever a branching instruction could branch to. This is called a control-flow graph, and it can help us better understand what's going on. Each section is called a basic block, and we'll refer to them that way for the rest of this post.

<div align="center">
  <a href="/assets/aoy/part22-pattern-matching.svg" aria-label="pattern matching">
    <img src="/assets/aoy/part22-pattern-matching.svg" alt="pattern matching">
  </a>
</div>

I've linked the image above so you can view it full-size if that helps. Now that we have things a little better laid out, let's take a look at what's going on. There are 8 basic blocks in total in this diagram. I'll refer to them by their starting offset from the start of the instruction sequence.

block 0
: The starting block sets up the stack, pushes the object to be matched onto the stack, pushes the pattern to match onto the stack, then calls `checkmatch`. It branches on the success of running `checkmatch`.

block 19
: This block is a failure case. For some reason the `#===` method that was called on the pattern returned an unexpected value. This block sets up the error message that will be used when the `NoMatchingPatternError` error is raised.

block 49
: This block sets up the `NoMatchingPatternError` using the message built by block 19 and then actually raises it by calling `core#raise` on the frozen core object. It then jumps to a final exit block.

block 85
: This block cleans up the cached values on the stack, pushes `nil`, and then exits.

block 37
: This block checks the result of the match operation. If it was successful, it jumps to block 89. If not, it jumps to block 43.

block 43
: This block determines the reason the match operation failed. It branches to either block 49 or 65 to raise the appropriate error.

block 89
: This is the successful match case. It cleans out the stack, pushes `nil`, and then exits.

block 65
: This block raises a `NoMatchingPatternKeyError` and then jumps to block 85.

Believe it or not, this is one of the simplest kinds of pattern matching that exists. It only gets more complicated from here. We're not going to dive into every kind today, but we will explain a couple of instructions that get used by pattern matching in general.

## `checkmatch`

We saw earlier that `checkmatch` showed up to perform the pattern matching. `checkmatch` is responsible for popping two values off the stack, the object to be matched and the pattern to match against, matching them using some strategy, and then pushing the result of the match onto the stack.

The strategy used to match the object against the pattern is determined by the `flag` operand to `checkmatch`. There are three strategies that can be used:

VM_CHECKMATCH_TYPE_WHEN
: This strategy ignores the object to be matched and checks that the pattern is truthy.

VM_CHECKMATCH_TYPE_CASE
: This strategy checks that the pattern matches the object to be matched using the `#===` method.

VM_CHECKMATCH_TYPE_RESCUE
: This performs the same check as `VM_CHECKMATCH_TYPE_CASE` with the additional check that the pattern is a class or module.

## `checktype`

There are times in YARV where the type of the object returned by a method call needs to checked to conform to an expected type. For example, with pattern matching you can define custom `#deconstruct` and `#deconstruct_keys` methods. Those methods should return arrays and hashes respectively. If they don't, then an error should be raised. This is where `checktype` comes in.

`checktype` accepts a single operand which is the type that the object on the top of the stack should conform to. If it does, then `true` is pushed onto the stack. If it doesn't, then `false` is pushed onto the stack. The type check uses the `TYPE` macro, which returns a value from the `ruby_value_type` enumerable. This mostly involves checking the object's tag or flags.

## Wrapping up

There is a lot of depth that you can go into when looking at how YARV implements pattern matching. We only barely scratched the surface in this post. However, we did go through two of the instructions that make it possible: `checkmatch` and `checktype`. A couple of things to remember from this post:

* Pattern matching is implemented in many YARV instructions, as opposed to fewer instructions with more logic.
* Control-flow graphs with basic blocks are a great way to visualize the flow of instructions in a method.

In the next post we'll look at a couple of instructions that you will only see in YARV if you're working on CRuby itself.
