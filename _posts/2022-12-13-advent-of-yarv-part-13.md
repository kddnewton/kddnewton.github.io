---
layout: post
title: Advent of YARV
subtitle: Part 13 - Constants
meta:
  "twitter:card": summary
  "twitter:title": "Advent of YARV: Part 13"
  "twitter:description": "This post is part of a series about how the YARV virtual machine works."
  "twitter:site": "@kddnewton"
  "twitter:image": https://upload.wikimedia.org/wikipedia/commons/thumb/7/73/Ruby_logo.svg/1200px-Ruby_logo.svg.png
---

This blog series is about how the CRuby virtual machine works. If you're new to the series, I recommend starting from [the beginning](/2022/11/30/advent-of-yarv-part-0). This post is about constants.

Constants in Ruby exist in their own tree. Accessing them involves looking them up by walking up the tree according to your current constant nesting. The details of that specific algorithm are outside the scope of this post, but you can read more about it in the [Ruby documentation](https://ruby-doc.org/3.1.2/syntax/modules_and_classes_rdoc.html).

* [putspecialobject](#putspecialobject)
* [getconstant](#getconstant)
* [setconstant](#setconstant)
* [opt_getconstant_path](#opt_getconstant_path)

## `putspecialobject`

push a special object on the stack

## `getconstant`

get a constant

## `setconstant`

set a constant

## `opt_getconstant_path`

get a constant from a path

## Wrapping up
