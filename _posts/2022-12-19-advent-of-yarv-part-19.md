---
layout: post
title: Advent of YARV
subtitle: Part 19 - Defined
meta:
  "twitter:card": summary
  "twitter:title": "Advent of YARV: Part 19"
  "twitter:description": "This post is part of a series about how the YARV virtual machine works."
  "twitter:site": "@kddnewton"
  "twitter:image": https://upload.wikimedia.org/wikipedia/commons/thumb/7/73/Ruby_logo.svg/1200px-Ruby_logo.svg.png
---

This blog series is about how the CRuby virtual machine works. If you're new to the series, I recommend starting from [the beginning](/2022/11/30/advent-of-yarv-part-0). This post is about the `defined?` keyword.

The `defined?` keyword is a very interesting keyword that accepts absolutely any Ruby expression as an argument. It is responsible with returning a string that describes the type of the expression. For example, `defined?(1)` returns `"expression"` and `defined?(puts)` returns `"method"`. If the value is not defined, `nil` is returned.

The keyword itself corresponds to the `defined` instruction. This instruction has three operands: the type of expression to check, the object associated with the expression, and the string to push onto the stack if the value is defined. It pops a single value off the stack, and pushes a single value onto the stack.

The behavior of this instruction changes quite a bit depending on its first operand, which is the type of expression to check. The enum that this integer value corresponds to is defined in `iseq.h`:

```c
enum defined_type {
  DEFINED_NOT_DEFINED,
  DEFINED_NIL = 1,
  DEFINED_IVAR,
  DEFINED_LVAR,
  DEFINED_GVAR,
  DEFINED_CVAR,
  DEFINED_CONST,
  DEFINED_METHOD,
  DEFINED_YIELD,
  DEFINED_ZSUPER,
  DEFINED_SELF,
  DEFINED_TRUE,
  DEFINED_FALSE,
  DEFINED_ASGN,
  DEFINED_EXPR,
  DEFINED_REF,
  DEFINED_FUNC,
  DEFINED_CONST_FROM
};
```

Although it's possible to trigger code paths that will exercise each of these, in reality we only need to talk about a subset because the rest get optimized into a single `putstring`/`putobject` instruction because it's information known at compile-time. With that in mind, below are the ones that perform something dynamic.

## `DEFINED_IVAR`

In Ruby, this looks like:

```ruby
defined?(@foo)
```

In YARV disassembly, this looks like:

```
== disasm: #<ISeq:<main>@-e:1 (1,0)-(1,14)> (catch: false)
0000 putnil                                                           (   1)[Li]
0001 defined                                instance-variable, :@foo, "instance-variable"
0005 leave
```

Inside a switch statement that checks the kind of defined expression based on the first operand, the check boils down to:

```c
rb_ivar_defined(GET_SELF(), SYM2ID(obj));
```

This will check if the current value of self has an instance variable with the given name. Note that even if the value is `nil`, this will still return true.

## `DEFINED_GVAR`

In Ruby:

```ruby
defined?($foo)
```

In YARV:

```
== disasm: #<ISeq:<main>@-e:1 (1,0)-(1,14)> (catch: false)
0000 putnil                                                           (   1)[Li]
0001 defined                                global-variable, :$foo, "global-variable"
0005 leave
```

In C:

```c
rb_gvar_defined(SYM2ID(obj));
```

This will check if there is an entry in the global table corresponding to the given name. Note that even if the value is `nil`, this will still return true.

## `DEFINED_CVAR`

In Ruby:

```ruby
defined?(@@foo)
```

In YARV:

```
== disasm: #<ISeq:<main>@-e:1 (1,0)-(1,15)> (catch: false)
0000 putnil                                                           (   1)[Li]
0001 defined                                class variable, :@@foo, "class variable"
0005 leave
```

In C:

```c
rb_cvar_defined(vm_get_cvar_base(vm_get_cref(GET_EP()), GET_CFP(), 0), SYM2ID(obj));
```

This will check if there is an entry in the instance variable table corresponding to the given name.

## `DEFINED_CONST`

In Ruby:

```ruby
defined?(Foo)
```

In YARV:

```ruby
== disasm: #<ISeq:<main>@-e:1 (1,0)-(1,13)> (catch: false)
0000 putnil                                                           (   1)[Li]
0001 defined                                constant, :Foo, "constant"
0005 leave
```

In C:

```c
vm_get_ev_const(ec, v, SYM2ID(obj), true, true);
```

This checks if there is a constant defined with the given name. The fourth argument indicates that it should also check the nesting since it is a relative path to a constant.

## `DEFINED_CONST_FROM`

In Ruby:

```ruby
defined?(::Foo)
```

In YARV:

```
== disasm: #<ISeq:<main>@-e:1 (1,0)-(1,15)> (catch: false)
0000 putobject                              Object                    (   1)[Li]
0002 defined                                constant-from, :Foo, "constant"
0006 leave
```

In C:

```c
vm_get_ev_const(ec, v, SYM2ID(obj), false, true);
```

This checks if there is a constant defined with the given name at the given scoped path. The fourth argument indicates that it should not check the nesting since it is an absolute path to a constant.

