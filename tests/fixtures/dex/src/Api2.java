import java.io.*;
import java.lang.annotation.*;
import java.util.*;
import java.util.function.*;
import java.util.stream.*;

/** classes the runtime gained late: Spliterator, Scanner, AbstractSequentialList, the annotation enums, InheritableThreadLocal */
public class Api2 {
    static StringBuilder out;
    static void p(String name, Object v) { out.append(name).append('=').append(v).append('\n'); }

    static class Countdown implements Iterable<Integer> {
        final int n;
        Countdown(int n) { this.n = n; }
        public Iterator<Integer> iterator() {
            return new Iterator<Integer>() {
                int i = n;
                public boolean hasNext() { return i > 0; }
                public Integer next() { return i--; }
            };
        }
    }

    static class Evens extends Spliterators.AbstractSpliterator<Integer> {
        int next = 0;
        final int limit;
        Evens(int limit) { super(Long.MAX_VALUE, Spliterator.ORDERED); this.limit = limit; }
        public boolean tryAdvance(Consumer<? super Integer> action) {
            if (next >= limit) return false;
            action.accept(next);
            next += 2;
            return true;
        }
    }

    static class Chain extends AbstractSequentialList<String> {
        final LinkedList<String> inner = new LinkedList<>();
        public ListIterator<String> listIterator(int index) { return inner.listIterator(index); }
        public int size() { return inner.size(); }
    }

