---
layout: post
title: Formatting Ruby
subtitle: Part 0 - Introduction
---

Last October, the Ruby Association selected its [2021 grant recipients](https://www.ruby.or.jp/en/news/20211025) for the various projects around the Ruby ecosystem that they would support. Among them was my proposal to create a standard library Ruby formatter. Below is the description of the project, as per the submission:

> Ruby formatter is a reimplementation of the prettier plugin for Ruby written in pure Ruby. It will provide an executable that can be used to format Ruby files from the command line. It will also provide a language server that can be used to integrate with Its implementation will be based on both the ripper and prettyprint gems, with additional functionality being added to both.

Work on this project is well underway; you can check out the current state of affairs in the [kddnewton/syntax_tree](https://github.com/kddnewton/syntax_tree) repository on GitHub or read my previous post on this blog detailing the [intermediate report](/2022/01/17/ruby-association-intermediate-report).

As a part of this work, and an introduction to the Ruby community, I've planned out a series of blog posts on the formatter that will show how I made it, why I made it, and how you can use it. The planned posts are the following:

* [Formatting Ruby: Part 1](/2022/02/14/formatting-ruby-part-1) - How ripper works
* Formatting Ruby: Part 2 - Building the syntax tree
* Formatting Ruby: Part 3 - How prettyprint works
* Formatting Ruby: Part 4 - Formatting the syntax tree
* Formatting Ruby: Part 5 - Building the CLI
* Formatting Ruby: Part 6 - Building the language server
* Formatting Ruby: Part 7 - Extending the language server

When the posts are done, this post will link back to all of them. I'm planning (hoping) to write one per week, which means this blog series would end just after the final report of the project is due on March 18th. (Maybe we'll squeeze two into one week to get it done on time, but no promises.)

If you're interested in this work and how you can use it to improve your Ruby development experience, check back here, follow me on twitter, or subscribe to the RSS feed at the bottom of this page. See you next week.
