---
layout: post
title: Advent of YARV
subtitle: Part 7 - Calling methods (2)
meta:
  "twitter:card": summary
  "twitter:title": "Advent of YARV: Part 7"
  "twitter:description": "This post is part of a series about how the YARV virtual machine works."
  "twitter:site": "@kddnewton"
  "twitter:image": https://upload.wikimedia.org/wikipedia/commons/thumb/7/73/Ruby_logo.svg/1200px-Ruby_logo.svg.png
---

This blog series is about how the CRuby virtual machine works. If you're new to the series, I recommend starting from [the beginning](/2022/11/30/advent-of-yarv-part-0). This post is the second of two posts about calling methods.

In yesterday's post we talked about the `send` instruction. Today, we're going to show all of the various specializations of that instruction. These specializations exist in order to provide fast implementations of common method calls. Let's first take a look at an example of one of these specializations, then we'll dive into the entire list.

## `opt_plus`

The `opt_plus` instruction is a specialization of `send` that is used to implement the `+` operator. Like almost every one of the instructions in this post, it has a single operand that is a call data struct. The call data struct will always contain the exact same information:

* `mid`: `:+`
* `argc`: `1`
* `flag`: `VM_CALL_ARGS_SIMPLE`

It will always contain this information because this specialization will only get compiled into the instruction sequence if these parameters are met exactly (e.g., if you called `1.+(2, 3) {}` then it would not specialize to `opt_plus`).

It's worth looking at the C code that implements this instruction to get a better sense of what it is doing. Don't worry if you're unfamiliar with C, we'll walk through each part in turn.

When you're looking at the implementation of instructions in YARV, your first stop is `insns.def`. This file contains a DSL that is used to generate the C code that implements the instructions. The `opt_plus` instruction is defined as follows:

```c
DEFINE_INSN
opt_plus
(CALL_DATA cd)
(VALUE recv, VALUE obj)
(VALUE val)
{
    val = vm_opt_plus(recv, obj);

    if (val == Qundef) {
        CALL_SIMPLE_METHOD();
    }
}
```

Every instructions begins with `DEFINE_INSN`. The next lines are:

* the name of the instruction
* the operands to the instruction
* the objects that are popped off the stack (in this case the values on the left and right side of the `+` operator)
* the objects that are pushed onto the stack

Next is the C code that implements the instruction. We can see in this case that `recv` and `obj` are popped off the stack, then passed immediately to the `vm_opt_plus` function. The return value of that function is assigned to `val` which is going to be pushed onto the stack when the instruction is done executing. If the return value is `Qundef`, then instead we fall back to the same code that the unspecialized `send` instruction would use.

The `vm_opt_plus` function is therefore doing most of the heavy lifting here, so let's take a look at that next. For the most part, these helper functions are defined in `vm_insnhelper.c`. I've reformatted and restructured the function slightly to make it easier to read, but the code is otherwise unchanged.

```c
static VALUE
vm_opt_plus(VALUE recv, VALUE obj)
{
  // adding two tagged integers
  if (FIXNUM_2_P(recv, obj) && BASIC_OP_UNREDEFINED_P(BOP_PLUS, INTEGER_REDEFINED_OP_FLAG)) {
    return rb_fix_plus_fix(recv, obj);
  }

  // adding two tagged floats
  if (FLONUM_2_P(recv, obj) && BASIC_OP_UNREDEFINED_P(BOP_PLUS, FLOAT_REDEFINED_OP_FLAG)) {
    return DBL2NUM(RFLOAT_VALUE(recv) + RFLOAT_VALUE(obj));
  }

  // skip true/false/nil
  if (SPECIAL_CONST_P(recv) || SPECIAL_CONST_P(obj)) {
    return Qundef;
  }

  // adding two floats
  if (RBASIC_CLASS(recv) == rb_cFloat && RBASIC_CLASS(obj)  == rb_cFloat && BASIC_OP_UNREDEFINED_P(BOP_PLUS, FLOAT_REDEFINED_OP_FLAG)) {
    return DBL2NUM(RFLOAT_VALUE(recv) + RFLOAT_VALUE(obj));
  }

  // adding two strings
  if (RBASIC_CLASS(recv) == rb_cString && RBASIC_CLASS(obj) == rb_cString && BASIC_OP_UNREDEFINED_P(BOP_PLUS, STRING_REDEFINED_OP_FLAG)) {
    return rb_str_opt_plus(recv, obj);
  }

  // adding two arrays
  if (RBASIC_CLASS(recv) == rb_cArray && RBASIC_CLASS(obj) == rb_cArray && BASIC_OP_UNREDEFINED_P(BOP_PLUS, ARRAY_REDEFINED_OP_FLAG)) {
    return rb_ary_plus(recv, obj);
  }

  // otherwise
  return Qundef;
}
```