    public static String run() throws Exception {
        out = new StringBuilder();

        // spliterators
        Spliterator<Integer> sp = Arrays.asList(1, 2, 3, 4).spliterator();
        p("sized", sp.estimateSize() + "," + sp.hasCharacteristics(Spliterator.SIZED) + "," + sp.getExactSizeIfKnown());
        final StringBuilder sb = new StringBuilder();
        while (sp.tryAdvance(x -> sb.append(x).append(';'))) { }
        p("tryAdvance", sb);
        p("iterable stream", StreamSupport.stream(new Countdown(4).spliterator(), false).map(x -> x * x).collect(Collectors.toList()));
        p("unknown size", new Countdown(3).spliterator().getExactSizeIfKnown() + "," + (new Countdown(3).spliterator().estimateSize() == Long.MAX_VALUE));
        p("abstract spliterator", StreamSupport.stream(new Evens(10), false).collect(Collectors.toList()));
        p("limited infinite", StreamSupport.stream(new Evens(1000000), false).limit(3).collect(Collectors.toList()));
        Iterator<Integer> back = Spliterators.iterator(Arrays.asList(7, 8, 9).spliterator());
        sb.setLength(0);
        while (back.hasNext()) sb.append(back.next());
        p("spliterator iterator", sb);
        Spliterator<String> fromIterator = Spliterators.spliteratorUnknownSize(Arrays.asList("x", "y").iterator(), 0);
        sb.setLength(0);
        fromIterator.forEachRemaining(sb::append);
        p("forEachRemaining", sb);
        p("empty", Spliterators.emptySpliterator().tryAdvance(x -> { }));
        p("set stream", StreamSupport.stream(new TreeSet<>(Arrays.asList(3, 1, 2)).spliterator(), false).collect(Collectors.toList()));
        p("map stream", StreamSupport.stream(new TreeMap<>(Map.of("b", 2, "a", 1)).entrySet().spliterator(), false).map(e -> e.getKey() + e.getValue()).collect(Collectors.toList()));

        // Scanner
        Scanner sc = new Scanner("12 abc -7 3.5 true\n second line \nthird 0x1F 99999999999 1,234 +5");
        p("scan int", sc.hasNextInt() + "," + sc.nextInt());
        p("scan word", sc.hasNextInt() + "," + sc.hasNext() + "," + sc.next());
        p("scan neg", sc.nextInt());
        p("scan double", sc.hasNextDouble() + "," + sc.nextDouble());
        p("scan bool", sc.hasNextBoolean() + "," + sc.nextBoolean());
        p("scan rest of line", "[" + sc.nextLine() + "]");
        p("scan line", "[" + sc.nextLine() + "]");
        p("scan token", sc.next() + "," + sc.hasNextInt());
        try { sc.nextInt(); } catch (InputMismatchException e) { p("mismatch", e.getMessage()); }
        p("still there", sc.next());
        try { sc.nextInt(); } catch (InputMismatchException e) { p("out of range", e.getMessage()); }
        sc.next();
        p("grouped", sc.nextInt() + "," + sc.nextInt());
        p("hasNext end", sc.hasNext() + "," + sc.hasNextLine());
        try { sc.next(); } catch (NoSuchElementException e) { p("no more", e.getClass().getSimpleName()); }
        sc.close();
        try { sc.next(); } catch (IllegalStateException e) { p("closed", e.getMessage()); }

        Scanner csv = new Scanner("a,b;;c , d").useDelimiter("\\s*[,;]\\s*");
        sb.setLength(0);
        while (csv.hasNext()) sb.append('[').append(csv.next()).append(']');
        p("delimiter", sb);
        Scanner lines = new Scanner("one\r\ntwo\n\nfour");
        sb.setLength(0);
        while (lines.hasNextLine()) sb.append('<').append(lines.nextLine()).append('>');
        p("lines", sb);
        Scanner radix = new Scanner("ff 101 -z");
        p("radix", radix.nextInt(16) + "," + radix.useRadix(2).nextInt() + "," + radix.radix());
        Scanner stream = new Scanner(new ByteArrayInputStream("5 6\n7".getBytes("UTF-8")));
        int total = 0;
        while (stream.hasNextInt()) total += stream.nextInt();
        p("stream sum", total);
        Scanner find = new Scanner("name=value; other=thing");
        p("findInLine", find.findInLine("\\w+=") + "," + find.findInLine("(\\w+)") + "," + find.findInLine("zzz"));
        Scanner skip = new Scanner("   42 rest");
        skip.skip("\\s*");
        p("skip", skip.nextInt() + "," + skip.next());
        p("tokens", new Scanner("a b  c").tokens().collect(Collectors.toList()));
        p("next pattern", new Scanner("abc 123").next("[a-z]+") + "," + new Scanner("abc 123").hasNext("\\d+"));
        p("long", new Scanner("9223372036854775807 -9223372036854775808").nextLong());
        p("short byte", new Scanner("32767 127").nextShort() + "," + new Scanner("128").hasNextByte());
        p("empty", new Scanner("").hasNext() + "," + new Scanner("").hasNextLine() + "," + new Scanner("\n").hasNextLine());

        // AbstractSequentialList
        Chain chain = new Chain();
        chain.add("a"); chain.add("b"); chain.add(1, "x"); chain.add(0, "first");
        p("seq list", chain + " " + chain.get(2) + " " + chain.indexOf("b") + " " + chain.size());
        chain.set(1, "A"); chain.remove(0); chain.remove("x");
        p("seq list edit", chain + " " + chain.contains("b"));
        try { chain.get(5); } catch (IndexOutOfBoundsException e) { p("seq oob", "ioobe"); }

        // annotation enums
        p("element types", ElementType.METHOD + "," + ElementType.valueOf("FIELD").ordinal() + "," + ElementType.values().length);
        p("retention", Arrays.toString(RetentionPolicy.values()) + RetentionPolicy.RUNTIME.compareTo(RetentionPolicy.SOURCE));
        p("formattable flags", FormattableFlags.LEFT_JUSTIFY + "," + FormattableFlags.UPPERCASE + "," + FormattableFlags.ALTERNATE);

        // InheritableThreadLocal
        InheritableThreadLocal<String> inherited = new InheritableThreadLocal<String>() {
            protected String childValue(String parent) { return parent + "+child"; }
        };
        ThreadLocal<String> plain = new ThreadLocal<>();
        inherited.set("parent");
        plain.set("plain");
        final String[] seen = new String[2];
        Thread t = new Thread(() -> { seen[0] = inherited.get(); seen[1] = plain.get(); });
        t.start();
        t.join();
        p("inheritable", seen[0] + "," + seen[1]);
        return out.toString();
    }
}
