---
layout: post
title: Advent of YARV
subtitle: Part 11 - Class and instance variables
meta:
  "twitter:card": summary
  "twitter:title": "Advent of YARV: Part 11"
  "twitter:description": "This post is part of a series about how the YARV virtual machine works."
  "twitter:site": "@kddnewton"
  "twitter:image": https://upload.wikimedia.org/wikipedia/commons/thumb/7/73/Ruby_logo.svg/1200px-Ruby_logo.svg.png
---

This blog series is about how the CRuby virtual machine works. If you're new to the series, I recommend starting from [the beginning](/2022/11/30/advent-of-yarv-part-0). This post is about how YARV handles class and instance variables.

In Ruby, objects need to be able to store state. This is done through the use of class and instance variables. This post is not about what these variables are and how to use them, I'm assuming you know that already. Instead, this post focuses on how they are implemented in YARV. There are four instructions in YARV corresponding to class and instance variables. They are the subject of today's post.

* [getclassvariable](#getclassvariable)
* [setclassvariable](#setclassvariable)
* [getinstancevariable](#getinstancevariable)
* [setinstancevariable](#setinstancevariable)

## `getclassvariable`

Whenever you use a class variable, YARV will compile a `getclassvariable` instruction. The instruction has two operands: the name of the class variable as a symbol and an inline cache.

The inline cache is used to cache the lookup to find where the class variable value is stored - not the value of the class variable itself. The cache key is the value of `ruby_vm_global_cvar_state`, a global variable used by the entire Ruby runtime that is incremented any time something happens in the VM that could result in a different lookup (e.g., a module being included).[^1]

Once the storage location has been determined either through the cache or a fresh lookup, the value at that location is retrieved and pushed onto the stack.

<div align="center">
  <img src="/assets/aoy/part11-getinstancevariable.svg" alt="getclassvariable">
</div>

The diagram here leaves a bit to be desired, since the stack is not the most complex part of this instruction. If we were to look at this in Ruby:

```ruby
class GetClassVariable
  attr_reader :name, :cache

  def initialize(name, cache)
    @name = name
    @cache = cache
  end

  def call(vm)
    clazz =
      cache.fetch do
        _self = vm._self
        _self.is_a?(Class) ? _self : _self.class
      end

    vm.stack.push(clazz.class_variable_get(name))
  end
end
```

In `@@foo` disassembly:

```
== disasm: #<ISeq:<main>@-e:1 (1,0)-(1,5)> (catch: false)
0000 getclassvariable                       :@@foo, <is:0>            (   1)[Li]
0003 leave
```

## `setclassvariable`

The `setclassvariable` is compiled whenever you assign to a class variable. It has the same operands as `getclassvariable`, and performs the same lookup to determine where the value is stored. Once the location is determined, the value is popped off the stack and stored there.

One interesting thing to note is that if the same class variable is being referenced within the same instruction sequence, it will use the same inline cache.

<div align="center">
  <img src="/assets/aoy/part11-setinstancevariable.svg" alt="setclassvariable">
</div>

In Ruby:

```ruby
class SetClassVariable
  attr_reader :name, :cache

  def initialize(name, cache)
    @name = name
    @cache = cache
  end

  def call(vm)
    clazz =
      cache.fetch do
        _self = vm._self
        _self.is_a?(Class) ? _self : _self.class
      end

    clazz.class_variable_set(name, vm.stack.pop)
  end
end
```

In `@@foo = 1` disassembly:

```
== disasm: #<ISeq:<main>@-e:1 (1,0)-(1,9)> (catch: false)
0000 putobject_INT2FIX_1_                                             (   1)[Li]
0001 dup
0002 setclassvariable                       :@@foo, <is:0>
0005 leave
```

## `getinstancevariable`

Instance variables used to work in a very similar way to class variables. They would cache the lookup of the storage location in the inline cache and then retrieve the value from that location. This has changed recently in Ruby 3.2 with the introduction of object shapes.

The implementation details of the object shapes mechanism are far outside the scope of this post, but the gist is that we can store instance variables in an array instead of a hash by caching the index of the instance variable in the object shape. This results in much faster access to instance variables. The value of the cache is both an object shape and the index of the instance variable in the object shape.

<div align="center">
  <img src="/assets/aoy/part11-getinstancevariable.svg" alt="getinstancevariable">
</div>

I'm not going to attempt to translate this into Ruby because any example I gave you would be quite a bit different from how it's actually implemented. However, for a disassembly example, here's `@foo`:

```ruby
== disasm: #<ISeq:<main>@-e:1 (1,0)-(1,4)> (catch: false)
0000 getinstancevariable                    :@foo, <is:0>             (   1)[Li]
0003 leave
```

## `setinstancevariable`

Similar to `getinstancevariable`, `setinstancevariable` has an inline cache that caches the object shape and the index of the instance variable in the object shape. The value is popped off the stack and stored at the storage location indicated by these two factors.

Note that for instance variables because they use object shapes now, the inline cache is no longer shared between instructions.

<div align="center">
  <img src="/assets/aoy/part11-setinstancevariable.svg" alt="setinstancevariable">
</div>

Again, I'm going to forgo translating this into Ruby because it would be quite different from the actual implementation. For disassembly, here's `@foo = 1`:

```
== disasm: #<ISeq:<main>@-e:1 (1,0)-(1,8)> (catch: false)
0000 putobject_INT2FIX_1_                                             (   1)[Li]
0001 dup
0002 setinstancevariable                    :@foo, <is:0>
0005 leave
```

## Wrapping up

In this post we discussed class and instance variables. We saw they are stored and use caches to improve lookup speeds. A couple of things to remember from this post:

* Inline caches are operands to instructions that are used to store some kind of state. In the case of class variables, they store the class that owns the class variable. In the case of instance variables, they store the object shape and the index of the instance variable in the object shape.
* Cache busting is an incredibly hard problem. YARV has different schemes for different kinds of caches, and different approaches are being explored all of the time. While class variables are keyed off a global cache key, instance variables use object shapes. In a future post we'll see that constant lookups introduce another scheme entirely.

In the next post we'll continue looking at types of variables by digging into global variables.

---

[^1]: The inline cache for class variables didn't come into play until Ruby 3.0. Prior to that, the instruction only had one operand and the class to look up the variable was determined every time the instruction ran. This led to many blog posts and linters deciding that class variables were bad and should be avoided on account of performance. Thanks to Eileen Uchitelle and Aaron Patterson, this is no longer the case. But you still may want to avoid them for other reasons.
