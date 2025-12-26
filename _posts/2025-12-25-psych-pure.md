---
layout: post
title: A Ruby YAML parser
---

Recently I built the [psych-pure](https://github.com/kddnewton/psych-pure) gem, a pure-Ruby implementation of a YAML 1.2 parser and emitter. It fully conforms to the YAML 1.2 specification, passes the entire YAML test suite, and allows you to preserve comments when loading and dumping YAML documents. This post explains how and why.

## Motivation

First, let's talk about YAML. YAML is a surprisingly complex data serialization format. It supports a wide variety of data types and syntactic structures, making it both powerful and a huge pain to implement correctly. If you check out [matrix.yaml.info](https://matrix.yaml.info/) you'll see that very few of the YAML parsers in use fully conform to the YAML 1.2 spec.

Notably, the one used by Ruby — [libyaml](https://github.com/yaml/libyaml) — errors out on quite a few of the test cases. The slightly more modern [libfyaml](https://github.com/pantoniou/libfyaml) does much better, being one of the only implementations that actually conforms to the whole spec. Unfortunately it does not support Windows. So if you want to parse YAML in Ruby, the best option remains [psych](https://github.com/ruby/psych), a wrapper around `libyaml`.

It has always bothered me to not see a Ruby implementation on that list. First and foremost because of the comformance reasons, but secondly because it just feels odd to not have a pure-Ruby option for something so fundamental to the Ruby ecosystem.

The other reason I wanted to build this is that `libyaml` discards comments as they are being parsed. This means if you want to be able to load YAML, modify it, and dump it, you're going to lose all comments in the process. This has been discussed [before](https://github.com/ruby/psych/issues/464) a [few times](https://github.com/ruby/psych/issues/566) on the issue tracker, with various [workarounds](https://github.com/wantedly/psych-comments/) proposed. Nothing truly solves the problem though. These workarounds suffer from the same classic problem parsing context-free grammars with regular expressions always have: the grammar is [not powerful enough](https://stackoverflow.com/questions/1732348/regex-match-open-tags-except-xhtml-self-contained-tags). The only truly viable solutions at this point is to develop a proper parser, either by bringing Windows support to `libfyaml` and wrapping it in a Ruby native extension, or building a pure-Ruby implementation. I decided to go with the latter.

## Implementation

Fortunately, a project exists under the `yaml` organization on GitHub called the [yaml-reference-parser](https://github.com/yaml/yaml-reference-parser). This repository contains language-agnostic infrastructure to template out a YAML 1.2 spec-conforming parser. You have to provide a bunch of the pieces and write a not-insignificant amount of CoffeeScript, but the heavy lifting is done for you. This formed the basis of my implementation. Unfortunately this generates a wildly inefficient parser, so I had to spend a fair amount of time inlining methods and moving things around to get it to a reasonable performance level.

To validate the implementation, I needed a test suite. The `yaml` organization also provides the [yaml-test-suite](https://github.com/yaml/yaml-test-suite), a collection of hundreds of YAML documents designed to test the conformance of YAML parsers. Unfortunately, the canonical way to run these tests is through [testml](https://github.com/testml-lang/testml), a sort of DSL-like language that describes tests. Therefore I ended up adding [Ruby support](https://github.com/testml-lang/testml/pull/64) to `testml` in the process of building this. With that in place, I was able to run the entire test suite against my implementation and ensure it conformed to the spec.

At this point, the parser was functional and able to parse and load YAML documents correctly. I now needed to start working on supporting comments. I ended up following the same approach I took with the [Prism parser](https://github.com/ruby/prism/blob/26b745f39afd4d4d1b57abe4c6eba64e79b74695/lib/prism/parse_result/comments.rb#L93-L114) which is itself a port of the way that the [Prettier formatter](https://github.com/prettier/prettier/blob/6c339cd882bfa735bb574358f31225faff1477d9/src/main/comments/attach.js#L113-L245) handles comments. After parsing the document, it walks the AST, determines following, preceding, and enclosing nodes, and attaches the comments accordingly. Then, it is the responsibility of the emitter to place the comments back in the right places when dumping the document.

Unfortunately, this meant writing my own YAML emitter as well, since the one provided by `psych` is not aware of comments on nodes. It also meant that loaded objects (e.g., hashes and arrays) needed to be wrapped in custom delegator classes to hold on to their comments in the case that they get dumped back out to YAML. This ended up being tedious for [Hash](https://github.com/kddnewton/psych-pure/blob/63a50cb7c6b32389ffe73af420240e64f175130e/lib/psych/pure.rb#L254-L515) because I ended up needing to re-implement every mutating method, but for the most part it was straightforward.

At this point, all that remained was to copy over the public API of `Psych` onto `Psych::Pure`, such that it functions as a drop-in replacement. This means whatever visitors or handlers you may have written for `Psych` should work with `Psych::Pure` as well.

## Conclusion

In the end, I am quite happy with how this turned out. The Ruby community now has a fully spec-conforming YAML 1.2 parser and emitter written in pure Ruby, which also preserves comments. In fact it joins Perl as the only two languages with fully cross-platform implementations. If any of you feel up to it, I would love to see it listed in the matrix at [matrix.yaml.info](https://matrix.yaml.info/) by adding it to [yaml-runtimes](https://github.com/yaml/yaml-runtimes)! As always, contributions and feedback are welcome on the [GitHub repository](https://github.com/kddnewton/psych-pure). Happy holidays, and happy Ruby 4.0!

