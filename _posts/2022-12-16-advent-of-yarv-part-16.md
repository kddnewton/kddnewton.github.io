---
layout: post
title: Advent of YARV
subtitle: Part 16 - Defining methods
meta:
  "twitter:card": summary
  "twitter:title": "Advent of YARV: Part 16"
  "twitter:description": "This post is part of a series about how the YARV virtual machine works."
  "twitter:site": "@kddnewton"
  "twitter:image": https://upload.wikimedia.org/wikipedia/commons/thumb/7/73/Ruby_logo.svg/1200px-Ruby_logo.svg.png
---

This blog series is about how the CRuby virtual machine works. If you're new to the series, I recommend starting from [the beginning](/2022/11/30/advent-of-yarv-part-0). This post is about defining methods.

In the previous post we looked at the `defineclass` instruction, which defined a class, singleton class, or module. It then pushed a frame onto the frame stack and executed the instructions within it within the context of the new class, singleton class, or module.

In today's post we're going to look at `definemethod` and `definesmethod`, both instructions for defining methods on classes. While these instructions look very similar to `defineclass` on the surface, they function quite differently. Where `defineclass` immediately executes the instructions in the context of the new class, `definemethod` and `definesmethod` associate their given instruction sequence with the method but do not execute them until those methods are called.

Both `definemethod` and `definesmethod` have two operands. The first is an `ID` corresponding to the name of the method being defined. The second is the instruction sequence that corresponds to the body of the method. Neither instruction push anything onto the stack. `definemethod` pops nothing off of it either. `definesmethod` pops a single value off of the stack, which is the object on which the method is being defined.

The instruction definitions in `insns.def` are as follows:

```c
DEFINE_INSN
definemethod
(ID id, ISEQ iseq)
()
()
{
    vm_define_method(ec, Qnil, id, (VALUE)iseq, FALSE);
}

DEFINE_INSN
definesmethod
(ID id, ISEQ iseq)
(VALUE obj)
()
{
    vm_define_method(ec, obj, id, (VALUE)iseq, TRUE);
}
```

You can see they're mostly delegating their work to `vm_define_method`, which is defined in `vm_insnhelper.c`:

```c
static void
vm_define_method(const rb_execution_context_t *ec, VALUE obj, ID id, VALUE iseqval, int is_singleton)
{
    VALUE klass;
    rb_method_visibility_t visi;
    rb_cref_t *cref = vm_ec_cref(ec);

    if (is_singleton) {
        klass = rb_singleton_class(obj);
        visi = METHOD_VISI_PUBLIC;
    }
    else {
        klass = CREF_CLASS_FOR_DEFINITION(cref);
        visi = vm_scope_visibility_get(ec);
    }

    rb_add_method_iseq(klass, id, (const rb_iseq_t *)iseqval, cref, visi);
}
```

I've simplified this function a bit but the essence is still there. This function basically boils down to gathering up some more information and eventually calling `rb_add_method_iseq`. You can see it's searching for the class on which to define the method and defining the visibility of the method (methods defined on a singleton class `def self.foo` are always public).

`rb_add_method_iseq` gathers up even more information and then calls `rb_add_method` which does this again and then finally calls `rb_method_entry_make`. This function is where the method is actually defined and added into the method table.

That's really all there is to it. `definemethod` and `definesmethod` both associate a given instruction sequence with a method entry in a method table. The instructions contained within those instruction sequences are executed when the method is called. Let's look at a couple of disassembly examples.

## Defining methods

Let's define a simple method named `foo` that always returns `1`:

```ruby
def foo
  1
end
```

In the disassembly we'll see:

```
== disasm: #<ISeq:<main>@test.rb:1 (1,0)-(3,3)> (catch: false)
0000 definemethod                           :foo, foo                 (   1)[Li]
0003 putobject                              :foo
0005 leave

== disasm: #<ISeq:foo@test.rb:1 (1,0)-(3,3)> (catch: false)
0000 putobject_INT2FIX_1_                                             (   2)[LiCa]
0001 leave                                                            (   3)[Re]
```

You can see `definemethod` is the first instruction compiled. It accepts the name of the method being defined (`:foo` in this case) and the instruction sequence for the method body (an instruction sequence named `foo` in this case). That instruction sequence is then disassembled and we can see it contains the instructions for the method body. After the method is defined, `putobject` is called with the name of the method (`:foo` in this case), because using `def foo` always returns `:foo`.

## Defining singleton methods

Now let's define a singleton method named `foo` that also always returns `1`:

```ruby
def Object.foo
  1
end
```

You can see here we're defining a singleton method on the value referred to by the `Object` constant. In the disassembly we'll see:

```
== disasm: #<ISeq:<main>@test.rb:1 (1,0)-(3,3)> (catch: false)
0000 opt_getconstant_path                   <ic:0 Object>             (   1)[Li]
0002 definesmethod                          :foo, foo
0005 putobject                              :foo
0007 leave

== disasm: #<ISeq:foo@test.rb:1 (1,0)-(3,3)> (catch: false)
0000 putobject_INT2FIX_1_                                             (   2)[LiCa]
0001 leave                                                            (   3)[Re]
```

The `opt_getconstant_path` instruction will push the value referred to by the `Object` constant onto the stack. The `definesmethod` instruction pops that value off of the stack and uses it to define the singleton method. The rest of the disassembly is the same as the previous example.

## Wrapping up

In this post we looked at both the `definemethod` and `definesmethod` instructions. They are used to define methods on classes and singleton classes. A couple of things to remember from this post:

* `definemethod` and `definesmethod` both associate a given instruction sequence with a method entry in a method table. The instructions contained within those instruction sequences are executed when the method is called.
* Instructions that take instruction sequences as operands do not necessarily execute those instruction sequences immediately. This may seem obvious in hindsight, but it can trip people up.

In this post we looked at defining methods, but purposefully left out the fact that methods can have arguments. In the next post we'll take a look at all of the different kinds of arguments in Ruby and how YARV implements them.
