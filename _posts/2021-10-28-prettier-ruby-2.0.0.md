---
layout: post
title: Prettier Ruby 2.0.0
---

I just released the `2.0.0` version of the [prettier plugin for Ruby](https://github.com/prettier/plugin-ruby). In this post I'm going to talk about what this project is, how it works, what the `2.0.0` release means, and where this project is going.

## What is prettier for Ruby?

[Prettier](https://prettier.io/) is an opinionated language-agnostic formatter for code. It was started in 2017, and since then has seen a meteoric rise in usage within the frontend ecosystem. By default, it ships with support for JavaScript, HTML, CSS, and markdown of various forms. It also includes variants on all of these, including things like JSX, TypeScript, SCSS, MDX, etc.

Prettier also ships with a plugin interface to allow it to be extended by various languages. This has resulted in the community adding support for even more languages. The most mature projects include the [Apex plugin](https://github.com/dangmai/prettier-plugin-apex), the [Java plugin](https://github.com/jhipster/prettier-java), the [PHP plugin](https://github.com/prettier/plugin-php), the [XML/SVG plugin](https://github.com/prettier/plugin-xml), and of course the [Ruby plugin](https://github.com/prettier/plugin-ruby).

The Ruby plugin adds support for formatting the Ruby programming language to the prettier package. By virtue of plugging into prettier, it also gets a whole set of editor integrations for free, so this package includes that as well.

## How prettier plugins work

When you're writing a prettier plugin, you're effectively writing two parts. The first part is the [`parse` function](https://github.com/prettier/plugin-ruby/blob/f3fb267cb705573ffb62a4db4cefec3875d05d2b/src/ruby/parser.ts#L5-L11), which is responsible for transforming a string of source code (given to you by prettier) into some kind of object structure. The structure can actually be anything that you want. If it conforms to certain parameters (like having a `comments` key at the top of the structure) then prettier will attempt to take care of some of the printing for you.

Once you've transformed the source into your structure, that object will then be accessible through prettier's `AstPath` object that will be passed into your [`print` function](https://github.com/prettier/plugin-ruby/blob/f3fb267cb705573ffb62a4db4cefec3875d05d2b/src/ruby/printer.ts#L123-L138). Your `print` function is responsible for taking the object you generated in your `parse` function and transforming it into an intermediate representation that prettier calls `Doc` nodes.

`Doc` nodes are small, simple objects that represent various pieces of text that should be printed. The simplest of these is just a string of text, which will be printed literally. There is also the `indent` node, which will move all of the contents that you pass into it one level higher in indentation. There are also `align` nodes, `fill` and `join` nodes, `dedent` nodes, etc. You can view all of them in the [doc-builders.js](https://github.com/prettier/prettier/blob/6106421f0a7f9f241ae1de64fb22f0a21a9c0778/src/document/doc-builders.js) file.

The most important of these nodes are the `group` and `line` nodes. `group` nodes contain other nodes but change slightly how they print. If a `group` cannot fit its contents onto the current line, then it "breaks" its content up whenever it sees a `line` node. (Note: this is a slightly simplified version of what actually happens, but you get the point.)

Once you've built up this intermediate representation in your `print` function, prettier can take over, as at this point the structure of your formatter is entirely language-agnostic. It doesn't matter that originally it was a `class` node or a `module` node, at this point it's just text and groups. Prettier will then take its nodes and print them out for you.

## How the Ruby plugin works

In order to write the Ruby plugin, we needed the two pieces mentioned above, the `parse` and `print` functions. Let's start with the `parse` function.

### Parser

If you want the access the syntax tree (a structure that represents the code and the way it is laid out in source) you have a couple of options in the Ruby ecosystem. There are two main packages that will do this for you: [`ruby_parser`](https://github.com/seattlerb/ruby_parser) and [`parser`](https://github.com/whitequark/parser). There is also one standard library (assuming you're supporting versions of Ruby `< 2.7`) that will do this for you: [`ripper`](https://github.com/ruby/ruby/blob/b9f34062f00d1d2548ca9b6af61a6447c2d0f8e3/ext/ripper/README). Due to the nature of this project where it was going to be run as a node project, I didn't think it would be feasible to rely on the various Ruby load paths for dependencies, so the standard library `ripper` was the only realistic option.

`ripper` is a very interesting tool that effectively forks the bison parser that Ruby uses internally by placing special comments into the source grammar file. Every time a production rule is reduced in the generated parser, it dispatches an "event" for that rule. So for example, if you wanted to get a list of all of the comments in a Ruby source file, you could use `ripper` like:

```ruby
class CommentRipper < Ripper
  attr_reader :comments

  def initialize(*)
    super
    @comments = []
  end

  def on_comment(value)
    @comments << value
  end
end

ripper = CommentRipper.new(<<~CODE)
  # this is a comment
  foo
  # this is another comment
CODE

ripper.parse
ripper.comments
# => ["# this is a comment\n", "# this is another comment\n"]
```

This works for this small example, as comments by default are ignored in the final structure anyway. However, if you want to handle more node types, it's useful to know that the return value of your handler function will get passed up the tree as it's being built. So for example, let's say you wanted to write a calculator using ripper. You could write:

```ruby
class CalculatorRipper < Ripper
  def on_binary(left, oper, right)
    case oper
    when :+ then left + right
    when :- then left - right
    when :* then left * right
    when :/ then left / right
    else raise
    end
  end

  def on_int(value) = value.to_i
  def on_stmts_new = []
  def on_stmts_add(stmts, stmt) = stmts << stmt
  def on_program(stmts) = stmts.first
end

CalculatorRipper.parse('1 + 2 * 3')
# => 7
```

Internally, the parse tree for the code that we passed into that example looks something like:

```ruby
[:program,
  [:stmts_add,
    [:stmts_new],
    [:binary,
      [:int, "1"],
      :+,
      [:binary,
        [:int, "2"],
        :*,
        [:int, "3"]
      ]
    ]
  ]
]
```

You can see from this structure what's going to get called first. It's going to start at the leaves of the tree, so `on_int` is going to get called with the argument `"2"` and `"3"`. Those are going to get transformed into integers with the call to `to_i`. They're both going to be passed into the `on_binary` method next, along with the `:*` operator. That will return `6`, which will in turn get passed up to the next `on_binary` call. Finally we'll pass everything up to `stmts_add` and `program`.

You can see how in this way, we can build up whatever structure we want using ripper, provided we implement enough methods. That's exactly what we've done in our prettier plugin, which is to implement a handler method for every node in the parse tree in our [`parser.rb`](https://github.com/prettier/plugin-ruby/blob/f3fb267cb705573ffb62a4db4cefec3875d05d2b/src/ruby/parser.rb) file.

If you're interested in learning more about ripper and how it works internally, I've written up just about everything I know about ripper in a completely separate repository [here](https://kddnewton.com/ripper-docs/).

### Server

When the initial request to parse a file comes into our plugin, it comes in from the parent node process. However, our parser is written in Ruby. So we need a way to communicate between the two languages that will allow us to pass the structure back from Ruby once it's done parsing. In order to accomplish this, when the first request to parse a file is received, the node process will spawn a Ruby server that handles all current and future parse requests.

That server is defined in our [`server.rb`](https://github.com/prettier/plugin-ruby/blob/f3fb267cb705573ffb62a4db4cefec3875d05d2b/src/parser/server.rb) file. It is first spawned in our `parseSync.ts` file within our [`spawnServer`](https://github.com/prettier/plugin-ruby/blob/f3fb267cb705573ffb62a4db4cefec3875d05d2b/src/parser/parseSync.ts#L63-L165) function. A couple of things happen here that are a little complicated to get everything set up correctly.

The first issue is that for a prettier plugin, your `parse` function _must_ be synchronous, meaning when you receive code you cannot return a promise that will resolve to syntax tree. The second issue is that node has no built-in way of communicating with a separate server that is synchronous. The only thing that will block the main thread that looks anything like server communication is to spawn another process and wait for it to exit. So this is how we communicate between the two processes. The data flow looks like the following:

* Receive a request to parse code in one of our plugin's `parse` functions, as in [here](https://github.com/prettier/plugin-ruby/blob/f3fb267cb705573ffb62a4db4cefec3875d05d2b/src/ruby/parser.ts#L5-L11)
* Create a temporary file where our connection information is going to be written [here](https://github.com/prettier/plugin-ruby/blob/f3fb267cb705573ffb62a4db4cefec3875d05d2b/src/parser/parseSync.ts#L68-L69)
* Spawn a Ruby process running our server [here](https://github.com/prettier/plugin-ruby/blob/f3fb267cb705573ffb62a4db4cefec3875d05d2b/src/parser/parseSync.ts#L125-L129)
* Once the server is booted, it determines the fastest way to connect to it in parallel (looking at tools like `netcat` and `telnet`) [here](https://github.com/prettier/plugin-ruby/blob/f3fb267cb705573ffb62a4db4cefec3875d05d2b/src/parser/server.rb#L110-L135)
* Now that the server is booted and knows the best way to connect, it writes out that connection information to the temporary file created in the node process [here](https://github.com/prettier/plugin-ruby/blob/f3fb267cb705573ffb62a4db4cefec3875d05d2b/src/parser/server.rb#L139). It then blocks the process waiting for future requests
* Back in the parent node process, spawn another process that will block and wait for the connection information to be written [here](https://github.com/prettier/plugin-ruby/blob/f3fb267cb705573ffb62a4db4cefec3875d05d2b/src/parser/parseSync.ts#L152)
* The child process that waits for the connection information to be written eventually writes back that information to stdout [here](https://github.com/prettier/plugin-ruby/blob/f3fb267cb705573ffb62a4db4cefec3875d05d2b/src/parser/getInfo.js)
* Finally, the server is booted and we know how to communicate with it, so send the actual parse request to the server and return the resulting structure [here](https://github.com/prettier/plugin-ruby/blob/f3fb267cb705573ffb62a4db4cefec3875d05d2b/src/parser/parseSync.ts#L187-L213)

While this is a pretty complicated setup, in reality it only needs to be done once for the lifetime of the prettier node process, as after that it's set up and ready for future requests. The whole cycle takes about 200ms for the first request, whereas future requests are much quicker (measured in double-digit ms).

### Printer

Now that the structure has been returned, prettier does something nice and attaches our parsed comments to our parse tree for us. It does this by first "decorating" each comments with metadata about its "enclosing" node (the parent node in the tree), its "preceding" node (the node immediately before the comment), and its "following" node (the node immediately after the comment). Any of these nodes can be null. It does that in its [`decorateComment`](https://github.com/prettier/prettier/blob/6106421f0a7f9f241ae1de64fb22f0a21a9c0778/src/main/comments.js#L78-L155) function.

It determines these surrounding nodes by knowing where the nodes were in the original source using the `locStart` and `locEnd` functions called [here](https://github.com/prettier/prettier/blob/6106421f0a7f9f241ae1de64fb22f0a21a9c0778/src/main/comments.js#L95-L96) as well as the `getSortedChildNodes` function called [here](https://github.com/prettier/prettier/blob/6106421f0a7f9f241ae1de64fb22f0a21a9c0778/src/main/comments.js#L86). Those functions _must_ be provided by the plugin in order for this process to work properly. This is why it's so important that every node has the ability to know where it was originally in the code.

As a quick aside, this was not a trivial task. Ripper provides two methods for determining source location, `lineno` and `column`. They internally access the information of the parser when the production rule is being reduced. However, it can take bit of further processing before the parser realizes that a parser event has occurred. In that case, the `column` information may be incorrect. `column` itself is measured as a byte offset in the original string as opposed to a character offset as well, so that difference must be taken into account. For even more information on this, check out the documentation [here](https://kddnewton.com/ripper-docs/location) and the inline comments [here](https://github.com/prettier/plugin-ruby/blob/f3fb267cb705573ffb62a4db4cefec3875d05d2b/src/ruby/parser.rb#L25-L56).

With the comments attached, prettier will pass an `AstPath` object around the structure. The algorithm it uses internally is not all that dissimilar to a depth-first search, in that it will recursive all of the way down to the leaf nodes before building up the overall resulting `Doc` node. Once that whole tree is built in the prettier intermediate representation, that tree is handed back to prettier for printing.

## Going `2.0.0`

There are a couple of big things that changed between the `1.6.1` release (the last pre-`2.0.0`) and the `2.0.0` release. In terms of user-facing changes it's actually relatively minor. Internally, however, a lot of things have changed.

### TypeScript

The codebase for the Ruby plugin is half Ruby and half JavaScript-dialect. Previously the JS-dialect was entire JavaScript, running on node >= 8. All of this is backed by a fairly extensive test suite written in minitest (on the Ruby side) and jest (on the JS side).

Over time, it became obvious to me that the JS-side of things was really not all that maintainable. Even though I included massive amounts of comments in the source of the plugin, there still were non-obvious checks being done (e.g., `node.type !== "args"`, well then what is it!?) that I couldn't remember the original reason. Overall, due to the nature of walking a tree without a well-defined structure, it just became hard to understand.

It was at this point that I decided to switch that half of the codebase over to TypeScript. Mind you, this is no small task. Beyond the initial setup and trivial functions, the biggest blocker of them all presented itself: I needed a TypeScript representation of all of the possible syntax trees that my ripper parser could generate. I didn't know how to get this without doing a lot of manual work, so I paused here for a couple of months until inspiration struck.

A couple of months into thinking about this problem, I ended up developing a solution that involved parsing every Ruby file I could get my hands on (read: [ruby](https://github.com/ruby/ruby), [rails](https://github.com/rails/rails), [discourse](https://github.com/discourse/discourse), Shopify's internal monolith because I work there, etc.). Once I had parsed every file I could find, I generated the TypeScript types programmatically based on what I had found. Normally I would have open-sourced this kind of tool, but it was so specific to this project that I ended up scrapping it as soon as the script was finished running. After a lot of manual cleanup, I ended up with [this file](https://github.com/prettier/plugin-ruby/blob/f3fb267cb705573ffb62a4db4cefec3875d05d2b/src/types/ruby.ts) which provided me with the entire tree.

The next blocker was that prettier's print functions were not very friendly to type systems. It was originally designed with JavaScript in mind, not TypeScript, so that types for the various print functions were very lacking. Let's take a look at the following example that illustrates how you would print a tree using the `AstPath` object:

```javascript
const astPath = new AstPath({
  type: "program",
  stmts: [
    {
      type: "binary",
      left: { type: "int", value: "1" },
      operator: "+",
      right: { type: "int", value: "2" }
    }
  ]
})

function printNode(path, opts, print) {
  // getValue gets the current node that the path is pointing to. You can
  // recurse using the path.call or path.map member functions that will call
  // back into the print function with an AstPath object pointing at the child
  // nodes.
  const node = path.getValue();

  switch (node.type) {
    case "program":
      // If we're at the root of our tree, then we know we have a stmts key (see
      // the structure above) that points to an array of other nodes. So we can
      // call path.map to recurse down into that list and then join the result
      // of printing each one with a hardline (forced line break).
      return [join(hardline, path.map(print, "stmts")), hardline];
    case "binary":
      // If we're at a binary node, then we know we have "left", "operator", and
      // "right" keys on this node. In this case we can use path.call to descend
      // into each side of the node, and concat them all together using an
      // array. Since the operator itself is not a node but just a string, we
      // can just interpolate it into the result.
      return [path.call(print, "left"), ` ${node.operator} `, path.call(print, "right")];
    case "int":
      // In the case of an int node, we know we only have the one "value" key
      // which points to a string, so we can just return that.
      return node.value;
  }
}
```

The above is a very simplified version of what is happening in the Ruby plugin. You can see why it's difficult to add a type system to these kinds of function calls. The acceptable arguments at each callsite for `path.map` and `path.call` is dependent on which node the `AstPath` object is currently pointing to. Fortunately, TypeScript's generics system is pretty incredible, so we can get away with some pretty crazy stuff.

Effectively, I made it so that `AstPath` was generic over the type of node that it was pointing to. Then, when you go to call something like `path.map`, you can introspect on the properties of the current node that are iterable and only allow those keys. So for example, for a single argument to the `map` function you can write something like:

```typescript
// For a given object T, return a union of the keys of the object whose values
// are an array or tuple.
type ArrayProperties<T> = { [K in keyof T]: T[K] extends any[] ? K : never }[keyof T];

// For a given object T that is an array, return the type of element that
// comprises the array.
type ArrayElement<T> = T extends (infer E)[] ? E : never;

// For a given node T and a given return type U, the callback will be a function
// that accepts an element and index of the array and returns U.
type Callback<T, U> = (path: AstPath<ArrayElement<T>>, index: number, value: any) => U

class AstPath<T> {
  map<U, P1 extends ArrayProperties<T>>(callback: Callback<T, U>, prop1: P1): U[];
}
```

This is actually somewhat simplified from the final result which you can see [here](https://github.com/prettier/plugin-ruby/blob/f3fb267cb705573ffb62a4db4cefec3875d05d2b/src/types/plugin.ts). What this is doing is saying that you can only pass keys of the node that the `AstPath` object is currently pointing to that correspond to array values. As it turns out, this works! It becomes more complicated when you have multiple properties (like `path.map("stmts", 0)`), but you can see how that ends up working in the implementation from the link. What you end up doing is accepting another generic for each argument to the function as another function overload.

Once I had the representation of the Ruby syntax tree and prettier adding a lot of type safety, it became a lot easier to refactor the entire codebase. The types guided me through the refactor and I was able to run the test suite at each step of the way to ensure I kept compatibility. By and large, this refactor was the biggest one I've ever pulled on this project, and it was very much worth it.

One of the side benefits of having gone through the process of converting everything over to TypeScript is that I now have a reliable type system for the syntax tree that I can convert over the Ruby. We'll revisit this again in the concluding section of this post.

### Server communication

As I mentioned in the server section of this post, the setup to communicate between the node and Ruby processes is anything but trivial. This is actually the third iteration of this piece of the plugin, which includes a refactor even in this release.

The first version of the parse function spawned a Ruby process every time it wanted to parse a file. This worked flawlessly, so I was reticent to give it up. However, speed was very much an issue. Spawning any process is not cheap, and spawning a Ruby one especially tanked performance of the plugin overall. If you were going to format an entire codebase with hundreds of files, that meant hundreds of Ruby processes were going to be created.

Fortunately, in the second version of the parse function, we changed all that. Instead of spawning a Ruby process every time, the plugin instead spawned a Ruby process once and then used `netcat` to communicate with it. The server functioned using UNIX sockets. Whenever a request to format a file was made, the node process would `spawnSync` a `netcat` process into existence and write the contents of the file onto the `stdin` file input. `netcat` would dutifully take that and forward it on to the UNIX socket that the Ruby process was listening on. The Ruby process would receive that request and write the JSON-serialized result back onto the socket, which `netcat` would then print to `stdout` and exit. Because `spawnSync` blocks, the node process could then continue on and read the `stdout` of the now-dead child process, `JSON.parse` the result, and return it.

This worked much better than the first version because spawning a `netcat` process was much less costly than spawning a Ruby process. It had the benefit of keeping the Ruby server running in the background which made parsing very quick. I added some logic to support environments where `netcat` might not be available (like the `rubyNetcatCommand` option for specifying your own executable), and called it a day.

There were a couple of issues that cropped up as a result of this second iteration. The first had to do with the initial spawn of the Ruby server. In order to make sure that it could do everything it needed to do before we wrote any requests to it, I was shelling out to `sleep` for a short period of time until the sockfile existed. This turned out to be terrible for portability. The second was that I was relying on UNIX sockets being supported everywhere, which they definitely weren't.

The third iteration, and what ended up being a part of the `2.0.0` release was to refactor this _again_ into what is described in the server section above. Effectively this meant spawning a process to spawn the Ruby server initially, and then supporting a TCP server if UNIX sockets weren't available.

### Windows support

In the midst of all of the server refactoring, an issue was reported that `sleep` (and UNIX sockets) weren't supported on Windows. Fortunately, GitHub actions made it relatively painless to add different Windows boxes to our test suite. Once all of the server communication refactoring work was done and the `sleep` call was eliminated, I added the TCP server support to get the Windows test suite green. This worked, so `2.0.0` is a massive step forward for running this plugin on a Windwos machine.

## The future

As much as I have enjoyed maintaining this behemoth of a project for so long, the time has come for some change. Just looking at everything I've written at this post is intimidating, let alone thinking about maintaining it for much longer. Ideally, I'd like to do a couple of things:

* Upstream the parser. Ripper currently ships with `Ripper::SexpBuilder` and `Ripper::SexpBuilderPP`, both of which produce a structure of arrays, strings, and symbols. It includes the built-in location information for scanner events but not parser events. Unfortunately there's not really any names associated with the various edges of the tree, so it's difficult to work with reliably. I'd like to solve this by having ripper ship with another subclass that is effectively the parser written in this plugin, with a couple of modifications:
  * I'd like to replace the usage of all of the various hashes with well-defined classes. I don't like that everything is being merged into each other, as it's difficult to distinguish what's actually going on.
  * I'd like to delineate the logic for serializing to JSON from the logic to do the actual parsing. At the moment we're just dealing with the final representation, which makes it non-obvious how to change things. (A lot of this is actually an artifact of serializing to JSON: having `start_line` spelled out for every node was taking too much space so I reduced it to `sl`.)
  * I'd like to move all of the location information into its own object and make it serialize using only an array. Having `{ sl:, sc:, el:, ec: }` characters in every node wastes a lot of space.
* Convert and upstream the formatting. Fortunately, prettier and the `prettyprint` standard library share a similar algorithm. It should be possible to convert the bulk of what prettier is doing into enhancements to the `prettyprint` gem which can be upstreamed. From there, writing the formatter should just be a matter of requiring the `ripper` and `prettyprint` standard libraries and writing a bunch of `pp` methods.

Fortunately, the Ruby association has agreed to sponsor this work (see the announcement [here](https://www.ruby.or.jp/en/news/20211025)) so this will be happening of the course of the next six months. Beyond that, I still have more goals for this project as well, including:

* Building a language server dedicated to the formatter.
* Bringing basic linting capability into this project.
* Explaining syntax on hover for people less familiar with the more esoteric parts of Ruby syntax.
* Add refactoring support to the language server for a better development experience.

We'll see what's possible. It's an exciting time to work on Ruby dev tools!