## `DEFINED_FUNC`

In Ruby:

```ruby
defined?(puts)
```

In YARV:

```
== disasm: #<ISeq:<main>@-e:1 (1,0)-(1,14)> (catch: false)
0000 putself                                                          (   1)[Li]
0001 defined                                func, :puts, "method"
0005 leave
```

In C:

```c
rb_ec_obj_respond_to(ec, CLASS_OF(v), SYM2ID(obj), TRUE);
```

This checks if the class for the current value of self responds to the given method name.

## `DEFINED_METHOD`

In Ruby:

```ruby
foo = 1
defined?(foo.bar)
```

In YARV:

```
== disasm: #<ISeq:<main>@test.rb:1 (1,0)-(2,17)> (catch: true)
== catch table
| catch type: rescue st: 0004 ed: 0010 sp: 0000 cont: 0012
| == disasm: #<ISeq:defined guard in <main>@test.rb:0 (0,0)-(-1,-1)> (catch: false)
| local table (size: 1, argc: 0 [opts: 0, rest: -1, post: 0, block: -1, kw: -1@-1, kwrest: -1])
| [ 1] $!@0
| 0000 putnil
| 0001 leave
|------------------------------------------------------------------------
local table (size: 1, argc: 0 [opts: 0, rest: -1, post: 0, block: -1, kw: -1@-1, kwrest: -1])
[ 1] foo@0
0000 putobject_INT2FIX_1_                                             (   1)[Li]
0001 setlocal_WC_0                          foo@0
0003 putnil                                                           (   2)[Li]
0004 getlocal_WC_0                          foo@0
0006 defined                                method, :bar, "method"
0010 swap
0011 pop
0012 leave
```

In C:

```c
const rb_method_entry_t *me = rb_method_entry_with_refinements(CLASS_OF(v), SYM2ID(obj), NULL);

if (me) {
  switch (METHOD_ENTRY_VISI(me)) {
    case METHOD_VISI_PRIVATE:
      break;
    case METHOD_VISI_PROTECTED:
      if (!rb_obj_is_kind_of(GET_SELF(), rb_class_real(me->defined_class))) {
        break;
      }
    case METHOD_VISI_PUBLIC:
      return true;
    default:
      rb_bug("vm_defined: unreachable: %u", (unsigned int)METHOD_ENTRY_VISI(me));
  }
}
else {
  return check_respond_to_missing(obj, v);
}
```

There are a couple of things happening here that are a bit new. First of all, you'll notice that for the first time in this blog series, you can see `(catch: true)` on the first line of the disassembly. We're going to cover what that actually means in tomorrow's post. Second of all you can see that this check in C is much more complex than the others. That's because the `defined` instruction takes into account method visibility when checking if a method is defined on an explicit receiver.

## `DEFINED_YIELD`

In Ruby:

```ruby
defined?(yield)
```

In YARV:

```
== disasm: #<ISeq:<main>@-e:1 (1,0)-(1,15)> (catch: false)
0000 putnil                                                           (   1)[Li]
0001 defined                                yield, false, "yield"
0005 leave
```

In C:

```c
GET_BLOCK_HANDLER() != VM_BLOCK_HANDLER_NONE;
```

This checks if there is a block handler on the frame stack. If there is, then it means that a block was passed to the current method.

## `DEFINED_ZSUPER`

In Ruby:

```ruby
defined?(super)
```

In YARV:

```
== disasm: #<ISeq:<main>@-e:1 (1,0)-(1,15)> (catch: false)
0000 putnil                                                           (   1)[Li]
0001 defined                                super, false, "super"
0005 leave
```

In C:

```c
const rb_callable_method_entry_t *me = rb_vm_frame_method_entry(GET_CFP());

if (me) {
  VALUE klass = vm_search_normal_superclass(me->defined_class);
  ID id = me->def->original_id;

  return rb_method_boundp(klass, id, 0);
}
```

Somewhat confusingly, even if you pass arguments to the super call within the `defined?` keyword, it will still be `DEFINED_ZSUPER`. This checks that a super method for the current method exists.

## `DEFINED_REF`

In Ruby:

```ruby
defined?($1)
```

In YARV:

```
== disasm: #<ISeq:<main>@-e:1 (1,0)-(1,12)> (catch: false)
0000 putnil                                                           (   1)[Li]
0001 defined                                ref, :$1, "global-variable"
0005 leave
```

In C:

```c
vm_getspecial(ec, GET_LEP(), Qfalse, FIX2INT(obj)) != Qnil;
```

This checks if the given global variable is defined that corresponds to a capture group or a special back reference.

## Wrapping up

The `defined` instruction implements the `defined?` keyword, and it can come in quite a few different flavors. Each one will either push a string or `nil` onto the stack. A couple of things to remember from this post:

* Sometimes the `defined` instruction will create a catch table entry if the expression inside would potentially raise an exception.
* The `defined` instruction will check method visibility when checking if a method is defined on an explicit receiver.

In the next post we'll go over what it means to have catch table entries and how they work.
