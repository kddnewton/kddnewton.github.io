---
layout: post
title: Advent of YARV
subtitle: Part 10 - Local variables (3)
meta:
  "twitter:card": summary
  "twitter:title": "Advent of YARV: Part 10"
  "twitter:description": "This post is part of a series about how the YARV virtual machine works."
  "twitter:site": "@kddnewton"
  "twitter:image": https://upload.wikimedia.org/wikipedia/commons/thumb/7/73/Ruby_logo.svg/1200px-Ruby_logo.svg.png
---

This blog series is about how the CRuby virtual machine works. If you're new to the series, I recommend starting from [the beginning](/2022/11/30/advent-of-yarv-part-0). This post is the last of three posts about local variables.

In the previous two posts, we've discussed two ways of introducing local variables into your code. You can assign to a local variable through regular assignment, like `foo = 1`. Or you can declare parameters on a method declaration and then access them in the method, as in `def foo(bar) = bar`. In this post, we'll talk about a couple more ways to introduce local variables and how to access them.

## Environment data

First, before we go on, I need to make a confession. I omitted a detail when we were discussing local variables and the environment pointer to make the concept simpler in the beginning. Now that we have a better understanding of locals and the environment pointer though, we need that detail in place.

Here it is: when a frame that is not a `block` frame is pushed onto the frame stack, 3 other values are pushed onto the value stack as well. Those values depend on the frame type, but effectively form a scratch area that the frame can use to read and write values. Internally to CRuby, this area is called `VM_ENV_DATA`. The 3 slots of the value stack are within the data area are:

VM_ENV_DATA_INDEX_ME_CREF
: This slot can contain a couple of different things: method entries, class references, special variables, or `false`.

VM_ENV_DATA_INDEX_SPECVAL
: This is used to hold either the environment pointer for the parent frame or the block handler for a method.

VM_ENV_DATA_INDEX_FLAGS
: This is used to hold flags for the frame. We ran into this in the previous post when we were discussing the `VM_FRAME_FLAG_MODIFIED_BLOCK_PARAM` flag.

Today, we're interested in `VM_ENV_DATA_INDEX_ME_CREF`. This slot contains a special struct that is used to store a `vm_svar` struct, which contains our additional local variables.

## Special variables

Let's take a look at the struct definition for `vm_svar`:

```c
/*! SVAR (Special VARiable) */
struct vm_svar {
  VALUE flags;
  const VALUE cref_or_me; /*!< class reference or rb_method_entry_t */
  const VALUE lastline;
  const VALUE backref;
  const VALUE others;
};
```

This is a common structure used in CRuby called an `imemo`. An `imemo` is a kind of interface of the same size that can be passed around the Ruby VM without too much hassle. The last three entries in the structure are what we care about right now. So let's define them now:

* `lastline` - this is either `nil` or the last line read by an IO method, such as `gets` or `readline`. It can also be accessed directly through the `$_` global variable.
* `backref` - this is either `nil` or the last match data rendered by a regular expression match. It can also be accessed directly through the `$~` global variable.
* `others` - this is either `nil` or an array of booleans. Each boolean represents the state of a flip-flop operator. This is used by the `..` and `...` operators when a flip-flop is created.

### flip-flop

We need to take a quick minute to discuss the flip-flop operator, because it is not a commonly used or known feature of Ruby. The flip-flop operator is a way to create a gating condition that will evaluate to true every time after its initial condition is met until its final condition is met. It is used like this:

```ruby
(1..100).each do |value|
  if (value == 5) .. (value == 10)
    print "#{value} "
  end
end

puts "done!"
```

The example above will print `5 6 7 8 9 10 done!`. You can see that there's an extra state that needs to be stored somewhere which is whether or not the flip-flop has been triggered yet. This is the boolean that is stored in the `others` array.

## `getspecial`

Finally, we get to the instructions that we're here to see today. These instructions are `getspecial` and `setspecial`. These instructions are used to access information held _within_ the special variables we just discussed (but not the variables themselves!).

The `getspecial` instruction has two operands. Its function is to access the special variable given by the operands and push the value onto the stack.

The first operand is the index of the special variable to access. If the index is `0`, then it's referring to `VM_SVAR_LASTLINE`, which will access the `lastline` field on the `svar` struct. If the index is `1`, then it's referring to `VM_SVAR_BACKREF`, which will access the `backref` field on the `svar` struct. If the index is `2` or above, then it's referring to 2 more than an index into the the `others` field, which is an array.

The second value is used only if the match data is being accessed and is used to indicate which field within the match data to return. It is a tagged value, with its tag being the least significant bit.

* If the least significant bit is `0`, then the value is 2 times the index of the capture group to return. For example, `$2` would merit `getspecial 1, 4`. The maximum capture group you can access is `$1073741823`, or one less than `2^30`.
* If the least significant bit is `1`, then the value is twice plus one the character value of the corresponding global variable to return. For example, `$&` would merit `getspecial 1, 77` because `'&'` is `38` and `38 * 2 + 1 = 77`. The global variables that can be accessed in this way are `$&`, <code class="language-plaintext highlighter-rouge">$`</code>, `$'`, and `$+`.

Let's go through an example of each type of special variable.

### `lastline`

The only way to access the `lastline` special variable directly through the `getspecial` instruction is when you use a regular expression as the predicate of a conditional statement. As in:

