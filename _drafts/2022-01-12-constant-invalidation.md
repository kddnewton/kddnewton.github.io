Finer-grained inline constant cache invalidation

When a constant expression appears in code, Ruby adds an inline cache object into the associated instruction sequence. That inline cache keeps track of the value of the constant the last time it was looked up so that it doesn't have to be fetched each time that instruction is executed.

This cache is invalidated any time:

* a constant is assigned (`X = 1`)
* a constant is removed (`remove_const(:X)`)
* a constant has its visibility changed (`private_constant(:X)`)
* a module is included (`include X`)
* a module is found to be missing through `const_missing`

Currently the way invalidation works is that every inline cache stores an integer representing the global constant state that was set the last time the value was fetched. If the global constant state has not changed (i.e., the values match) then the cache is hit. Otherwise, it's a cache miss, the value is refetched and the new global constant state is stored.

Unfortunately, some applications do undesirable things like setting constants at runtime, which ends up invalidating every cache in the application. This imposes a penalty on all of the subsequent constant lookups, which can add up to a lot of waste cycles. For example, if you had some code in your application that ran `X = 1` on every request (unlikely, but possible), your caches to `Y` and `Z` would always miss even though they're unrelated.

The current behavior also has serious implications for YJIT. Since YJIT specializes on runtime values, it _must_ rely upon consistent values for constants. Therefore we currently have to track which basic blocks have dependencies on the global constant state. If that global constant state changes, then we have to invalidate every basic block that depended on it, which means throwing out a whole bunch of generated code. Without code GC, this makes it even worse, because now we have dead code lying around taking up space in our allocated memory region.

This commit changes the behavior of our inline constant caches. Instead of relying on a global constant state, they instead just check if the cache has been populated. If the cache is empty, it performs the constant lookup again. So to invalidate the cache, we just clear the cache entry.

The first time the `opt_getinlinecache` instruction is hit the cache is empty. It sees this, and walks through the ISEQ to find all of the `getconstant` calls that exist between the `opt_getinlinecache` and the `opt_setinlinecache` instruction. For each of the `getconstant` instructions it pulls out the `ID` associated with it and puts it into the VM's new `constant_cache` `st_table`. The `st_table` contains all of the inline cache objects that are associated with that `ID`. We then insert the `IC` into that table in a nested `st_table`. So for example, if you ran the following code:

```ruby
[X, X::Y, Y]
```

You would get the following instructions:

```
== disasm: #<ISeq:<main>@test.rb:1 (1,0)-(1,12)> (catch: FALSE)
0000 opt_getinlinecache                     9, <is:0>                 (   1)[Li]
0003 putobject                              true
0005 getconstant                            :X
0007 opt_setinlinecache                     <is:0>
0009 opt_getinlinecache                     22, <is:1>
0012 putobject                              true
0014 getconstant                            :X
0016 putobject                              false
0018 getconstant                            :Y
0020 opt_setinlinecache                     <is:1>
0022 opt_getinlinecache                     31, <is:2>
0025 putobject                              true
0027 getconstant                            :Y
0029 opt_setinlinecache                     <is:2>
0031 newarray                               3
0033 leave
```

There are 3 inline caches in the ISEQ above (`is:0`, `is:1`, and `is:2`). The first would be associated with the `ID` `X`, the second with both `X` and `Y`, and the third with just `Y`. So you would end up with a table on the VM that looked something like:

```
{
  X => <is:0>, <is:1>
  Y => <is:1>, <is:2>
}
```

To invalidate the cache, previously we would increment the global constant state. In this new behavior, we instead determine which `ID`s need to be invaliated, and walk through the VM's table to clear out any caches associated with those `ID`s. So, for example, if we changed the value of `Y` in the previous example, we would be clearing the cache entries for `<is:1>` and `<is:2>`.

