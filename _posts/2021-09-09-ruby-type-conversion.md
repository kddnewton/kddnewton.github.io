---
layout: post
title: Ruby type conversion
---

Let's talk about type conversion in Ruby.

First, we're going to need some definitions:

* `type`  
the kind of object the program is currently dealing with. In Ruby this _usually_ breaks down to the class of the object (e.g., `String` or `Integer`).
* `type conversion`  
the process of converting an object from one type to another type. Type conversion is an umbrella term, encapsulating both _implicit_ and _explicit_ type conversion.
* `type coercion`  
this is the term used for _implicit_ type conversion. The definition of this term in the context of Ruby is relatively up for debate, but I'm going to define it as either (a) a method converting an argument or (b) the syntax of the Ruby language converting an object.
* `type casting`  
this is the term used for _explicit_ type conversion. Ruby doesn't necessarily have "casting" in the traditional sense (like C) but instead has methods used to represent explicit type conversions like `#to_s` or `#to_i`.
* `interface`  
a set of methods that an object understands. These methods can be defined pretty much anywhere as long as the object knows where to find them (e.g., the class of the object, a module that is included in the object, the singleton class of the object, any active refinements, etc.).

With these definitions in mind, we can define the term "dynamically-typed". Ruby is considered a dynamically-typed language because the types of the objects that are live during the execution of a Ruby program are not known at compile time, they are only known at run time. It follows that any method can receive any type of object for any argument. When a method receives an argument of a type that it doesn't expect, it can do one of three things:

* raise an error implicitly - effectively analogous to praying you get the right types
* raise an error explicitly - something like `raise ArgumentError unless value.is_a?(String)`
* convert the type of the object - by calling a type conversion method like `#to_str`

By far the worst option is the first one, as it's abdicating responsibility to the next developer. The second option is somewhat better, it in that it enforces the expected type. The issue with the second one is that it's enforcing the _nominal_ type (the class) as opposed to the _structural_ type (the interface). It precludes the possibility that the object could be converted into the desired type, and instead halts execution.

The third option is the subject of this blog post. Ruby is rife with examples of this kind of type conversion, especially within the standard library. This pattern has propagated into other popular Ruby projects, including Ruby on Rails. To start out, let's look at some examples.

## Type coercion in a method

Let's look at `Array#flatten`. For those unfamiliar, `#flatten` is a method on `Array` that concatentates together internal arrays into a single array. For example:

```ruby
[1, [2, 3], [4], [5, [6, [7]]]].flatten
# => [1, 2, 3, 4, 5, 6, 7]
```

It also accepts as an argument the "level" of flattening (i.e., the number of times it should recursively flatten). That looks like:

```ruby
[1, [2, 3], [4], [5, [6, [7]]]].flatten(2)
# => [1, 2, 3, 4, 5, 6, [7]]
```

(Notice that the final array containing the integer `7` is not flattened because it was three levels deep.)

This is the base case, and works just fine in the examples provided above. However, there are times when the values inside the array are not so primitive. Let's consider an example where we have a custom class that functions as a list of elements (and maintains its own internal array). In that case, if we call `#flatten` on an array of those objects, we'll get back the same array, as in:

```ruby
class List
  def initialize(elems)
    @elems = elems
  end
end

[List.new([1, 2]), List.new([3, 4]), List.new([5, 6])].flatten
# => [#<List @elems=[1, 2]>, #<List @elems=[3, 4]>, #<List @elems=[5, 6]>]
```

