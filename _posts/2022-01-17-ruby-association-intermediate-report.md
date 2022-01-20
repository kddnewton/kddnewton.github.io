---
layout: post
title: Ruby Association Intermediate Report
---

In accordance with the Ruby Association's timeline, this is an intermediate report on the [Ruby formatter](https://www.ruby.or.jp/en/news/20211025) project.

## Proposed work

When I first proposed the project, here are the list of deliverables that I mentioned in the proposal:

* A definitive representation of the Ruby AST based on `ripper`. It would be an additional shipped `ripper` subclass (like `Ripper::SexpBuilder` and `Ripper::SexpBuilderPP`) with Ruby. The difference is that every node has location information available on it. It will also involve documentation of every node type being shipped along with the parser.
* Updates and enhancements to the `prettyprint` gem. `prettyprint` does not currently support all of the various node types that will be neccessary, so another pull request will be merging in additional functionality to the `prettyprint` gem. This has the added benefit of allowing other developers to build formatters as well with the same infrastructure.
* The formatter itself that will convert the nodes from the `ripper` parser into the `prettyprint` IR.
* A CLI for formatting files (this could be baked into the Ruby CLI as well). This will trigger the formatter on each of the files given.
* A language server that supports the `formatOnSave` option. The idea here is to trigger the formatter whenever the developer hits save and watch everything snap into place.

## Current status

Progress for each bullet is detailed below.

### `ripper` subclass

I've created an additional `ripper` subclass here: <https://github.com/kddnewton/syntax_tree/blob/main/lib/syntax_tree.rb>. This file lives within the published `syntax_tree` gem. Each node contains an instance of a `SyntaxTree::Location` object that can be used to get definitive information about where it existed in the source. Each node also provides `attr_reader` methods for each of the child nodes, which are all documented.

As a part of this work, I've also added documentation to all of the various node types that ship with `ripper` here: <https://kddnewton.com/ripper-docs/>. Ideally, I'd like to upstream both the `syntax_tree` AST builder and the `ripper` documentation to make it easier for others to contribute and maintain it as a part of CRuby.

### `prettyprint` updates

In order to support all of the necessary formatting capabilities of a Ruby language formatter, I've opened a pull request ([https://github.com/ruby/ruby/pull/5163](https://github.com/ruby/ruby/pull/5163)) against Ruby that adds a bunch of new functionality to the `prettyprint` gem. That pull request itself has a lot of details on why the changes are necessary and details about how the gem is impacted.

### Formatter

The formatter itself is baked into the `syntax_tree` gem. Each node has its own corresponding `format` node (that functions in the same spirit as the `pretty_print` method convention of accepting a `PrettyPrint` object). For example, [here](https://github.com/kddnewton/syntax_tree/blob/0d3e9b7bcc0b198ca92b617cc787b17744035dd8/lib/syntax_tree.rb#L866-L881) is the code that handles formatting an `ARef` node (a node in the syntax tree that corresponds to accessing a collection at an index like `collection[index]`).

As of the latest commit on the `main` branch of the `syntax_tree` repository, `syntax_tree` supports all of the Ruby 3.1 syntax. As an additional guarantee of stability, I've added to the test suite a [test](https://github.com/kddnewton/syntax_tree/blob/0d3e9b7bcc0b198ca92b617cc787b17744035dd8/test/idempotency_test.rb) that formats all of the files shipped with Ruby twice to test for idempotency.

### `stree` CLI

The `syntax_tree` gem now ships with an `stree` executable that functions as a CLI for formatting files. It provides a lot of additional functionality is well (like displaying the syntax tree or the doc node print tree). One additional nicety that it provides is the ability to run `stree check **/*` which will exit `1` if any files are not formatted as expected (which allows running this in a continuous integration environment).

### Language server

Recently, I added language server support to the `syntax_tree` project to support integrating with editors that support the language server protocol. The code for that lives [here](https://github.com/kddnewton/syntax_tree/blob/0d3e9b7bcc0b198ca92b617cc787b17744035dd8/lib/syntax_tree/language_server.rb). Currently it supports the `textDocument/formatting` request type, which allows `formatOnSave` functionality (you can turn this on in your editor of choice today by manually bundling the language server).

One additional piece of functionality that the language server provides is the custom `syntaxTree/visualizing` request. This request returns the syntax tree of the file corresponding to the given URI, which allows the requesting editor to display a tree-like structure inline with the code being edited. In VSCode, if you execute `syntaxTree.visualize`, it will now open a side-by-side tab with the displayed tree.

## Future work

I still have lots of functionality I'd like to bring to `syntax_tree` and its related projects. I also have some far-flung dreams that may or may not come to fruition. First, here are the things that I definitely intend to complete before the end of this project:

* I'd like to upstream the `syntax_tree` AST builder, the `ripper` documentation, and the `prettyprint` updates. I'll be asking for feedback on them soon, but ideally all of this would ship with CRuby to make it easier for it to stay up-to-date with syntax changes as they are built.
* I'd like to enhance the language server to not only provide the syntax tree as a custom request but to support it on hover so that you can hover over any syntactic structure in your code and have it explained. I think this will help both new programmers coming to Ruby to learn the syntax but also help veteran Rubyists learn new syntax as it comes out.
* I'd like to enhance the language server to better support incremental changes. At the moment, each time a file is changed the entire file is reparsed. This isn't necessary because the change request comes with the changes ranges. We can instead only reparse the subset of the file that changed and replace the encapsulating nodes in the tree that correspond to those changes.

That's the extent of the work that corresponds to the proposed work in the grant proposal. However, I have addition desires for other future work beyond the scope of this grant. That includes:

* A well-defined interface for programmatic code modification functionality. Currently you _can_ replace nodes and have them formatted correctly, meaning you can programmatically change Ruby code. However, doing this is definitely not easy and requires a lot of knowledge of `syntax_tree` internals. Ideally this would be a lot easier.
* A backend for the `parser` gem. Ideally I'd like to create an interface layer that would convert `syntax_tree` nodes into their `parser` gem counterparts. I'd like to do this because it would make it trivial for gems that are consumers of the `parser` gem to switch to using `syntax_tree` as the parser for some additional speed boosts. Note that this wouldn't mean switching off the `parser` gem, it would just mean that the parsing would be faster.
* Decoupling the parsing functionality (the `ripper` subclass) from the `syntax_tree` node definitions. In the far future, this could potentially mean being able to switch out the parser backing `syntax_tree` from `ripper` to some other tool but maintaining all of the functionality built into the various node types.

The final report for this grant is due March 18th, and I will be publishing it here. If you're interested in following this project, you can watch the `syntax_tree` repository or check/subscribe to this blog.
