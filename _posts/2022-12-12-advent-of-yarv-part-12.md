---
layout: post
title: Advent of YARV
subtitle: Part 12 - Global variables
meta:
  "twitter:card": summary
  "twitter:title": "Advent of YARV: Part 12"
  "twitter:description": "This post is part of a series about how the YARV virtual machine works."
  "twitter:site": "@kddnewton"
  "twitter:image": https://upload.wikimedia.org/wikipedia/commons/thumb/7/73/Ruby_logo.svg/1200px-Ruby_logo.svg.png
---

This blog series is about how the CRuby virtual machine works. If you're new to the series, I recommend starting from [the beginning](/2022/11/30/advent-of-yarv-part-0). This post is about global variables.

YARV has two instructions in its instruction set that relate to global variables: `getglobal` and `setglobal`. They each have a single operand: the name of the global as a symbol. The instructions themselves pretty straightforward, but global variables can be tricky and actually come in a couple of different forms.

* [getglobal](#getglobal)
* [setglobal](#setglobal)

## `getglobal`

Global variables are stored in the global `rb_global_tbl` table. This is an internal hash table used by CRuby that has `ID`s for keys (the structure that backs Ruby symbols) and `struct rb_global_entry *` for values. The `rb_global_entry` structure is defined in `variable.c` and looks like this:

```c
struct rb_global_entry {
  struct rb_global_variable *var;
  ID id;
  bool ractor_local;
};
```

It stores a pointer to the `struct rb_global_variable` that holds the actual value of the global variable, the `ID` of the global variable (the name), and a boolean indicating whether the global variable is ractor-local. Taking this one step further, let's look at the structure of `rb_global_variable`:

```c
struct rb_global_variable {
  int counter;
  int block_trace;
  VALUE *data;
  rb_gvar_getter_t *getter;
  rb_gvar_setter_t *setter;
  rb_gvar_marker_t *marker;
  rb_gvar_compact_t *compactor;
  struct trace_var *trace;
};
```

The fields toward the bottom of that struct are all function pointers. This is where the variation in global variables comes into play. For the most part, the global that you'll be dealing with will store their value directly in the `data` field that you see there. However, there are some cases where the global variable is calculated on the fly, and in those cases, the `getter` field will be set to a function that will calculate the value of the global variable. The `setter` field is used for the same purpose, but for setting the value of the global variable. The `marker` and `compactor` fields are used for garbage collection, and the `trace` field is used for tracing.

As an example, let's consider the global variable we encountered when we looked at the `getspecial` instruction: `$_`. This global refers to the last line read by an IO method. The `rb_gvar_getter_t *` for this global is actually assigned to `get_LAST_READ_LINE`, which then delegates to `rb_lastline_get`, which in turn delegates to `vm_svar_get(GET_EC(), VM_SVAR_LASTLINE)`. That function is actually the same code path as the `getspecial` instruction that we looked at previously.

The role of the `getglobal` instruction is therefore to fetch the entry corresponding to the name in the global variables table and then to call the getter function associated with that entry passing in the `rb_global_entry.id` field and the `rb_global_variable.data` field as arguments. The getter function will then return the value of the global variable. Once the value has been calculated, it is pushed onto the stack. For example, with `getglobal :$0`:

<div align="center">
   <img src="/assets/aoy/part12-getglobal.svg" alt="getglobal">
</div>

In Ruby:

```ruby
class GetGlobal
  attr_reader :name

  def initialize(name)
    @name = name
  end

  def call(vm)
    vm.stack.push(vm.globals[name])
  end
end
```

In `$0` disassembly:

```
== disasm: #<ISeq:<main>@-e:1 (1,0)-(1,2)> (catch: false)
0000 getglobal                              :$0                       (   1)[Li]
0002 leave
```

## `setglobal`

Much like `getglobal`, `setglobal` is responsible for fetching the entry for the global variable corresponding to the name given by its only operand from the global variable table. It then calls the setter function associated with that entry, passing in the value to set the variable to which is popped off the top of the stack, the `rb_global_entry.id` field, and the `rb_global_variable.data` field as arguments. The setter function will then set the value of the global variable. For example, with `setglobal :$0`:

<div align="center">
  <img src="/assets/aoy/part12-setglobal.svg" alt="setglobal">
</div>

In Ruby:

```ruby
class SetGlobal
  attr_reader :name

  def initialize(name)
    @name = name
  end

  def call(vm)
    vm.globals[name] = vm.stack.pop
  end
end
```

In `$0 = "!!"` disassembly:

```
== disasm: #<ISeq:<main>@-e:1 (1,0)-(1,9)> (catch: false)
0000 putstring                              "!!"                      (   1)[Li]
0002 dup
0003 setglobal                              :$0
0005 leave
```

## Wrapping up

Believe it or not we are halfway through the series in terms of posts, and we are 77 instructions in to the list of 105 instructions that we are going to look at! In _this_ post we talked about the two instructions in YARV that correspond to global variables: `getglobal` and `setglobal`. A few things to remember from this post:

* Global variables are stored in the global `rb_global_tbl` table.
* Global variables can be calculated on the fly, depending on the way they were set up.

In the next post we'll look at the last kind of variable in Ruby: constants.
