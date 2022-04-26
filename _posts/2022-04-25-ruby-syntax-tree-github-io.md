---
layout: post
title: ruby-syntax-tree.github.io
---

Over the weekend I cobbled together [ruby-syntax-tree.github.io](https://ruby-syntax-tree.github.io), and I thought I'd share a quick post about what it is, how it works, and what I learned while I built it.

## What is it?

A lot of good tools exist in the Ruby ecosystem that allow you to run some version of Ruby in the browser. I'm talking about tools like [try.ruby-lang.org](https://try.ruby-lang.org/), [runruby.io](https://runrb.io/), and [sorbet.run](https://sorbet.run/).

Usually getting Ruby to run in the browser entails using [emscripten](https://emscripten.org/) to compile C to [WebAssembly](https://webassembly.org/) or using [Opal](https://opalrb.com/) to compile Ruby to JavaScript. Recently, however, the [Ruby Association](https://www.ruby.or.jp/en/news/20211025) funded a project to compile Ruby to WebAssembly using the [WASI ABI](https://github.com/WebAssembly/WASI). Using this new functionality, you can compile Ruby itself or a Ruby application into a `.wasm` file that you can execute natively in the browser or through a polyfill. (You can actually execute it on any WebAssembly runtime, but for my purposes the browser will do.) For more information on the WASI Ruby project, check out the [final report](https://itnext.io/final-report-webassembly-wasi-support-in-ruby-4aface7d90c9).

So, to get to the titular question of this section. [ruby-syntax-tree.github.io](https://ruby-syntax-tree.github.io) is a website that uses the new WASI ABI functionality of Ruby to compile a `.wasm` file containing both the Ruby runtime and the source for the [Syntax Tree](https://ruby-syntax-tree.github.com/syntax_tree) gem. It then boots a virtual machine within the browser and uses it to transpile your Ruby into equivalent s-expressions.

## How it works

Let's start from the ground up. The first part of building the site was to build the `.wasm` file containing the Ruby runtime and the Ruby files necessary to run Syntax Tree. Following instructions from the [ruby/ruby.wasm](https://github.com/ruby/ruby.wasm) README, I ran a bunch of commands locally to get my own machine up and running. Once I verified that I had everything I needed, I replicated that process in a [Rakefile](https://github.com/ruby-syntax-tree/ruby-syntax-tree.github.io/blob/main/Rakefile).

One of the trickier parts was including Syntax Tree itself. I briefly considering including it as a git submodule so that it could be mounted as part of the wasi-vfs build process. I ended up scrapping that solution since dependabot wouldn't be able to automatically update it, and I realized that if I ever wanted any other gems loaded I wanted a reproducable solution.

Instead, I ended up using bundler as normal to install the dependencies. Once they were installed, I knew they existed _somewhere_ on the system. I also knew that `require "bundler/setup"` sets up the load paths so that you can require gems my name. So I decided to piggy-back on this functionality to copy the gem contents into the mounted directory. I found the right directory based on the `$:` load path global variable.

With everything in place, I used wasi-vfs to build the file. For packaging this file into the built web application, I used `esbuild`. They don't have built-in support for `.wasm` files, but adding support isn't hard. You can write your own plugin by mostly copy-pasting from their docs. That resulted in the esbuild plugin [here](https://github.com/ruby-syntax-tree/ruby-syntax-tree.github.io/blob/main/bin/wasmPlugin.js). That makes it so that you can import `.wasm` files as you would normally import modules. The default export is a function that accepts the imports for the module, and it asynchronously returns the module. You can then use the `ruby-head-wasm-wasi` npm package that Ruby now ships to wrap up the module and provide an `eval` function to evaluate RUby code.

Once the module is imported, it's a matter of requiring the correct files at the top of the file. That's accomplished by requiring the native gems that we need, then adding `lib` directory we put the Syntax Tree gem into early to the load path, then requiring it. All of that is encapsulated in the [createRuby.ts](https://github.com/ruby-syntax-tree/ruby-syntax-tree.github.io/blob/main/src/createRuby.ts) file. The actual web application is a relatively standard React/TypeScript application. Since it's not the novelty of this post, I won't cover it, but you can check out the source [here](https://github.com/ruby-syntax-tree/ruby-syntax-tree.github.io/blob/main/src/index.tsx).

## What I learned

I learned a bunch of stuff with this experiment! Here are a couple of things that I found useful that I feel are worth sharing:

* Rake proxies all of the `FileUtils` class methods as instance methods, so you can call things like `rm_rf` or `cp_r` from within Rake tasks and it will just work.
* You can reflect on load paths to find out where gems are housed by looking at `$:` once `bundler/setup` is required.
* There's a new-ish `Awaited` TypeScript generic type that will return the type encapsulated by a `Promise`.
* `esbuild` is really well documented and plugins are not too hard to write.
* You can deploy directly to GitHub pages through GitHub actions even if you have to invoke something like rake. ([See here](https://github.com/ruby-syntax-tree/ruby-syntax-tree.github.io/blob/main/.github/workflows/main.yml))

At some point I'd like to add the ability to format the source, add a better editor, and general improve the styling and UX. But for now, the current state is up at [ruby-syntax-tree.github.io](https://ruby-syntax-tree.github.io).