You can see that the function is checking for a number of different cases. If the receiver and the argument are both tagged integers, then it will call `rb_fix_plus_fix` to add them. If they are both tagged floats, then it will add them directly. If they are both floats, then it will add them directly. If they are both strings, then it will call `rb_str_opt_plus` to add them. If they are both arrays, then it will call `rb_ary_plus` to add them. Otherwise, it will return `Qundef` to indicate that it doesn't know how to handle the case, and the unspecialized code should run.

This is the general structure of all of the specializations. They check for a number of different cases on a number of different types, and if they can handle the case, they do the work and return the result. If they can't handle the case, they return `Qundef` to indicate that the unspecialized code should run.

You can see there's a lot of usage of the `BASIC_OP_UNREDEFINED_P` macro in this code. That macro checks a flag that lives on the virtual machine itself that keeps track of whenever basic operators are redefined. For example, if you were to define in your Ruby code:

```ruby
# please don't ever do this
class Integer
  def +(other)
    self - other
  end
end
```

then a flag on the virtual machine would be set that would cause `BASIC_OP_UNREDEFINED_P` to return `false` for `BOP_PLUS` and `INTEGER_REDEFINED_OP_FLAG`. This would cause the `vm_opt_plus` function to return `Qundef` for any case where the receiver and argument are both tagged integers.

It's worth noting that these type checks are going to be run every time the instruction is run. For the most part they're very fast because they're just checking a couple of bits in the object header, but it's still worth keeping in mind that they're not free.[^1]

Now that we understand that these specializations provide fast paths for common cases, we can dig into the full list. We're not going to go through the implementation of all of them (you're welcome to browse the source yourself!), but we'll discuss the context of each of them. There are a total of 31 specializations of `send`, so strap in.

## Arithmetic specializations

These five specializations are for arithmetic operations. These are compiled whenever an infix operator is used with a single positional argument and no block. The instructions and their corresponding operators are:

* `opt_plus` - `+`
* `opt_minus` - `-`
* `opt_mult` - `*`
* `opt_div` - `/`
* `opt_mod` - `%`

## Bitwise specializations

These two specializations are for bitwise operations. These are compiled whenever an infix operator is used with a single positional argument and no block. The instructions and their corresponding operators are:

* `opt_and` - `&`
* `opt_or` - `|`

Note that even though they are named `opt_and` and `opt_or`, these are very different from the `and` and `or` keywords in Ruby which cause changes in control-flow and are not method calls. Similarly, these instructions are unrelated to the `||` and `&&` operators which are also not method calls.

## Unary specializations

These seven specializations correspond to common method calls[^2] that are invoked on objects without any arguments. The instructions and their corresponding method names are:

* `opt_not` - `!`
* `opt_empty_p` - `empty?`
* `opt_length` - `length`
* `opt_nil_p` - `nil?`
* `opt_reverse` - `reverse`
* `opt_size` - `size`
* `opt_succ` - `succ`

## Comparison specializations

These six specializations correspond to infix comparison operators. These are compiled whenever an infix operator is used with a single positional argument and no block. The instructions and their corresponding operators are:

* `opt_gt` - `>`
* `opt_ge` - `>=`
* `opt_lt` - `<`
* `opt_le` - `<=`
* `opt_eq` - `==`
* `opt_neq` - `!=`

Note that the `opt_neq` instruction is a bit special. It's the only instruction in this list that actually has two operands. The first is a call data object that contains the information for a `==` method call. The second is a call data object that contains the information for a `!=` method call. This is because `!=` can be implemented by negating the result of the `==` method call.

## Matching specialization

This specialization is `opt_regexpmatch2`, which is compiled whenever the `=~` infix operator is used. This instruction has its own name because it triggers the matched regular expression (if there is one) to set special local and global variables. We'll talk more about this when we get to the `getspecial` instruction.

It's worth taking a quick look at the C implementation of this one as well. Much like `opt_plus`, it delegates most of its work to a VM helper method in its instruction definition.

```c
DEFINE_INSN
opt_regexpmatch2
(CALL_DATA cd)
(VALUE obj2, VALUE obj1)
(VALUE val)
{
  val = vm_opt_regexpmatch2(obj2, obj1);

  if (val == Qundef) {
    CALL_SIMPLE_METHOD();
  }
}
```

Notice how similar that looks to the `opt_plus` implementation. For a more full view, here is the implementation of `vm_opt_regexpmatch2`, which is delegates most of its work to:

