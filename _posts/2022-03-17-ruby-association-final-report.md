---
layout: post
title: Ruby Association Final Report
---

In accordance with the Ruby Association's timeline, this is the final report on the [Ruby formatter](https://www.ruby.or.jp/en/news/20211025) project.

## Deliverables

When the project was initially proposed to create a standard library formatter, a list of 5 delivers was created. Below I detail what the initial proposal for each one was, as well as the work that ended up being done.

### `ripper` updates

A definitive representation of the Ruby syntax tree based on `ripper` was proposed. The existing `ripper` subclasses ship without location information for inner nodes, discard comments in the final representation, and don't have named fields. These issues and more are remedied in the new `Ripper::Tree` subclass. This subclass is now backing the formatter [here](https://github.com/ruby-syntax-tree/syntax_tree/blob/773315c1157c9279933f19da69ad9d102dae8d8c/lib/syntax_tree.rb) as the basis for the syntax tree. Its main benefits are:

* It uses class instances instead of arrays to represent nodes. This has the benefit of explicitness as well as documentation.
* Comments are automatically attached to the various nodes when parsing is finished. This makes it much easier to detect which comments "belong" to which nodes.
* A couple of additional nodes are added for clarity (i.e., `ArgStar`, `Not`, `PinnedBegin`, etc.) as opposed to having to rely on contextual information.
* Every node has location information attached to it (as opposed to just the scanner event nodes). This is vital for formatting.
* There's a standard interface for descending the tree (the `child_nodes` method).

This work hasn't been merged upstream, but the pull request has been opened [here](https://github.com/ruby/ruby/pull/5679).

### `prettyprint` updates

Updates and enhancements to the `prettyprint` library were proposed. In general, `prettyprint` is well suited to printing out object descriptions but lacks enough necessary functionality to be able to accurately print a programming language like Ruby. Many (non-breaking) updates were made to the `prettyprint` library to enhance it enough to power the formatter. The following issues have been addressed:

* `prettyprint` assumed that content in `Text` would not change its representation if it was contained within a broken group versus contained within a flat group. This wasn't a problem for the existing uses of `prettyprint`, but for the purposes of building a formatter, it definitely was. Consider something like trailing commas (where you want a comma if it is broken but nothing if it's not) or block operators (where you would use a do and end for multi-line (broken group) or braces for single line (flat group)).
* The `Breakable` class assumed that you always wanted to indent the subsequent line up to the current indentation level. This was true in most cases, and certainly for all the existing use cases. But there are times when you don't want that behavior (for example if you're in the middle of a nested indentation structure but have to force content to start at the beginning of the next line as in a comment with `=begin`..`=end` bounds).
* There was previously no way to force a group to break. You can access the current group in the printer with `current_group`, but that wouldn't force the parent groups to break. Without hacking around a lot of stuff, it was difficult to get this behavior. This is necessary if you want to ensure a newline is added and respected, like after a keyword where it would be necessary.

These issues were addressed with a small algorithm change and the additional of many node types in the print tree. From the user of this class's perspective, nothing is different. Internally however, there's a bunch of additional functionality and a lot more control over the printing algorithm! Also the ability to debug has been greatly enhanced with `pretty_print` methods on each of the nodes and the ability to walk the print tree nodes before they're printed.

This work hasn't been merged upstream, but the pull request has been opened [here](https://github.com/ruby/prettyprint/pull/3).

### Formatter

A formatter for Ruby source code was proposed. With the work done on the `ripper` subclass and the `prettyprint` updates, this amounted to combining those two efforts by defining formatting functions on each of the node types.

That work was all bundled up into the `syntax_tree` gem (now published). You can see how all of that formatting is performed [here](https://github.com/ruby-syntax-tree/syntax_tree/blob/773315c1157c9279933f19da69ad9d102dae8d8c/lib/syntax_tree.rb). Particularly look at all of the `format` methods, as well as the various classes and modules created to support those methods.

### CLI

A CLI for formatting files was proposed. When the formatter was finished, this was a matter of triggering its execution from the command line.

This work has been bundled up into the [cli.rb](https://github.com/ruby-syntax-tree/syntax_tree/blob/773315c1157c9279933f19da69ad9d102dae8d8c/lib/syntax_tree/cli.rb) file in the `syntax_tree` gem. It includes the proposed functionality of formatting Ruby code. It also supports various other helpful functionality, a subset of which is listed below.

* `stree ast FILE` - prints out the AST corresponding to the given files.
* `stree check FILE` - ensures that the given files are formatted as `syntax_tree` would format them.
* `stree format FILE` - prints out the formatted version of the given files.
* `stree write FILE` - reads, formats, and writes back the source of the given files.

### Language server

A language server supporting the `formatOnSave` option was proposed.

A subset of the language server protocol has been implemented in the `syntax_tree` gem and supports the `formatOnSave` option [here](https://github.com/ruby-syntax-tree/syntax_tree/blob/773315c1157c9279933f19da69ad9d102dae8d8c/lib/syntax_tree/language_server.rb). A couple other features were added as well (the ability to disassemble the YARV bytecode for a given method, various inlayed code hints, as well as the ability to see the syntax tree). These features and more were also built into a [VSCode plugin](https://github.com/ruby-syntax-tree/vscode-syntax-tree) to make it easier for developers to integrate into their workflows.

## Future work

I still plan to build lots of additional functionality into `syntax_tree` and its related projects. Some of that functionality includes:

* A well-defined interface for programmatic code modification functionality. Currently you _can_ replace nodes and have them formatted correctly, meaning you can programmatically change Ruby code. However, doing this is definitely not easy and requires a lot of knowledge of `syntax_tree` internals. Ideally this would be a lot easier.
* A backend for the `parser` gem. Ideally I'd like to create an interface layer that would convert `syntax_tree` nodes into their `parser` gem counterparts. I'd like to do this because it would make it trivial for gems that are consumers of the `parser` gem to switch to using `syntax_tree` as the parser for some additional speed boosts. Note that this wouldn't mean switching off the `parser` gem, it would just mean that the parsing would be faster.
* Decoupling the parsing functionality (the `ripper` subclass) from the `syntax_tree` node definitions. In the far future, this could potentially mean being able to switch out the parser backing `syntax_tree` from `ripper` to some other tool but maintaining all of the functionality built into the various node types.

If you're interested in following this project, you can watch the [ruby-syntax-tree/syntax_tree](https://github.com/ruby-syntax-tree/syntax_tree) repository or check/subscribe to this blog. I've also started a blog series describing how this project was built, which you can start reading with the [introductory post](/2022/02/03/formatting-ruby-part-0).
