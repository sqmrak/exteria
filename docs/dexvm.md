# dex runtime

`python/shim/dexvm` runs the classes of a dex file inside the app, with cpython 3.11 and no jvm. a method is translated into a python function on its first call, the java and android classes it names are python classes. the design follows the onegram analysis in `~/dev/java` (`TZ.md`, `README.md`).

## use

```python
import dexvm
loader = dexvm.load(data)                  # one dex file, a zip with classes.dex and classesN.dex, or bytes of either
klass = loader.load_class("Name")
klass.call_static("run")                   # natural python values in and out
obj = klass.new_instance(1, 2)
```

plugins reach it through `dalvik.system` (`DexClassLoader`, `InMemoryDexClassLoader`, `PathClassLoader`, `DelegateLastClassLoader`, `DexFile`) and `Class.forName`.

## what runs

- every dalvik instruction of dex versions 035 to 040, `invoke-polymorphic` and `invoke-custom` included. a method the translator refuses fails with `VerifyError` naming the instruction
- `invoke-custom`: `LambdaMetafactory.metafactory` and `altMetafactory`, `StringConcatFactory.makeConcat` and `makeConcatWithConstants`, and any bootstrap method of the program or the runtime. a lambda is an instance of a class made for its call site (`jindy.LambdaClass`) that converts between the erased interface types and the types of its implementation. the site is linked once, on its first execution
- java arithmetic (int and long wrap, float and double text as java prints it), arrays, exceptions with try tables, monitors, threads, class initialisation, reflection, proxies
- java classes by name: `python/shim/dexvm/index.py` lists them (about 860). a class that is named but missing fails at the instruction that names it with `NoClassDefFoundError`. a name in `android.*`, `androidx.*`, `org.telegram.*`, `de.robv.*` or `app.exteraless.*` is taken from the python shims of the app when they have it
- the output of the fixtures in `tests/fixtures/dex` equals what a jvm prints for the same sources (`tests/fixtures/dex/expected`)

## limits

a call from python gets the budget set with `dexvm.limits.configure(seconds, steps, elements)`; `exteria_host` sets 20 s. `with dexvm.limits.budget(seconds=1): ...` sets one for a block, and a nested one can only be narrower.

- translated code checks the budget on entry to every method that makes a call and before every jump back; the native machine does it between runs of 65536 jumps
- an exhausted budget raises `BudgetExceeded`, a `BaseException`: a `catch (Throwable)` of the program does not catch it. a thread the program starts spends the budget of its starter, and the starter's call raises when it returns
- `elements` counts the elements of arrays allocated under the budget, and one array over `limits.MAX_ARRAY_LENGTH` (64 M elements) is an `OutOfMemoryError`
- this bounds a loop. it is not a sandbox: a call blocked in c or in a lock never reaches a check, and the code has the rights of the app. `policy.FILE_ROOTS` restricts the files `java.io` opens, and is off by default
- input limits: 64 MiB per dex, 256 MiB per container, 4096 zip entries, 100 dex files

## cache

`dexvm.cache.configure(folder)` keeps the compiled code of each translated method, keyed by the sha-256 of the dex, the method, a digest of the translator and the python version. the app uses `Library/Caches/exteria-dex-methods`. 64 MiB in all, 2 MiB an entry, oldest first. an entry is written under a temporary name and renamed; a damaged one is dropped. the answers the translator got about the classes around a method are stored and asked again on every load. `cache.current().stats` counts hits, misses, stores and failures. entries are read with `marshal`, so the folder must be the app's own

## native machine

`core/dexnative` is a register machine for static methods that are pure integer code: int, long, boolean, byte, short and char arguments, arithmetic, shifts, comparisons, jumps, no calls, fields, arrays or try blocks. `dexvm/native.py` turns such a method into a program and `_exteria_dexnative` (`core/pyhost/exteria_dexnative_module.c`) runs it. any other method takes the python path. results equal the python translation; division by zero is the same `ArithmeticException`. on the host a loop of this kind runs 15 to 20 times faster

`native.plan` says why a method does not qualify. where the module is missing, nothing changes except speed.

## api added after the first pass

