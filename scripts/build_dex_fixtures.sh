#!/usr/bin/env bash
# builds the dex fixtures of tests/python/test_dexvm_*.py from tests/fixtures/dex/src with javac and d8, and records
# what a real jvm prints for the same classes (tests/fixtures/dex/expected). the dex files and the expected output are
# committed, so the tests need none of these tools; run this only after changing a source
#
# DEXVM_JAVAC, DEXVM_JAVA   javac and java of a jdk 24 or newer (java.lang.classfile writes the class of gen/)
# DEXVM_D8                  d8 of the android build-tools
# DEXVM_ANDROID_JAR         android.jar of a platform, the class path d8 desugars against
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixtures="$root/tests/fixtures/dex"
javac="${DEXVM_JAVAC:-javac}"
java="${DEXVM_JAVA:-java}"

for var in DEXVM_D8 DEXVM_ANDROID_JAR; do
  if [ -z "${!var:-}" ]; then
    echo "$var is not set" >&2
    exit 1
  fi
done
[ -x "$DEXVM_D8" ] || { echo "DEXVM_D8 is not executable: $DEXVM_D8" >&2; exit 1; }
[ -f "$DEXVM_ANDROID_JAR" ] || { echo "DEXVM_ANDROID_JAR is missing: $DEXVM_ANDROID_JAR" >&2; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/classes" "$work/oracle" "$work/dex" "$work/expected"

# inline string concatenation keeps the classes free of invokedynamic, which the translator refuses
# lib/ holds classes the fixtures link against and the dex files leave out, nooracle/ fixtures whose result depends on that
"$javac" -encoding UTF-8 --release 11 -XDstringConcat=inline -g:none -d "$work/classes" "$fixtures"/src/*.java "$fixtures"/lib/*.java "$fixtures"/nooracle/*.java
"$javac" -d "$work/oracle" "$fixtures/oracle/Oracle.java"

for source in "$fixtures"/src/*.java "$fixtures"/nooracle/*.java; do
  name="$(basename "$source" .java)"
  classes=("$work"/classes/"$name".class "$work"/classes/"$name"\$*.class)
  existing=()
  for file in "${classes[@]}"; do [ -f "$file" ] && existing+=("$file"); done
  mkdir -p "$work/out-$name"
  "$DEXVM_D8" --min-api 21 --lib "$DEXVM_ANDROID_JAR" --output "$work/out-$name" "${existing[@]}" >/dev/null
  cp "$work/out-$name/classes.dex" "$work/dex/$name.dex"
  if [ "$(dirname "$source")" = "$fixtures/src" ]; then
    "$java" -cp "$work/classes:$work/oracle" Oracle "$name" > "$work/expected/$name.txt"
    echo "$name: $(stat -c %s "$work/dex/$name.dex") bytes, $(wc -l < "$work/expected/$name.txt") lines"
  else
    echo "$name: $(stat -c %s "$work/dex/$name.dex") bytes, no oracle"
  fi
done
# indy/ keeps invokedynamic (lambdas, method references, string concatenation): d8 needs api 26, the first level that has
# invoke-custom, and --no-desugaring, or it turns the call sites into synthetic classes and the fixture tests nothing
mkdir -p "$work/indy-classes"
"$javac" -encoding UTF-8 --release 11 -g:none -d "$work/indy-classes" "$fixtures"/indy/*.java
for source in "$fixtures"/indy/*.java; do
  name="$(basename "$source" .java)"
  existing=("$work"/indy-classes/"$name".class "$work"/indy-classes/"$name"\$*.class)
  mkdir -p "$work/out-$name"
  "$DEXVM_D8" --min-api 26 --no-desugaring --lib "$DEXVM_ANDROID_JAR" --output "$work/out-$name" "${existing[@]}" >/dev/null
  cp "$work/out-$name/classes.dex" "$work/dex/$name.dex"
  "$java" -cp "$work/indy-classes:$work/oracle" Oracle "$name" > "$work/expected/$name.txt"
  echo "$name: $(stat -c %s "$work/dex/$name.dex") bytes, $(wc -l < "$work/expected/$name.txt") lines"
done
# gen/ holds bootstrap methods and the writer of a class that calls them: javac has no syntax for a call site with a
# bootstrap of the program, so CustomIndyGen writes that class with java.lang.classfile (a jdk 24 or newer)
mkdir -p "$work/gen-classes" "$work/gen-writer"
"$javac" -encoding UTF-8 --release 11 -g:none -d "$work/gen-classes" "$fixtures"/gen/Bootstraps.java
"$javac" -d "$work/gen-writer" "$fixtures/gen/CustomIndyGen.java"
"$java" -cp "$work/gen-writer" CustomIndyGen "$work/gen-classes"
mkdir -p "$work/out-CustomIndy"
"$DEXVM_D8" --min-api 26 --no-desugaring --lib "$DEXVM_ANDROID_JAR" --output "$work/out-CustomIndy" "$work"/gen-classes/*.class >/dev/null
cp "$work/out-CustomIndy/classes.dex" "$work/dex/CustomIndy.dex"
"$java" -cp "$work/gen-classes:$work/oracle" Oracle CustomIndy > "$work/expected/CustomIndy.txt"
echo "CustomIndy: $(stat -c %s "$work/dex/CustomIndy.dex") bytes, $(wc -l < "$work/expected/CustomIndy.txt") lines"
mkdir -p "$fixtures/expected"
cp "$work"/dex/*.dex "$fixtures/"
cp "$work"/expected/*.txt "$fixtures/expected/"