However, if we define the `#to_ary` type coercion method (remember that's the _implicit_ option), then Ruby will happily call this method for us, as in:

```ruby
class List
  def to_ary
    @elems
  end
end

[List.new([1, 2]), List.new([3, 4]), List.new([5, 6])].flatten
# => [1, 2, 3, 4, 5, 6]
```

You can see how it's implemented in various Ruby implementations like [CRuby](https://github.com/ruby/ruby/blob/419e6ed464b2abcc18b60d1bcbd183fe9dfb99c2/array.c#L6219), [TruffleRuby](https://github.com/oracle/truffleruby/blob/521f9c0fad5244c9cf5302f56b1570a34ca065d5/src/main/java/org/truffleruby/core/array/ArrayNodes.java#L2413-L2418), and [Rubinius](https://github.com/rubinius/rubinius/blob/b7a755c83f3dd3f0c1f5e546f0e58fb61851ea44/core/array.rb#L2112-L2119). You can also see how it's implemented in the [Sorbet](https://github.com/sorbet/sorbet/blob/e4afd42a569959da9e8c294bbb253e0a9df80c4d/core/types/calls.cc#L2947) type system, which handles these kinds of special conversions in what it calls "instrinsic" methods.

This is an example of type coercion that happens because of a standard library method call. But as mentioned above in the definition of type coercion, it can also happen as a result of syntax.

## Type coercion from syntax

Let's say we have an array of integers and we want to convert them into an array of strings. We can accomplish that with the `#map` method that accepts a block and a type cast (the _explicit_ option), as in:

```ruby
[1, 2, 3].map { |value| value.to_s }
# => ["1", "2", "3"]
```

We can also create a proc that will be used for the mapping and then pass it as the block for the method by using the `&` unary operator, as in:

```ruby
mapping = proc { |value| value.to_s }
[1, 2, 3].map(&mapping)
```

From the perspective of the `#map` method these two snippets are equivalent as in both it receives a block. There's also the more terse version of this type conversion that most Rubyists prefer, which is to instead pass a symbol that represents the mapping, as in:

```ruby
mapping = :to_s
[1, 2, 3].map(&mapping)
# => ["1", "2", "3"]
```

In the above snippet, we're taking advantage of the fact that `Symbol` has the `#to_proc` implicit type conversion method defined on it, which Ruby will take advantage of when using the `&` operator. In fact, it will do this on _any_ object that has that conversion method defined, as in:

```ruby
class Double
  def to_proc
    proc { |value| value * 2 }
  end
end

[1, 2, 3].map(&Double.new)
# => [2, 4, 6]
```

This is an example of syntax implicitly calling methods on objects in order to achieve a type conversion.

## Type conversion interfaces

Some languages have explicit interface constructs that allow the developer to define a set of methods that an object should respond to in order to say they "implement" that interface. (These are also sometimes called traits.) In Ruby they are implicit, though this doesn't make them any less common. Here is a list of the most common ones that I could find in use within the standard library:

* `to_a`/`to_ary` - converting to `Array`
* `to_h`/`to_hash` - converting to `Hash`
* `to_s`/`to_str` - converting to `String`
* `to_sym` - converting to `Symbol`
* `to_proc` - converting to `Proc`
* `to_io` - converting to `IO`
* `to_i`/`to_int`/`to_f`/`to_c`/`to_r` - converting to various `Numeric` subtypes
* `to_regexp` - converting to `Regexp`
* `to_path` - converting to a `String` to be used to represent a filepath
* `to_enum` - converting to `Enumerable`
* `to_open` - exclusively used by `Kernel#open` to convert the object its attempting to open into a URL or path

There are also the relatively new pattern matching interfaces:

* `deconstruct` - for converting an object into an array or find pattern for matching
* `deconstruct_keys` - for converting an object into a hash pattern for matching

As well as some very esoteric ones, like `sleep` accepting anything that responds to [divmod](https://github.com/ruby/ruby/blob/419e6ed464b2abcc18b60d1bcbd183fe9dfb99c2/time.c#L2590).

All of these methods can be used for type coercion or type casting, depending on the context. Sometimes Ruby will trigger these method calls implicitly but any developer can also call these methods explicitly. Below I'll go into some more details about where you can find these conversions and how they're used.

### to_a

Used by the `Kernel.Array` and `Queue#initialize` methods, but much more commonly used by the splat operator. For example, if you have an object that responds to `#to_a`, it can be splatted into an array, as in:

```ruby
class List
  def initialize(elems)
    @elems = elems
  end

  def to_a
    @elems
  end
end

[1, *List.new([2, 3]), 4]
# => [1, 2, 3, 4]
```

### to_ary

<details>
  <summary>List of methods</summary>
  <ul>
    <li><code>Array#&</code></li>
    <li><code>Array#+</code></li>
    <li><code>Array#-</code></li>
    <li><code>Array#<=></code></li>
    <li><code>Array#==</code></li>
    <li><code>Array#[]=</code></li>
    <li><code>Array#concat</code></li>
    <li><code>Array#difference</code></li>
    <li><code>Array#flatten</code></li>
    <li><code>Array#flatten!</code></li>
    <li><code>Array#intersection</code></li>
    <li><code>Array#join</code></li>
    <li><code>Array#product</code></li>
    <li><code>Array#replace</code></li>
    <li><code>Array#to_h</code></li>
    <li><code>Array#transpose</code></li>
    <li><code>Array#union</code></li>
    <li><code>Array#zip</code></li>
    <li><code>Array.initialize</code></li>
    <li><code>Array.new</code></li>
    <li><code>Array.try_convert</code></li>
    <li><code>Enumerabe#flat_map</code></li>
    <li><code>Enumerable#collect_concat</code></li>
    <li><code>Enumerable#to_h</code></li>
    <li><code>Enumerable#zip</code></li>
    <li><code>Hash#to_h</code></li>
    <li><code>Hash.[]</code></li>
    <li><code>IO#puts</code></li>
    <li><code>Kernel.Array</code></li>
    <li><code>Proc#===</code></li>
    <li><code>Proc#call</code></li>
    <li><code>Proc#yield</code></li>
    <li><code>Process.exec</code></li>
    <li><code>Process.spawn</code></li>
    <li><code>String#%</code></li>
    <li><code>Struct#to_h</code></li>
  </ul>
</details>

`#to_ary` is used in syntax for destructuring and multiple assignment. For example, let's say you have a `Point` class that represents a point in 2D space, and you want to print out just the `x` coordinate from a list of points. You could define the class such as:

```ruby
class Point
  attr_reader :x, :y

  def initialize(x, y)
    @x = x
    @y = y
  end
end
```

Then when you loop through to print the `x` coordinate, you would:

```ruby
[Point.new(1, 2), Point.new(3, 4)].each { |point| puts point.x }
```

This works, but you can take advantage of the fact that block arguments can destructure values by defining `#to_ary`, as in:

```ruby
class Point
  def to_ary
    [x, y]
  end
end

[Point.new(1, 2), Point.new(3, 4)].each { |(x, y)| puts x }
```

Similarly, you can destructure within multiple assignment as in:

```ruby
x, y = Point.new(1, 2)
x
# => 1
```

### to_hash

<details>
  <summary>List of methods</summary>
  <ul>
    <li><code>Enumerable#tally</code></li>
    <li><code>Hash#merge</code></li>
    <li><code>Hash#replace</code></li>
    <li><code>Hash#update</code></li>
    <li><code>Hash.[]</code></li>
    <li><code>Hash.try_convert</code></li>
    <li><code>Kernel.Hash</code></li>
    <li><code>Process.spawn</code></li>
  </ul>
</details>

`#to_hash` is used with the double splat (`**`) operator. For example, if you have some kind of object that represents parameters being sent to an HTTP endpoint, you can:

```ruby
class Parameters
  def initialize(params)
    @params = params
  end

  def to_hash
    @params
  end
end

class Job
  def initialize(foo:, bar:); end
end

parameters = Parameters.new(foo: "foo", bar: "bar")
Job.new(**parameters)
```

In the above example, we're taking advantage of the implicit type conversion performed by the double splat operator in order to call `#to_hash` on our `Parameters` object.

### to_s

<details>
  <summary>List of methods</summary>
  <ul>
    <li><code>Array#inspect</code></li>
    <li><code>Array#pack</code></li>
    <li><code>Array#to_s</code></li>
    <li><code>Exception#to_s</code></li>
    <li><code>File#printf</code></li>
    <li><code>Hash#to_s</code></li>
    <li><code>IO#binwrite</code></li>
    <li><code>IO#print</code></li>
    <li><code>IO#puts</code></li>
    <li><code>IO#syswrite</code></li>
    <li><code>IO#write</code></li>
    <li><code>IO#write_nonblock</code></li>
    <li><code>Kernel#String</code></li>
    <li><code>Kernel#warn</code></li>
    <li><code>Kernel.sprintf</code></li>
    <li><code>String#%</code></li>
    <li><code>String#gsub</code></li>
    <li><code>String#sub</code></li>
  </ul>
</details>

`#to_s` is called implicitly whenever an object is used within string interpolation. (It's minorly inconsistent in that most of the time in Ruby `#to_str` is used to implicitly convert to a `String`.) So, for example, if you have:

```ruby
"#{123}"
```

this is equivalent to calling:

```ruby
123.to_s
```

This is why in most Ruby linters it will show a violation for the code `"#{123.to_s}"` because it's redundant.

### to_str

<details>
  <summary>List of methods</summary>
  <ul>
    <li><code>Array#*</code></li>
    <li><code>Array#join</code></li>
    <li><code>Array#pack</code></li>
    <li><code>Binding#local_variable_defined?</code></li>
    <li><code>Binding#local_variable_set</code></li>
    <li><code>Dir.chdir</code></li>
    <li><code>ENV.[]</code></li>
    <li><code>ENV.[]=</code></li>
    <li><code>ENV.assoc</code></li>
    <li><code>ENV.rassoc</code></li>
    <li><code>ENV.store</code></li>
    <li><code>Encoding.Converter.asciicompat_encoding</code></li>
    <li><code>Encoding.Converter.new</code></li>
    <li><code>Encoding.default_external=</code></li>
    <li><code>Encoding.default_internal=</code></li>
    <li><code>File#delete</code></li>
    <li><code>File#path</code></li>
    <li><code>File#to_path</code></li>
    <li><code>File#unlink</code></li>
    <li><code>File.chmod</code></li>
    <li><code>File.join</code></li>
    <li><code>File.new</code></li>
    <li><code>File.split</code></li>
    <li><code>IO#each</code></li>
    <li><code>IO#each_line</code></li>
    <li><code>IO#gets</code></li>
    <li><code>IO#read</code></li>
    <li><code>IO#readlines</code></li>
    <li><code>IO#set_encoding</code></li>
    <li><code>IO#sysread</code></li>
    <li><code>IO#ungetbyte</code></li>
    <li><code>IO#ungetc</code></li>
    <li><code>IO.for_fd</code></li>
    <li><code>IO.foreach</code></li>
    <li><code>IO.new</code></li>
    <li><code>IO.open</code></li>
    <li><code>IO.pipe</code></li>
    <li><code>IO.popen</code></li>
    <li><code>IO.printf</code></li>
    <li><code>IO.readlines</code></li>
    <li><code>Kernel#gsub</code></li>
    <li><code>Kernel#instance_variable_get</code></li>
    <li><code>Kernel#open</code></li>
    <li><code>Kernel#remove_instance_variable</code></li>
    <li><code>Kernel#require</code></li>
    <li><code>Kernel#require_relative</code></li>
    <li><code>Kernel.`</code></li>
    <li><code>Module#alias_method</code></li>
    <li><code>Module#attr</code></li>
    <li><code>Module#attr_accessor</code></li>
    <li><code>Module#attr_reader</code></li>
    <li><code>Module#attr_writer</code></li>
    <li><code>Module#class_eval</code></li>
    <li><code>Module#class_variable_defined?</code></li>
    <li><code>Module#class_variable_get</code></li>
    <li><code>Module#class_variable_set</code></li>
    <li><code>Module#const_defined?</code></li>
    <li><code>Module#const_get</code></li>
    <li><code>Module#const_set</code></li>
    <li><code>Module#const_source_location</code></li>
    <li><code>Module#method_defined?</code></li>
    <li><code>Module#module_eval</code></li>
    <li><code>Module#module_function</code></li>
    <li><code>Module#protected_method_defined?</code></li>
    <li><code>Module#remove_const</code></li>
    <li><code>Process.getrlimit</code></li>
    <li><code>Process.setrlimit</code></li>
    <li><code>Process.spawn</code></li>
    <li><code>Regexp.union</code></li>
    <li><code>String#%</code></li>
    <li><code>String#+</code></li>
    <li><code>String#<<</code></li>
    <li><code>String#<=></code></li>
    <li><code>String#==</code></li>
    <li><code>String#===</code></li>
    <li><code>String#[]=</code></li>
    <li><code>String#casecmp</code></li>
    <li><code>String#center</code></li>
    <li><code>String#chomp</code></li>
    <li><code>String#concat</code></li>
    <li><code>String#count</code></li>
    <li><code>String#crypt</code></li>
    <li><code>String#delete</code></li>
    <li><code>String#delete_prefix</code></li>
    <li><code>String#delete_suffix</code></li>
    <li><code>String#each_line</code></li>
    <li><code>String#encode</code></li>
    <li><code>String#encode!</code></li>
    <li><code>String#force_encoding</code></li>
    <li><code>String#include?</code></li>
    <li><code>String#index</code></li>
    <li><code>String#initialize</code></li>
    <li><code>String#insert</code></li>
    <li><code>String#lines</code></li>
    <li><code>String#ljust</code></li>
    <li><code>String#partition</code></li>
    <li><code>String#prepend</code></li>
    <li><code>String#replace</code></li>
    <li><code>String#rjust</code></li>
    <li><code>String#rpartition</code></li>
    <li><code>String#scan</code></li>
    <li><code>String#split</code></li>
    <li><code>String#squeeze</code></li>
    <li><code>String#sub</code></li>
    <li><code>String#tr</code></li>
    <li><code>String#tr_s</code></li>
    <li><code>String#unpack</code></li>
    <li><code>String.try_convert</code></li>
    <li><code>Thread#name=</code></li>
    <li><code>Time#getlocal</code></li>
    <li><code>Time#localtime</code></li>
    <li><code>Time.gm</code></li>
    <li><code>Time.local</code></li>
    <li><code>Time.mktime</code></li>
    <li><code>Time.new</code></li>
  </ul>
</details>

This is the main conversion method for objects into strings. It's used all over the place in the standard library. This interface is very popular and can be seen even in [recent pull requests](https://github.com/rails/rails/pull/41390) to Ruby on Rails.

### to_sym

This is a relatively common way to convert strings into symbols, but doesn't get a ton of usage internally. The only method I could find in the standard library that converted an argument into a symbol using `#to_sym` was `Tracepoint.new`.

### to_proc

Another one that doesn't get used a ton internally, the only place I could find that used this in a method call was `Hash#default_proc=` (which will convert its only argument into a callable proc if it isn't already one). `#to_proc` does get triggered through syntax, however, when passing a block argument (see the example above).

### to_io

<details>
  <summary>List of methods</summary>
  <ul>
    <li><code>File.directory?</code></li>
    <li><code>File.size</code></li>
    <li><code>File.size?</code></li>
    <li><code>FileTest.directory?</code></li>
    <li><code>IO#reopen</code></li>
    <li><code>IO.select</code></li>
    <li><code>IO.try_convert</code></li>
  </ul>
</details>

This one is less well-known, but gets used a lot within the `IO` and `File` class to convert method arguments into objects that can be used as `IO`-like objects.

### to_i

<details>
  <summary>List of methods</summary>
  <ul>
    <li><code>Complex#to_i</code></li>
    <li><code>File#printf</code></li>
    <li><code>Kernel#Integer</code></li>
    <li><code>Kernel.Integer</code></li>
    <li><code>Kernel.sprintf</code></li>
    <li><code>Numeric#to_int</code></li>
    <li><code>String#%</code></li>
  </ul>
</details>

This begins a series of conversion methods for `Numeric` subtypes, which all convert into each other. `#to_i` converts into an `Integer` object. It's not all that commonly used compared in implicit ways compared to `#to_int`, but still gets some usage in the methods listed above. Much more commonly this is the method that is called on a string to convert into an integer (and it accepts as an argument a radix for this purpose).

### to_int

<details>
  <summary>List of methods</summary>
  <ul>
    <li><code>Array#*</code></li>
    <li><code>Array#[]</code></li>
    <li><code>Array#[]=</code></li>
    <li><code>Array#at</code></li>
    <li><code>Array#cycle</code></li>
    <li><code>Array#delete_at</code></li>
    <li><code>Array#drop</code></li>
    <li><code>Array#fetch</code></li>
    <li><code>Array#fill</code></li>
    <li><code>Array#first</code></li>
    <li><code>Array#flatten</code></li>
    <li><code>Array#hash</code></li>
    <li><code>Array#initialize</code></li>
    <li><code>Array#insert</code></li>
    <li><code>Array#last</code></li>
    <li><code>Array#pack</code></li>
    <li><code>Array#pop</code></li>
    <li><code>Array#rotate</code></li>
    <li><code>Array#sample</code></li>
    <li><code>Array#shift</code></li>
    <li><code>Array#shuffle</code></li>
    <li><code>Array#slice</code></li>
    <li><code>Array.new</code></li>
    <li><code>Encoding::Converter#primitive_convert</code></li>
    <li><code>Enumerable#cycle</code></li>
    <li><code>Enumerable#drop</code></li>
    <li><code>Enumerable#each_cons</code></li>
    <li><code>Enumerable#each_slice</code></li>
    <li><code>Enumerable#first</code></li>
    <li><code>Enumerable#take</code></li>
    <li><code>Enumerable#with_index</code></li>
    <li><code>File#chmod</code></li>
    <li><code>File#printf</code></li>
    <li><code>File.fnmatch</code></li>
    <li><code>File.fnmatch?</code></li>
    <li><code>File.umask</code></li>
    <li><code>IO#gets</code></li>
    <li><code>IO#initialize</code></li>
    <li><code>IO#lineno=</code></li>
    <li><code>IO#pos</code></li>
    <li><code>IO#putc</code></li>
    <li><code>IO#tell</code></li>
    <li><code>IO.for_fd</code></li>
    <li><code>IO.foreach</code></li>
    <li><code>IO.new</code></li>
    <li><code>IO.open</code></li>
    <li><code>IO.readlines</code></li>
    <li><code>Integer#*</code></li>
    <li><code>Integer#+</code></li>
    <li><code>Integer#-</code></li>
    <li><code>Integer#<<</code></li>
    <li><code>Integer#>></code></li>
    <li><code>Integer#[]</code></li>
    <li><code>Integer#allbits?</code></li>
    <li><code>Integer#anybits?</code></li>
    <li><code>Integer#nobits?</code></li>
    <li><code>Integer#round</code></li>
    <li><code>Kernel#Integer</code></li>
    <li><code>Kernel#exit!</code></li>
    <li><code>Kernel#exit</code></li>
    <li><code>Kernel#putc</code></li>
    <li><code>Kernel.Integer</code></li>
    <li><code>Kernel.exit!</code></li>
    <li><code>Kernel.exit</code></li>
    <li><code>Kernel.putc</code></li>
    <li><code>Kernel.rand</code></li>
    <li><code>Kernel.sprintf</code></li>
    <li><code>Kernel.srand</code></li>
    <li><code>MatchData#begin</code></li>
    <li><code>MatchData#end</code></li>
    <li><code>Process.getrlimit</code></li>
    <li><code>Process.setrlimit</code></li>
    <li><code>Random#seed</code></li>
    <li><code>Random.rand</code></li>
    <li><code>Range#first</code></li>
    <li><code>Range#last</code></li>
    <li><code>Range#step</code></li>
    <li><code>Regexp.last_match</code></li>
    <li><code>String#%</code></li>
    <li><code>String#*</code></li>
    <li><code>String#[]</code></li>
    <li><code>String#[]=</code></li>
    <li><code>String#byteslice</code></li>
    <li><code>String#center</code></li>
    <li><code>String#index</code></li>
    <li><code>String#insert</code></li>
    <li><code>String#ljust</code></li>
    <li><code>String#rindex</code></li>
    <li><code>String#rjust</code></li>
    <li><code>String#setbyte</code></li>
    <li><code>String#slice</code></li>
    <li><code>String#split</code></li>
    <li><code>String#sum</code></li>
    <li><code>String#to_i</code></li>
    <li><code>Time#getlocal</code></li>
    <li><code>Time#localtime</code></li>
    <li><code>Time.at</code></li>
    <li><code>Time.gm</code></li>
    <li><code>Time.local</code></li>
    <li><code>Time.mktime</code></li>
    <li><code>Time.new</code></li>
    <li><code>Time.new</code></li>
    <li><code>Time.utc</code></li>
  </ul>
</details>

This is a very commonly used conversion method for converting to `Integer`. A ton of methods will call this on arguments passed in to allow any kind of object to be used. It can also be triggered implicitly by setting the `$.` (the line number last read by the interpreter). I have no idea why that's in there, but it is.

### to_f

<details>
  <summary>List of methods</summary>
  <ul>
    <li><code>Complex#to_f</code></li>
    <li><code>File#printf</code></li>
    <li><code>Integer#coerce</code></li>
    <li><code>Kernel#Float</code></li>
    <li><code>Kernel.Float</code></li>
    <li><code>Kernel.sprintf</code></li>
    <li><code>Math.cos</code></li>
    <li><code>Numeric#ceil</code></li>
    <li><code>Numeric#coerce</code></li>
    <li><code>Numeric#fdiv</code></li>
    <li><code>Numeric#floor</code></li>
    <li><code>Numeric#round</code></li>
    <li><code>Numeric#truncate</code></li>
    <li><code>String#%</code></li>
  </ul>
</details>

A method of converting an object into a float. Not all that commonly used except for when a developer wants to avoid integer division.

### to_c

One of, if not the most, esoteric one I could find in the standard library. This is a way of converting an object into a `Complex` number type, which is only used by the `Kernel.Complex` method.

### to_r

<details>
  <summary>List of methods</summary>
  <ul>
    <li><code>Complex#to_r</code></li>
    <li><code>Numeric#denominator</code></li>
    <li><code>Numeric#numerator</code></li>
    <li><code>Numeric#quo</code></li>
    <li><code>Time#+</code></li>
    <li><code>Time#-</code></li>
    <li><code>Time#getlocal</code></li>
    <li><code>Time#localtime</code></li>
    <li><code>Time#new</code></li>
    <li><code>Time.at</code></li>
  </ul>
</details>

The final numeric conversion interface. `#to_r` is used to convert an object into a rational number. It gets most of its usage in the `Time` class.

### to_regexp

A less-used interface for converting an object into a regular expression, this only gets used internally within the `Regexp` class in the `Regexp.try_convert` and `Regexp.union` methods.

### to_path

<details>
  <summary>List of methods</summary>
  <ul>
    <li><code>Dir#initialize</code></li>
    <li><code>Dir.[]</code></li>
    <li><code>Dir.chdir</code></li>
    <li><code>Dir.children</code></li>
    <li><code>Dir.chroot</code></li>
    <li><code>Dir.each_child</code></li>
    <li><code>Dir.entries</code></li>
    <li><code>Dir.foreach</code></li>
    <li><code>Dir.glob</code></li>
    <li><code>Dir.mkdir</code></li>
    <li><code>File#path</code></li>
    <li><code>File#to_path</code></li>
    <li><code>File.ftype</code></li>
    <li><code>File.join</code></li>
    <li><code>File.mkfifo</code></li>
    <li><code>File.new</code></li>
    <li><code>File.realpath</code></li>
    <li><code>File::Stat#initialize</code></li>
    <li><code>IO#reopen</code></li>
    <li><code>IO#sysopen</code></li>
    <li><code>IO.copy_stream</code></li>
    <li><code>IO.foreach</code></li>
    <li><code>IO.read</code></li>
    <li><code>IO.readlines</code></li>
    <li><code>Kernel#autoload</code></li>
    <li><code>Kernel#open</code></li>
    <li><code>Kernel#require</code></li>
    <li><code>Kernel#require_relative</code></li>
    <li><code>Kernel#test</code></li>
    <li><code>Module#autoload</code></li>
    <li><code>Process.spawn</code></li>
  </ul>
</details>

I like this one a lot because it's one of the few on this list that is named after the role that the converted object will fulfill as opposed to the type of object that is expected. That is to say, `#to_path` converts an object into a `String` that will function as the representation of a filepath. It's used mostly within the `Dir`, `File`, and `IO` classes.

### to_enum

`Enumerable#zip` interestingly allows you to pass any object that responds to `#to_enum`. This was the only mention of this method that I could find in the standard library.

### to_open

Similarly to `#to_enum`, `#to_open` is also only used in one place: `Kernel#open`. Anything that you pass to that method that responds to `#to_open` will be converted implicitly.

## Pattern matching

When [pattern matching](https://docs.ruby-lang.org/en/3.0.0/doc/syntax/pattern_matching_rdoc.html) was introduced into Ruby, we got two additional methods for implicit type conversion: `deconstruct` and `deconstruct_keys`.

### deconstruct

If you're matching against an object as if it were an array, then `deconstruct` will be called implicitly. For example:

```ruby
class List
  def initialize(elems)
    @elems = elems
  end

  def deconstruct
    @elems
  end
end

case List.new([1, 2, 3])
in 1, 2, 3
  # we've matched here successfully!
in *, 2, *
  # we would match here successfully too!
end
```

### deconstruct_keys

If you're matching against an object as if it were a hash, then `deconstruct_keys` will be called implicitly. For example:

```ruby
class Parameters
  def initialize(params)
    @params = params
  end

  def deconstruct_keys(keys)
    @params.slice(keys)
  end
end

case Parameters.new(foo: 1, bar: 2)
in foo: Integer
  # we've matched here successfully!
in foo: 1, bar: 2
  # we would match here successfully too!
end
```

## coerce

No discussion of type conversions in Ruby would be complete without mentioning the `coerce` method. `coerce` is an interesting little method that is used for converting between different numeric types. It allows you to effectively hook into methods like `Integer#*` without having to monkey-patch it. Say, for example, you were defining your own special class that you wanted to support numeric computations:

```ruby
class Value
  attr_reader :number

  def initialize(number)
    @number = number
  end

  def *(other)
    Value.new(number * other)
  end
end

value = Value.new(2)
value * 3
# => #<Value @number=6>
```

This works well. However, if you reverse the operands for the `*` operator, Ruby breaks it down to `3.*(value)`, which results in `TypeError (Value can't be coerced into Integer)`. If you define the `coerce` method, however, this can be accomplished, as in:

```ruby
class Value
  def *(other)
    case other
    when Numeric
      Value.new(number * other)
    when Value
      Value.new(number * other.number)
    else
      if other.respond_to?(:coerce)
        self_equiv, other_equiv = other.coerce(self)
        self_equiv * other_equiv
      else
        raise TypeError, "#{other.class} can't be coerced into #{self.class}"
      end
    end
  end

  def coerce(other)
    case other
    when Numeric
      [Value.new(other), self]
    when Value
      self
    else
      raise TypeError, "#{self.class} can't be coerced into #{other.class}"
    end
  end
end
```

For good measure I've changed `*` to attempt to coerce its argument as well. Now all of the numeric types play nicely and you can run `3 * value` without it breaking. You can see another example of this kind of `coerce` implementation in the standard library in the [Matrix class](https://github.com/ruby/matrix/blob/29a110d587e2a389618072f8a6287f0c211ea34e/lib/matrix.rb#L1641-L1655) as well as in Ruby on Rails in the [Duration class](https://github.com/rails/rails/blob/cf99be46c9aec7fe4576da7fc667c4d3994470d2/activesupport/lib/active_support/duration.rb#L22-L24).

## Conclusion

Type conversion is a subtle art baked into the very syntax of the Ruby programming language. As with most everything programming related, use it with caution and with the context of the team that will be maintaining the software you're writing. Especially with type coercion, it's very easy to write code that is very difficult to reason about.

That said, using the existing interfaces from the standard library and defining interfaces within your own applications can lead to very beautiful code that never needs to perform type checks.