checked against a jvm by `tests/fixtures/dex/src/{Streams,Api2,Api3,Api4,Certs}.java`:

- streams are lazy: elements go through the pipeline one at a time, `limit` and the matching operations stop early, `Stream.iterate` and `generate` need no bound, `mapMulti`, `flatMapToInt` and friends exist; `String.chars` and `codePoints`; the summary statistics classes are the jdk ones
- `Spliterator`, `Spliterators` (with `AbstractSpliterator`), `StreamSupport.stream`, and `spliterator()` on every `Iterable` and `Collection`
- `Scanner` over a string, file, stream or reader: tokens, lines, `nextInt` and the rest with radix and the english digit groups, `useDelimiter`, `findInLine`, `skip`, `tokens`, the `InputMismatchException` messages of the jdk
- regular expressions: `\p{L}`, `\p{Lu}`, `\p{javaWhitespace}`, `\p{IsAlphabetic}` and the other unicode categories and java character classes (basic plane, as strings here are utf-16 units); the posix classes stay ASCII, as in java
- `java.util.concurrent`: `AbstractExecutorService`, `ExecutorCompletionService`, `DelayQueue`, `Exchanger`, `Phaser`, `LinkedTransferQueue`, `Atomic{Integer,Long,Reference}FieldUpdater` on the fields of dex classes
- `SimpleTimeZone` with daylight saving rules (wall, standard and utc time modes), `MonthDay`, `ValueRange`, `ChronoField.range()`, the `ChronoField` and `ChronoUnit` names as java prints them
- `java.lang.annotation` (`ElementType`, `RetentionPolicy` and the annotation types), `dalvik.annotation.*`, `InheritableThreadLocal`, `AbstractSequentialList`, `FormattableFlags`
- permissions (`BasicPermission` and its subclasses, `AllPermission`, `FilePermission`, `PropertyPermission`, `Permissions`), the elliptic curve, PSS, MGF1 and RSA-CRT key specs, `NamedParameterSpec`, `Destroyable`, `SNIHostName` and `SNIMatcher`, `ServerSocketFactory`
- `X509Certificate` from DER or PEM through `CertificateFactory` (names, validity, serial, extensions, alternative names, RSA and EC keys, `verify` of RSA signatures), `X500Principal` with the three name formats, and an in-memory `KeyStore`

## known differences and gaps

- the jvm and android print `/ by zero` and `divide by zero` for an `ArithmeticException`; the runtime prints the android text
- dates (`Calendar`, `SimpleDateFormat`) know english names only
- `Stream.count()` skips the pipeline when the size is known (list, array or range source through map, peek, sorted, skip, limit), as the jdk does
- `X509Certificate.toString()` follows the jdk layout and matches it for RSA/EC keys and the basic constraints, key identifier extensions; other extensions are dumped as DER; dates print the zone as the date shim does. `verify` handles RSA PKCS#1 v1.5, RSASSA-PSS and ECDSA (P-256, P-384, P-521); no certification paths, no revocation lists
- `KeyStore.load(stream)` and `store(stream)` refuse: PKCS#12, JKS and BKS files need password based encryption this runtime does not have. `KeyStore.getDefaultType()` answers `BKS`, as android does
- `SimpleTimeZone` ignores `setStartYear`
- android classes outside `python/shim/android` do not exist; there is no binder, no google services, no android `.so`
- `Cipher` and `Signature` are python and suit small data
- the native machine is compiled for armv7 (ios 5) and arm64 and linked into the app, but its tests ran on the host only
- nothing of the dex runtime has run on a phone

## tests

```
cd tests
python3.11 -I -m unittest discover -s python -p 'test_dexvm*.py'     # needs a c compiler for the native tests, they skip without one
make ../build/host/test_dexnative && ../build/host/test_dexnative     # the machine, in c
scripts/build_dex_fixtures.sh                                         # after changing a fixture source; needs javac/java 24+, d8
```

`test_dexvm.py` checks the fixtures against the jvm output, `test_dexvm_native.py` runs random methods through both paths and compares every result and exception, `test_dexvm_limits.py` covers the budget and the cache.