```c
static VALUE
vm_opt_regexpmatch2(VALUE recv, VALUE obj)
{
  // skip true/false/nil
  if (SPECIAL_CONST_P(recv)) {
    return Qundef;
  }

  // string =~ regexp
  if (RBASIC_CLASS(recv) == rb_cString && CLASS_OF(obj) == rb_cRegexp && BASIC_OP_UNREDEFINED_P(BOP_MATCH, STRING_REDEFINED_OP_FLAG)) {
    return rb_reg_match(obj, recv);
  }

  // regexp =~ other
  if (RBASIC_CLASS(recv) == rb_cRegexp && BASIC_OP_UNREDEFINED_P(BOP_MATCH, REGEXP_REDEFINED_OP_FLAG)) {
    return rb_reg_match(recv, obj);
  }

  // otherwise
  return Qundef;
}
```

Here you can see that in the specialized form, the `rb_reg_match` function is called. A bunch of function calls are made after that, but there is a chain that goes `rb_reg_match` to `reg_match_pos` to `rb_reg_search_set_match` to `onig_search`. `onig_search` is a function defined by the [Onigmo](https://github.com/k-takata/Onigmo) library, which is the library that CRuby embeds to handle regular expressions. So you can see that this instruction leads directly to calling into that library.

## Collection specializations

These three specializations are for methods that are commonly defined on collections (e.g., arrays and hashes).

* `opt_ltlt` - compiled whenever the `<<` method is used with one argument, as in `array << 1`
* `opt_aref` - compiled whenever the `[]` method is used with one argument, as in `array[1]`
* `opt_aset` - compiled whenever the `[]=` method is used with two arguments, as in `array[1] = 2`

## String specializations

These four specializations are used in combination with unfrozen strings. Before the `frozen_string_literal` pragma was developed, a lot of repositories in the Ruby ecosystem began receiving pull requests to freeze all of the strings in their source. While the `frozen_string_literal` pragma made this situation much better, there is still a lot of code that operates on unfrozen strings or attempts to freeze unfrozen strings. These specializations are used to optimize those cases.

* `opt_str_freeze` - compiled whenever `#freeze` is called on an unfrozen string. This is actually a peephole optimization that is added in after the other instructions have been compiled to reduce the common `putstring` to `send #freeze` sequence
* `opt_str_uminus` - compiled whenever `#-@` is called on an unfrozen string. Similar to `opt_str_freeze`, this is a peephole optimization that is added in after the other instructions have been compiled
* `opt_aref_with` - compiled whenever `opt_aref` is being called with a known string value
* `opt_aset_with` - compiled whenever `opt_aset` is being called with a known string value

## Array specializations

These two specializations are used to optimize the `max` and `min` methods on array literals. Typically when you call a method on an array literal it will either be a `duparray` or `newarray` instruction and then a `send`. However, if the array is going to be dropped from the stack after the method call, then it's more efficient to never allocate the array in the first place and to instead use the values directly on the stack. This is what these two specializations do.

* `opt_newarray_max` - compiled whenever `#max` is called on an array literal
* `opt_newarray_min` - compiled whenever `#min` is called on an array literal

## Block specialization

This is a different kind of specialization than the others that we've looked at in this post. So far all of the specializations we've seen have been to increase speed by providing more efficient versions of instructions. This specialization — `opt_send_without_block` — is a bit different. It's a specialization that is used to save on space.

The `send` instruction always has space for an instruction sequence operand corresponding to a given block as its second operand. If we know at compile time that we never have a block for a given call site, we can instead replace it with `opt_send_without_block`, which only has space allocated for the call data object. It turns out that most of the time, methods aren't being called with blocks, and so this can result in quite a lot of space saving.

## Wrapping up

In this post we looked at all of the specializations of the `send` instruction, of which there are quite a few. A couple of things to take away from this post:

* The `send` instruction is one of the most common instructions in Ruby code, and so it's important to optimize it as much as possible.
* Most specializations of `send` exist to provide fast implementations of common methods, such as `#+` and `#[]`.

In the next post we'll start digging into local variable instructions, and as such will be digging even more into the frame stack.

---

[^1]: This is one of the main advantages of a JIT compiler that uses lazy basic-block versioning like YJIT. When this instruction is being compiled by YJIT, it will compile a version of the instruction that is specialized to whatever type is on the top of the stack, following the logic that most of the time, call sites are monomorphic. A small guard will be placed at the beginning of the instruction to ensure that the type remains the same. If the type is different, then the instruction can be recompiled to handle the new type. This way, the type checks only need to be run once, and the instruction can be optimized for the type that it's actually going to be run with.
[^2]: The use of the word "common" here is of course very subjective. It very much depends on the body of Ruby code that you're using to drive your benchmarking. For a long time, the [optcarrot](https://github.com/mame/optcarrot) project was used to check the performance of various Ruby implementations. Some of the specializations in this file are therefore a direct result of the design of that project. Which is great for all of you that are running NES emulators in production.
