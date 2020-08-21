---
layout: post
title: Prettier's encoding bug
---

About a month ago, a curious bug was reported on the `prettier` plugin for Ruby in this issue: [prettier/plugin-ruby#596](https://github.com/prettier/plugin-ruby/issues/596). It stated that the parser was failing with an error saying that there was an invalid byte sequence for `US-ASCII` encoding. What made things even more confusing was that it only occured when it was being run through the JavaScript side, not just through the Ruby side.

Encodings have always felt a big like black magic to me, and this issue was no exception. What follows is every rabbit hole I went down before finally figuring out the answer. My hope is that if someone ends up in a similar situation where they know nothing about encoding, this might serve as a bit of a guidepost.

1. First, I just tried to replicate the issue. I installed the exact same version of Ruby, node, and VSCode. Then I ran every conceivable combination of printing and parsing files that I could think of. No dice, on my machine it continued to work normally.
2. Next, I tried going down the plain Ruby route. I started checking out methods like [String#encode](https://ruby-doc.org/core-2.7.1/String.html#method-i-encode) and [String#force_encoding](https://ruby-doc.org/core-2.7.1/String.html#method-i-force_encoding) trying to shoehorn the source string into the correct encoding. No matter what I tried I couldn't get it to replicate.
3. At this point I gave in and decided I had to have more information if I was going to continue. I started asking the folks reporting the issue to start printing out massive amounts of debugging information. This included `ruby -e 'pp RbConfig::CONFIG'` (to try to see if it was a Ruby configuration issue) and `ruby -rripper -e "pp Ripper.sexp('ä')"` (to see if it could parse non-ASCII strings at all). Eventually one of the reporters of the issue noticed that `ruby -e "pp 'ä'.encoding"` was always returning `US-ASCII` by default, which led to the next steps.

Once we determined it had to do with the default encoding for strings within Ruby, we got more narrowed down. I started looking into the Ruby source, trying to figure out how Ruby determines its default encoding. A quick search of the [ruby/ruby repository](https://github.com/ruby/ruby) for `UTF-8` led me to this file: [langinfo.c](https://github.com/ruby/ruby/blob/master/missing/langinfo.c). This file has a [couple of lines](https://github.com/ruby/ruby/blob/master/missing/langinfo.c#L44-L46) that included a certain header file if a special constant was defined. While this didn't feel like the answer yet, it seemed like enough of a flag to catch my attention because those constant could be defined on a per-system level. To test whether or not I had the constant defined on my machine, I created a `test.c` file and added this code:

```c
#include <stdio.h>

#ifdef HAVE_LANGINFO_H
  printf("TESTING!\n");
#endif

int main() {
  return 0;
}
```

Don't mind the fact that the code doesn't actually even work. The important part is that the file won't even compile correctly if `HAVE_LANGINFO_H` is defined. After running `gcc test.c` and seeing that it did in fact work, I knew I didn't have that constant defined. (For good measure I changed it to `#ifndef` and verified). A quick search of this constant actually led me to a [python bug](https://bugs.python.org/issue22747) of all things. The description of which pointed me to the `LC_ALL`, `LC_CTYPE`, and `LANG` environment variables.

It is at this point that I should mention that there are plenty of programmers in the world that understanding encoding far better than I do, and would probably have hit this point much sooner. Regardless, we're here now, so continuing on.

{:start="4"}
4. Searching through `ruby/ruby` for those environment variables led me to a nice comment in [encoding.c](https://github.com/ruby/ruby/blob/master/encoding.c#L1843-L1870) that clearly shows how you can set the `LANG` environment variable to control external encoding, which will in turn control the manner in which Ruby attempts to parse code. At this point it seemed clear that all I would have to do would be to pass the `LANG` variable down into the Ruby parsing process when it was being spawned and everything would work. Simple enough, here's the code that I ended up writing:

```diff
  const child = spawnSync(
    "ruby",
    ["--disable-gems", path.join(__dirname, "./ripper.rb")],
    {
+     env: { LANG: "UTF-8" },
      input: text,
      maxBuffer: 10 * 1024 * 1024 // 10MB
    }
  );
```

This actually ended up working perfectly (on my machine). To make sure I didn't end up shipping something that wasn't going to up fixing it on others however, I wrote the following test:

```javascript
const { spawnSync } = require("child_process");
const path = require("path");

// This is just a way to get the stderr to print out in the event that the
// process that we're testing failed with an unexpected error code.
expect.extend({
  toHaveExitedCleanly(child) {
    return {
      pass: child.status === 0,
      message: () => child.stderr.toString()
    };
  }
});

test("different lang settings don't break", () => {
  const script = path.join(__dirname, "../../node_modules/.bin/prettier");
  const child = spawnSync(
    process.execPath,
    [script, "--plugin", ".", "--parser", "ruby"],
    {
      env: {
        LANG: "US-ASCII"
      },
      input: "'# あ'"
    }
  );

  expect(child).toHaveExitedCleanly();
});
```

This test spawns the prettier process with the `LANG` environment variable for the overall system set to `US-ASCII` (which replicates the system of the users that initially reported the error). Fortunately it passes and failed depending on adding and removing that line in `parser.js`, so I assumed I was done.

Unfortunately, it failed in CI. As it turns out, `UTF-8` is not actually a valid locale outside of Mac (the machine I used to develop). It turns out that Mac has special handling for this locale to switch it to `en_US.UTF-8` automatically depending on your configuration. What linux expects is a different value: `C.UTF-8`. And after further searching it appears that Windows actually wants `.UTF-8`.

So, back to `parser.js`, we can extend it even further with:

```diff
+const LANG = {
+  aix: "C.UTF-8",
+  darwin: "UTF-8",
+  freebsd: "C.UTF-8",
+  linux: "C.UTF-8",
+  openbsd: "C.UTF-8",
+  sunos: "C.UTF-8",
+  win32: ".UTF-8"
+}[process.platform];
+
 const child = spawnSync(
   "ruby",
   ["--disable-gems", path.join(__dirname, "./ripper.rb")],
   {
-    env: { LANG: "UTF-8" },
+    env: { LANG },
     input: text,
     maxBuffer: 10 * 1024 * 1024 // 10MB
   }
 );
```

Finally, it passed both locally and on CI.

## tl;dr

Ruby infers the encoding in use by your system using the environment variables `LC_ALL`, `LC_CTYPE`, and `LANG`. If your system doesn't have `nl_langinfo`, it will replicate it for you. If you're going to spawn a Ruby process, make sure you have your encoding set correctly. The pull request that ended up fixing this is here: [prettier/plugin-ruby#617](https://github.com/prettier/plugin-ruby/pull/617/files).