```ruby
if /pattern/
  puts "matched pattern against last line!"
end
```

That results in a disassembly of:

```
== disasm: #<ISeq:<main>@test.rb:1 (1,0)-(3,3)> (catch: false)
0000 putobject                              /pattern/                 (   1)[Li]
0002 getspecial                             0, 0
0005 opt_regexpmatch2                       <calldata!mid:=~, argc:1, ARGS_SIMPLE>[CcCr]
0007 branchunless                           15
0009 putself                                                          (   2)[Li]
0010 putstring                              "matched pattern against last line!"
0012 opt_send_without_block                 <calldata!mid:puts, argc:1, FCALL|ARGS_SIMPLE>
0014 leave
0015 putnil
0016 leave
```

You can see the `getspecial` instruction here with the `0` index means the last line.

### `backref`

As we discussed, there are two kinds of backref special variables: capture groups and fields. Let's put them into the same example:

```ruby
[$1, $2, $3, $4, $&, $`, $', $+]
```

This results in a disassembly of:

```
== disasm: #<ISeq:<main>@test.rb:1 (1,0)-(1,32)> (catch: false)
0000 getspecial                             1, 2                      (   1)[Li]
0003 getspecial                             1, 4
0006 getspecial                             1, 6
0009 getspecial                             1, 8
0012 getspecial                             1, 77
0015 getspecial                             1, 193
0018 getspecial                             1, 79
0021 getspecial                             1, 87
0024 newarray                               8
0026 leave
```

You can see the first operand is always `1`, to indicate that we're accessing the last match. The second operand is the tagged value that indicates which field to access. The first four entries all correspond to the capture groups, and the last four correspond to the fields.

### `others`

Finally, we have the flip-flop states.

```ruby
if (value == 1) .. (value == 3)
  puts "value is between 1 and 3"
elsif (value == 6) .. (value == 8)
  puts "value is between 6 and 8"
end
```

This results in a disassembly of:

```
== disasm: #<ISeq:<main>@test.rb:1 (1,0)-(5,3)> (catch: false)
0000 getspecial                             2, 0                      (   1)[Li]
...
0036 getspecial                             3, 0                      (   3)[Li]
...
0074 leave
```

You can see the first operand increments for each flip-flop encountered. (It would continue if there were more.) It's always a `0` for the second operand because that doesn't apply.

### Diagram

If we take our example code `puts "matched!" if /pattern/` and disassemble it, we get:

```ruby
== disasm: #<ISeq:<main>@-e:1 (1,0)-(1,28)> (catch: false)
0000 putobject                              /pattern/                 (   1)[Li]
0002 getspecial                             0, 0
0005 opt_regexpmatch2                       <calldata!mid:=~, argc:1, ARGS_SIMPLE>[CcCr]
0007 branchunless                           15
0009 putself
0010 putstring                              "matched!"
0012 opt_send_without_block                 <calldata!mid:puts, argc:1, FCALL|ARGS_SIMPLE>
0014 leave
0015 putnil
0016 leave
```

When we get to the `getspecial` instruction, it looks a bit like:

<div align="center">
  <img src="/assets/aoy/part10-getspecial-step1.svg" alt="getspecial">
</div>

Once we execute it, it looks a bit like:

<div align="center">
  <img src="/assets/aoy/part10-getspecial-step2.svg" alt="getspecial">
</div>

## `setspecial`

Unlike the flexibility of `getspecial` which can set any of the special variables, `setspecial` can only set the boolean associated with a flip-flop. It has a single operand which is two more than the index of the flip-flop to set. The value to set it to is popped off the stack.

For example, in `foo if (bar == 1) .. (bar == 2)` disassembly:

```
== disasm: #<ISeq:<main>@-e:1 (1,0)-(1,31)> (catch: false)
0000 getspecial                             2, 0                      (   1)[Li]
0003 branchif                               17
0005 putself
0006 opt_send_without_block                 <calldata!mid:bar, argc:0, FCALL|VCALL|ARGS_SIMPLE>
0008 putobject_INT2FIX_1_
0009 opt_eq                                 <calldata!mid:==, argc:1, ARGS_SIMPLE>[CcCr]
0011 branchunless                           34
0013 putobject                              true
0015 setspecial                             2
0017 putself
0018 opt_send_without_block                 <calldata!mid:bar, argc:0, FCALL|VCALL|ARGS_SIMPLE>
0020 putobject                              2
0022 opt_eq                                 <calldata!mid:==, argc:1, ARGS_SIMPLE>[CcCr]
0024 branchunless                           30
0026 putobject                              false
0028 setspecial                             2
0030 putself
0031 opt_send_without_block                 <calldata!mid:foo, argc:0, FCALL|VCALL|ARGS_SIMPLE>
0033 leave
0034 putnil
0035 leave
```

## Wrapping up

In this post, we looked at the `getspecial` and `setspecial` instructions. We saw that they are used to access special variables that are stored on the stack within a `vm_svar` struct. A couple of things to remember from this post:

* Three extra slots are allocated on the stack to store information about a frame. This area acts as scratch data for each kind of frame.
* Special variables are stored in the `vm_svar` struct, which is stored in the slot that also can contain a method entry or class reference.

With this post, we're done with our tour of local variables. In the next post, we'll talk about two other kinds of variables.
