## coerce

https://stackoverflow.com/questions/2799571/in-ruby-how-does-coerce-actually-work

## to_a

### Methods

Kernel.Array
Queue#initialize

### Syntax

splatting
massign

## to_ary

### Methods

Array#<=>
Array#concat
Array#[]=
Array#==
Array#flatten
Array#flatten!
Array.initialize
Array.new
Array#+
Array#product
Array#to_h
Array#transpose
Array.try_convert
Array#zip
Array#difference
Array#-
Array#&
Array#intersection
Array#join
Array#replace
Array#union
Enumerable#to_h
Enumerable#zip
Enumerable#collect_concat
Enumerabe#flat_map
Hash.[]
Hash#to_h
IO#puts
Kernel.Array
Proc#call
Proc#===
Proc#yield
Process.exec
Process.spawn
String#%
Struct#to_h

### Syntax

blocks/yielding
destructuring
massign

## to_hash

### Methods

Hash.[]
Hash#merge
Hash.try_convert
Hash#replace
Hash#update
Kernel.Hash
Process.spawn

### Syntax

double splat

## to_s

### Methods

Array#pack
Array#inspect
Array#to_s
Exception#to_s
Hash#to_s
IO#print
IO#puts
IO#binwrite
IO#write
IO#syswrite
IO#write_nonblock
Kernel#String
Kernel#warn
File#printf
Kernel.sprintf
String#gsub
String#%
String#sub

### Syntax

interpolation

## to_str

### Methods

Array#join
Array#*
Array#pack
Binding#local_variable_defined?
Binding#local_variable_set
Dir.chdir
Encoding.default_external=
Encoding.default_internal=
Encoding.Converter.asciicompat_encoding
Encoding.Converter.new
ENV.assoc
ENV.[]
ENV.rassoc
ENV.[]=
ENV.store
File.chmod
File.join
File.new
File.split
File#path
File#to_path
File#delete
File#unlink
IO#gets
IO.pipe
IO.popen
IO.printf
IO#read
IO#readlines
IO#set_encoding
IO#sysread
IO#ungetbyte
IO#ungetc
IO#each_line
IO#each
IO.new
IO.for_fd
IO.open
IO.foreach
IO.readlines
Kernel.`
Kernel#gsub
Kernel#instance_variable_get
Kernel#open
Kernel#remove_instance_variable
Kernel#require_relative
Kernel#require
Module#alias_method
Module#attr_accessor
Module#attr_reader
Module#attr
Module#attr_writer
Module#class_variable_defined?
Module#class_variable_get
Module#class_variable_set
Module#const_defined?
Module#const_get
Module#const_set
Module#const_source_location
Module#method_defined?
Module#module_function
Module#protected_method_defined?
Module#remove_const
Module#class_eval
Module#module_eval
Process.getrlimit
Process.setrlimit
Process.spawn
Regexp.union
String#casecmp
String#center
String#chomp
String#<=>
String#count
String#crypt
String#delete_prefix
String#delete
String#delete_suffix
String#[]=
String#force_encoding
String#include?
String#index
String#insert
String#ljust
String#%
String#partition
String#+
String#prepend
String#rjust
String#rpartition
String#scan
String#split
String#squeeze
String#sub
String#tr_s
String#tr
String.try_convert
String#concat
String#<<
String#each_line
String#lines
String#encode
String#encode!
String#===
String#==
String#initialize
String#replace
String#unpack
Thread#name=
Time#getlocal
Time#localtime
Time.new
Time.gm
Time.local
Time.mktime

## to_sym

### Methods

Tracepoint.new

## to_proc

### Methods

Hash#default_proc=

### Syntax

passing block arguments

## to_io

### Methods

IO#reopen
IO.select
IO.try_convert
File.directory?
FileTest.directory?
File.size?
File.size

## to_f

### Methods

Complex#to_f
Integer#coerce
Kernel#Float
Kernel.Float
File#printf
Kernel.sprintf
Math.cos
Numeric#ceil
Numeric#coerce
Numeric#fdiv
Numeric#floor
Numeric#round
Numeric#truncate
String#%

## to_c

### Methods

Kernel.Complex

## to_r

### Methods

Complex#to_r
Numeric#denominator
Numeric#numerator
Numeric#quo
Time.at
Time#getlocal
Time#localtime
Time#-
Time#new
Time#+

## to_regexp

### Methods

Regexp.try_convert
Regexp.union

## to_i

### Methods

Complex#to_i
Kernel.Integer
Kernel#Integer
File#printf
Kernel.sprintf
Numeric#to_int
String#%

## to_int

### Methods

Array#at
Array#cycle
Array#delete_at
Array#drop
Array#[]=
Array#fetch
Array#fill
Array#first
Array#flatten
Array#hash
Array#initialize
Array#insert
Array#last
Array#*
Array.new
Array#pop
Array#rotate
Array#sample
Array#shift
Array#shuffle
Array#pack
Array#slice
Array#[]
Encoding::Converter#primitive_convert
Enumerable#cycle
Enumerable#drop
Enumerable#each_cons
Enumerable#each_slice
Enumerable#first
Enumerable#take
Enumerable#with_index
File#chmod
File.umask
File.fnmatch
File.fnmatch?
Integer#allbits?
Integer#anybits?
Integer#[]
Integer#<<
Integer#-
Integer#*
Integer#nobits?
Integer#+
Integer#>>
Integer#round
IO#gets
IO#initialize
IO#lineno=
IO.new
IO.for_fd
IO.open
IO#pos
IO#tell
IO.foreach
IO.readlines
Kernel.Integer
Kernel#Integer
Kernel.rand
Kernel.srand
File#printf
Kernel.sprintf
MatchData#begin
MatchData#end
Process.getrlimit
Process.setrlimit
Random.rand
Random#seed
Range#first
Range#last
Range#step
Regexp.last_match
String#center
String#[]=
String#index
String#insert
String#ljust
String#%
String#rindex
String#rjust
String#setbyte
String#slice
String#split
String#sum
String#to_i
String#byteslice
String#[]
Time.at
Time#getlocal
Time#localtime
Time.new
Time.gm
Time.local
Time.mktime
Time.new
Time.utc
IO#putc
Kernel.putc
Kernel#putc
Kernel.exit
Kernel#exit
Kernel.exit!
Kernel#exit!
String#*

### Syntax

setting $.

## to_path

### Methods

Dir.chdir
Dir.children
Dir.chroot
Dir.each_child
Dir.[]
Dir.entries
Dir.foreach
Dir.glob
Dir#initialize
Dir.mkdir
File.ftype
File.join
File.mkfifo
File.new
File#path
File.realpath
File#to_path
File::Stat#initialize
IO.copy_stream
IO.read
IO#reopen
IO#sysopen
IO.foreach
IO.readlines
Kernel#autoload
Kernel#open
Kernel#require_relative
Kernel#test
Kernel#require
Module#autoload
Process.spawn

## to_enum

### Methods

Enumerable#zip

## to_open

### Methods

Kernel#open

## deconstruct

### Syntax

array pattern
find pattern

## deconstruct_keys

### Syntax

hash pattern
