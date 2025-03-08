---
layout: post
title: AArch64 Bitmask Immediates
---

This post illustrates a small but fascinating piece of the [AArch64](https://en.wikipedia.org/wiki/AArch64) architecture called bitmask immediates. We'll briefly cover what AArch64 is, how it is different from other architectures, what a bitmask immediate is, and how all of this can be encoded in Rust.

For context, I work at Shopify on [YJIT](https://github.com/Shopify/yjit), a just-in-time compiler for CRuby. Lately I've been working on adding support for the AArch64 architecture; practically this means support for Apple M1s. Learning the ARM architecture and encoding it has been quite an adventure; you can check out our [working branch](https://github.com/Shopify/ruby/tree/yjit_backend_ir/yjit/src/asm/arm64) if you'd like to follow along.

## Fixed-width instruction sets

First, a bit of background. AArch64 is a fixed-width instruction set of 32-bits. That means every instruction, every time, is 32-bits. This is pretty different from, for example, [x86-64](https://en.wikipedia.org/wiki/X86-64), which allows variable-width instructions making encoding large values quite a bit easier.

For example, if you're attempting to move a 64-bit value into a 64-bit register, it's 1 instruction on x86-64, and (at worst) 4 instructions on AArch64. Let's say the value is `0xC3FFFFFFC3FFFFFF`. On x86-64, you would run:

```
mov %RAX, 0xC3FFFFFFC3FFFFFF
```

([Compiler Explorer](https://godbolt.org/z/MabvKPbsf)). This says to move the immediate 64-bit value into the RAX register, overwriting whatever was there previously. This encodes as:

```
48 B8 FF FF FF C3 FF FF FF C3
^^^^^
mov RAX
      ^^^^^^^^^^^^^^^^^^^^^^^
      0xC3FFFFFFC3FFFFFF
```

That's 10 bytes in total. On AArch64, you would instead run:

```
movz X0, #0xC3FF
movk X0, #0xFFFF, lsl 16
movk X0, #0xC3FF, lsl 32
movk X0, #0xFFFF, lsl 48
```

([Compiler Explorer](https://godbolt.org/z/KdKTMP6zv)). This says to first, move the `0xC3FF` 16-bit value into the X0 register and clear out the rest of the register by setting all other bits to 0. Then move the `0xFFFF` 16-bit value into the X0 register shifted left (lsl means logical shift left) by 16 bits, and keep the other bits in the register the same (i.e., leave `0xC3FF` in place). Then do the same for the other two 16-bit values. This encodes as:

```
E0 7F 98 D2 E0 FF BF D2 E0 7F D8 D2 E0 FF FF D2
^^^^^^^^^^^
movz X0, 0xC3FF
            ^^^^^^^^^^^
            movk X0, 0xFFFF, lsl 16
                        ^^^^^^^^^^^
                        movk X0, 0xC3FF, lsl 32
                                    ^^^^^^^^^^^
                                    movk X0, 0xFFFF, lsl 48
```

That's 16 bytes (4 for each 4-byte instruction). Because the width of the value that we're trying to move into the register is larger than the width of the instructions, AArch64 designers were forced to be a bit creative by splitting up the overall immediate.

## Bitmask immediates

There is another encoding for this same operation that can be accomplished in one instruction, however. A very common use-case when you're writing assembly is to compare a value against a bitmask, as in `value & 0b1111` to pull out the lower 4 bits of a number. This was common enough that the designers of AArch64 came up with a way to encode the most common patterns of bitmasks all of the way up to 64-bits, while excluding the less common patterns: bitmask immediates.

The official [documentation](https://developer.arm.com/documentation/dui0802/b/A64-General-Instructions/MOV--bitmask-immediate-#:~:text=Is%20the%20bitmask%20immediate%2e) for ARM explains bitmask immediates in the following way:

> Such an immediate is a 32-bit or 64-bit pattern viewed as a vector of identical elements of size e = 2, 4, 8, 16, 32, or 64 bits. Each element contains the same sub-pattern: a single run of 1 to e-1 non-zero bits, rotated by 0 to e-1 bits. This mechanism can generate 5,334 unique 64-bit patterns (as 2,667 pairs of pattern and their bitwise inverse). Because the all-zeros and all-ones values cannot be described in this way, the assembler generates an error message.

Like our example above, usually you've got one or more sequential 1s that you want to use in a logical comparison (e.g., `or`, `and`, `xor`, etc.). To encode this kind of pattern on AArch64, these instructions have allocated 13 bits within the 32-bit instruction. Those 13 bits are broken up into 3 parts:

* `N` (1 bit) - whether or not the pattern we're encoding is 64-bits wide
* `imms` (6 bits) - the size of the pattern, a 0, and then one less than the number of sequential 1s
* `immr` (6 bits) - the number of right rotations to apply to the pattern

Both `N` and `immr` are relatively quick to understand because they correspond to other constructs in the instruction set. `imms` however is quite a mind-bender. This table helps illuminate what we're talking about here:

| imms          | element size | number of 1s |
| ------------- | ------------ | ------------ |
| `1 1 1 1 0 x` | 2 bits       | 1            |
| `1 1 1 0 x x` | 4 bits       | 1-3          |
| `1 1 0 x x x` | 8 bits       | 1-7          |
| `1 0 x x x x` | 16 bits      | 1-15         |
| `0 x x x x x` | 32 bits      | 1-31         |
| `x x x x x x` | 64 bits      | 1-63         |

Below I'll show a couple of examples of these values being encoded.

### 2-bit patterns

When `imms` starts with `11110x`, it means that the pattern is 2 bits in size, and the number of 1s is always 1. In this case `immr` can only effectively indicate that it can be rotated 0 or 1 time. The only pattern this works for is `01`, which can optionally be right-rotated by 1 bit. The resulting 2 options for 2-bit patterns are:

| N   | imms     | immr     | bits                                                               |
| --- | -------- | -------- | ------------------------------------------------------------------ |
| `0` | `111100` | `000000` | `0101010101010101010101010101010101010101010101010101010101010101` |
| `0` | `111100` | `000001` | `1010101010101010101010101010101010101010101010101010101010101010` |

### 4-bit patterns

When `imms` starts with `1110xx`, it means that the pattern is 4 bits in size, and there can be 1, 2, or 3 sequential 1s. This works for `0001`, `0011`, and `0111`, and all of the allowable right-rotations of these numbers (e.g., `0001` can actually have a 1 in any position). The resulting 12 options for 4-bit patterns are:

| N   | imms     | immr     | bits                                                               |
| --- | -------- | -------- | ------------------------------------------------------------------ |
| `0` | `111000` | `000000` | `0001000100010001000100010001000100010001000100010001000100010001` |
| `0` | `111000` | `000001` | `1000100010001000100010001000100010001000100010001000100010001000` |
| `0` | `111000` | `000010` | `0100010001000100010001000100010001000100010001000100010001000100` |
| `0` | `111000` | `000011` | `0010001000100010001000100010001000100010001000100010001000100010` |
| `0` | `111001` | `000000` | `0011001100110011001100110011001100110011001100110011001100110011` |
| `0` | `111001` | `000001` | `1001100110011001100110011001100110011001100110011001100110011001` |
| `0` | `111001` | `000010` | `1100110011001100110011001100110011001100110011001100110011001100` |
| `0` | `111001` | `000011` | `0110011001100110011001100110011001100110011001100110011001100110` |
| `0` | `111010` | `000000` | `0111011101110111011101110111011101110111011101110111011101110111` |
| `0` | `111010` | `000001` | `1011101110111011101110111011101110111011101110111011101110111011` |
| `0` | `111010` | `000010` | `1101110111011101110111011101110111011101110111011101110111011101` |
| `0` | `111010` | `000011` | `1110111011101110111011101110111011101110111011101110111011101110` |

### Other patterns

You can see that this idea can be replicated to the 8-bit, 16-bit, 32-bit, and 64-bit options. Notice that for 64-bit patterns, the values are not copied since it fills the entire width.

## Encoding values

It's important to note that not every value can be encoded. If the value does not correspond to a binary representation that consists of one set of sequential 1s that can be copied up to 64 bits, it can't be encoded. The problem then becomes finding the correct values for `N`, `imms`, and `immr` for a given value if that triplet exists.

The language I'm writing this in is Rust, but pretty much any language can do the kind of bit manipulation necessary to determine these values. Rust does have some niceties that I'll take advantage of though. Since we are attempting to convert an unsigned integer into a bitmask immediate, I'll first define a struct for the bitmask immediate:

```rust
pub struct BitmaskImmediate {
    n: u8,
    imms: u8,
    immr: u8
}
```

Next, I'll implement `TryFrom<u64>` for `BitmaskImmediate`. You could implement this for each unsigned integer size, but we pass around unsigned integers in our intermediate representation so this is the only one I need. The outline for implementing this trait looks like the following:

```rust
impl TryFrom<u64> for BitmaskImmediate {
    type Error = ();

    fn try_from(value: u64) -> Result<Self, Self::Error> {
        Err(())
    }
}
```

Implementing this trait allows us to call:

```rust
let immediate: Result<BitmaskImmediate, _> = 7.try_into();
```

We are then free to unwrap, map, or otherwise manipulate the result as we see fit.

The first steps in implementing this trait are some edge cases. The documentation specifically mentions that all 0s and all 1s cannot be represented as a bitmask immediate. We'll handle those first:

```rust
if value == 0 || value == u64::MAX {
    return Err(());
}
```

The next step is to determine the size of the pattern that we're dealing with. To do this, we'll start at 64-bits and work downward. If the binary representation of the value is equal to itself when shifted by 32 bits, then we know we can continue. Otherwise, it must be a 64-bit pattern. Similarly, if the binary representation of the value is equal to itself when shifted by 16 bits, we can continue on. We continue on in this manner until we find the size. That code looks like the following:

```rust
let mut imm = value;
let mut size = 64;

loop {
    size >>= 1;
    let mask = (1 << size) - 1;

    if (imm & mask) != ((imm >> size) & mask) {
      size <<= 1;
      break;
    }

    if size <= 2 {
        break;
    }
}
```

Now that we have the size, we also inherently have the pattern — although it may be rotated. So the next step is to determine the number of left rotations to get it back to having all 1s on the right side and all 0s on the left side. To do that, we'll first need to quick helper functions.

```rust
/// Is this number's binary representation all 1s?
fn is_mask(imm: u64) -> bool {
    ((imm + 1) & imm) == 0
}

/// Is this number's binary representation one or more 1s followed by
/// one or more 0s?
fn is_shifted_mask(imm: u64) -> bool {
    is_mask((imm - 1) | imm)
}
```

These utility functions are necessary to help us figure out when the pattern has been rotated enough. Finally, we can find the number of rotations. If the number is already a shifted mask (i.e., it's just a series of 1s and then a series of 0s) it's relatively trivial to find the number of rotations: count the number of trailing 0s. If it's split up (like `1001`), then we need to add together the number of trailing and leading 0s. (Because of number representations, we actually flip all of the bits first to make them 1s first.) The code to do that looks like the following:

```rust
let trailing_ones: u32;
let left_rotations: u32;

let mask = u64::MAX >> (64 - size);
imm &= mask;

if is_shifted_mask(imm) {
    left_rotations = imm.trailing_zeros();
    trailing_ones = (imm >> left_rotations).trailing_ones();
} else {
    imm |= !mask;
    if !is_shifted_mask(!imm) {
        return Err(());
    }

    let leading_ones = imm.leading_ones();
    left_rotations = 64 - leading_ones;
    trailing_ones = leading_ones + imm.trailing_ones() - (64 - size);
}
```

Now that we have the size of the pattern, the number of sequential 1s, and the number of rotations, we have all of the information that we need. We can encode the values of `N`, `imms`, and `immr` like so:

```rust
// immr is the number of right rotations it takes to get from the
// matching unrotated pattern to the target value.
let immr = (size - left_rotations) & (size - 1);

// imms is encoded as the size of the pattern, a 0, and then one less
// than the number of sequential 1s.
let imms = (!(size - 1) << 1) | (trailing_ones - 1);

// n is 1 if the element size is 64-bits, and 0 otherwise.
let n = ((imms >> 6) & 1) ^ 1;

Ok(BitmaskImmediate {
    n: n as u8,
    imms: (imms & 0x3f) as u8,
    immr: (immr & 0x3f) as u8
})
```

That's it! We have successfully encoded a bitmask immediate for an unsigned integer.

## Testing our encoding

We can now write a couple of tests to verify the code is behaving as we expect. Writing a full test suite for this is outside the scope of this post, but below are a couple of the tests that made sense to write.

```rust
#[test]
fn test_size_16_minimum() {
    let bitmask = BitmaskImmediate::try_from(0x0001000100010001);
    assert!(matches!(bitmask, Ok(BitmaskImmediate { n: 0, immr: 0b000000, imms: 0b100000 })));
}

#[test]
fn test_size_16_rotated() {
    let bitmask = BitmaskImmediate::try_from(0xff8fff8fff8fff8f);
    assert!(matches!(bitmask, Ok(BitmaskImmediate { n: 0, immr: 0b001001, imms: 0b101100 })));
}

#[test]
fn test_size_16_maximum() {
    let bitmask = BitmaskImmediate::try_from(0xfffefffefffefffe);
    assert!(matches!(bitmask, Ok(BitmaskImmediate { n: 0, immr: 0b001111, imms: 0b101110 })));
}
```

These tests exercise the minimum and maximum values encodeable into a 16-bit pattern. Additionally it tests a random 16-bit pattern that has been rotated.

## Putting it all together

Now that we have this code available to us, we can actually use a more efficient version of the `mov` instruction that supports encoding bitmask immediates. Since we were trying to move `0xC3FFFFFFC3FFFFFF` into `X0`, we can actually directly do:

```
mov X0, 0xC3FFFFFFC3FFFFFF
```

([Compiler Explorer](https://godbolt.org/z/d1x3nsKqE)). We can do this because `0xC3FFFFFFC3FFFFFF` can be directly encoded into a bitmask immediate. Its binary representation is:

```
1100001111111111111111111111111111000011111111111111111111111111
```

This is actually the following 32-bit pattern rotated twice to the right:

```
00000011111111111111111111111111
```

The components of our bitmask immediate will then be:

* `N` = 0 since it's not a 64-bit pattern
* `imms` = `011011` to indicate a 32-bit pattern with 28 ones
* `immr` = `000010` to indicate 2 right rotations of the pattern

Which means that the overall instruction is encoded as:

```
B2 02 6F E0
```

Where before we had 16 bytes, we now only have 4! This is quite a reduction in size, and will result in a smaller binary size in the end.

In YJIT we lower every one of our intermediate representation instructions that load a value into a series of `mov` instructions. If `try_into()` results in an `Ok`, we use that representation first, since it's the most compact. Otherwise we fall back to the first approach we described with `movz`/`movk` instructions.

## Wrapping up

I hope someone finds this helpful. I don't imagine it's all that common place to write your own AArch64 encoder, let alone encode bitmask immediates. But for that one person that reads this and needs this information, I hope it's helpful to you! If you're looking for a reference, you can find the source code related to this post [here](https://github.com/Shopify/ruby/blob/73f567b0c1635a36c2f77da182108010dcd0d29d/yjit/src/asm/arm64/arg/bitmask_imm.rs).
