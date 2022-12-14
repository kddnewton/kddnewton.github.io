---
layout: post
title: Advent of YARV
subtitle: Part 23 - Primitive
meta:
  "twitter:card": summary
  "twitter:title": "Advent of YARV: Part 23"
  "twitter:description": "This post is part of a series about how the YARV virtual machine works."
  "twitter:site": "@kddnewton"
  "twitter:image": https://upload.wikimedia.org/wikipedia/commons/thumb/7/73/Ruby_logo.svg/1200px-Ruby_logo.svg.png
---

This blog series is about how the CRuby virtual machine works. If you're new to the series, I recommend starting from [the beginning](/2022/11/30/advent-of-yarv-part-0). This post is about the `Primitive` module and the `invokebuiltin` instruction.

In October of 2019, Koichi Sasada proposed adding a new way for methods that were defined in C to be declared in Ruby. You can read about it in the [initial proposal](https://bugs.ruby-lang.org/issues/16254) or view the [RubyKaigi presentation](https://rubykaigi.org/2019/presentations/ko1.html).

If the code being compiled is in a core Ruby file, there are two ways to use the new syntax. You can call either `__builtin_xxx` or `Primitive.xxx` where `xxx` is a function name. This will compile in the `invokebuiltin` instruction which will call the associated C function when it is executed. Once the functions are called, another script (`tool/mk_builtin_loader.rb`) will run over those files, find all of the builtin calls, and create a C function that exports them.

There are two optimizations that can be applied to the `invokebuiltin` instruction. The first is `opt_invokebuiltin_delegate`. This optimization gets compiled when the arguments to the `invokebuiltin` instruction are the same as the arguments to the C function. The second is `opt_invokebuiltin_delegate_leave` which gets compiled when `invokebuiltin` is followed by a `leave` instruction. This optimization will call the C function and immediately perform the same actions as the `leave` instruction.

To actually see these instructions in instruction sequences, you need to use the `RubyVM::InstructionSequence::of` method. This method will return a `RubyVM::InstructionSequence` object that corresponds to the given method. You can then call `disasm` on that object to get back the disassembly as a string. If we call it on a method that uses the `Primitive` module, we can see the `invokebuiltin` instruction and its specializations.

## `Array#sample`

As an example, let's take a look at the `Array#sample` method. Here's how it is declared in Ruby:

```ruby
class Array
  def sample(n = (ary = false), random: Random)
    if Primitive.mandatory_only?
      Primitive.ary_sample0
    else
      Primitive.ary_sample(random, n, ary)
    end
  end
end
```

This disassembles to:

```
== disasm: #<ISeq:sample@<internal:array>:60 (60,2)-(68,5)> (catch: false)
local table (size: 4, argc: 0 [opts: 1, rest: -1, post: 0, block: -1, kw: 1@0, kwrest: -1])
[ 4] n@0<Opt=0> [ 3] random@1   [ 2] ?@2        [ 1] ary@3                               
0000 putobject                              false                     (  60)[Li]         
0002 dup
0003 setlocal_WC_0                          ary@3
0005 setlocal_WC_0                          n@0
0007 checkkeyword                           4, 0
0010 branchif                               16
0012 opt_getconstant_path                   <ic:0 Random>
0014 setlocal_WC_0                          random@1
0016 getlocal_WC_0                          random@1                  (  66)[LiCa]
0018 getlocal_WC_0                          n@0
0020 getlocal_WC_0                          ary@3
0022 invokebuiltin                          <builtin!ary_sample/3>
0024 leave                                                            (  68)[Re]
```

You can see the `invokebuiltin` instruction gets compiled in here to call `ary_sample` with 3 arguments.

## `Dir::open`

Let's take a look at another example. This time, we'll look at the `Dir::open` method. Here's how it is declared in Ruby:

```ruby
class Dir
  def self.open(name, encoding: nil, &block)
    dir = Primitive.dir_s_open(name, encoding)
    if block
      begin
        yield dir
      ensure
        Primitive.dir_s_close(dir)
      end
    else
      dir
    end
  end
end
```

This disassembles to:

```
== disasm: #<ISeq:open@<internal:dir>:97 (97,2)-(108,5)> (catch: true)
== catch table                                                                                                                    
| catch type: ensure st: 0010 ed: 0014 sp: 0001 cont: 0018                                                                        
| == disasm: #<ISeq:ensure in open@<internal:dir>:103 (103,8)-(103,34)> (catch: true)                                             
| local table (size: 1, argc: 0 [opts: 0, rest: -1, post: 0, block: -1, kw: -1@-1, kwrest: -1])                                   
| [ 1] $!@0                                                                                                                       
| 0000 getlocal_WC_1                          dir@4                     ( 103)[Li]                                                
| 0002 invokebuiltin                          <builtin!dir_s_close/1>                                                             
| 0004 pop                                                                                                                        
| 0005 getlocal_WC_0                          $!@0                                                                                
| 0007 throw                                  0                                                                                   
|------------------------------------------------------------------------                                                         
local table (size: 5, argc: 1 [opts: 0, rest: -1, post: 0, block: 3, kw: 1@0, kwrest: -1])                                        
[ 5] name@0<Arg>[ 4] encoding@1 [ 3] ?@2        [ 2] block@3<Block>[ 1] dir@4                                                     
0000 opt_invokebuiltin_delegate             <builtin!dir_s_open/2>, 0 (  98)[LiCa]                                                
0003 setlocal_WC_0                          dir@4
0005 getblockparamproxy                     block@3, 0                (  99)[Li]
0008 branchunless                           19
0010 getlocal_WC_0                          dir@4                     ( 101)[Li]
0012 invokeblock                            <calldata!argc:1, ARGS_SIMPLE>
0014 opt_invokebuiltin_delegate             <builtin!dir_s_close/1>, 4( 103)[Li]
0017 pop
0018 leave                                                            ( 108)[Re]
0019 getlocal_WC_0                          dir@4                     ( 106)[Li]
0021 leave                                                            ( 108)[Re]
```

Here you can see `opt_invokebuiltin_delegate` is compiled in for `dir_s_open` and `dir_s_close`.

## `Integer#-@`

As a final example, let's look at `Integer#-@`. Here's how it is declared in Ruby:

```ruby
class Integer
  def -@
    Primitive.attr! 'inline'
    Primitive.cexpr! 'rb_int_uminus(self)'
  end
end
```

In YARV:

```
== disasm: #<ISeq:-@@<internal:numeric>:88 (88,2)-(91,5)> (catch: false)
0000 opt_invokebuiltin_delegate_leave       <builtin!_bi0/0>, 0       (  90)[LiCa]
0003 leave                                                            (  91)[Re]
```

You can see that it's only necessary to have a single instruction compiled in here, `opt_invokebuiltin_delegate_leave`.

## Wrapping up

In this post we looked at `invokebuiltin` and its associated optimizations. There was a lot of work that went into the proposal and implementation, and it's worth taking a glance at the issue and watching the video. This post only scratches the surface of what's possible with `invokebuiltin`. A couple of things to remember from this post:

* `invokebuiltin` is an instruction that allows CRuby developers to declare methods in Ruby that are implemented in C.
* It's possible that `invokebuiltin` can enable some optimizations in the future, such as inlining.

The next post will be the last post in the blog series! We'll wrap up the series with the final four instructions we haven't covered yet.
