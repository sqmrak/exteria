import java.util.*;
import java.util.function.*;
import java.util.stream.*;

/** the order in which a sequential stream runs its stages: the expected text is what a jvm printed */
public class Streams {
    static StringBuilder out;
    static void p(String name, Object v) { out.append(name).append('=').append(v).append('\n'); }

    public static String run() {
        out = new StringBuilder();
        StringBuilder log = new StringBuilder();
        List<Integer> r = Stream.of(1, 2, 3, 4)
            .peek(x -> log.append("a").append(x).append(' '))
            .map(x -> x * 10)
            .filter(x -> { log.append("f").append(x).append(' '); return x != 20; })
            .peek(x -> log.append("b").append(x).append(' '))
            .collect(Collectors.toList());
        p("interleaved", log + "| " + r);

        log.setLength(0);
        Optional<Integer> first = Stream.of(5, 6, 7).peek(x -> log.append("p").append(x).append(' ')).filter(x -> x > 5).findFirst();
        p("short circuit", log + "| " + first.get());

        log.setLength(0);
        boolean any = Stream.of(1, 2, 3, 4).peek(x -> log.append(x)).anyMatch(x -> x == 2);
        p("anyMatch", log + "|" + any);

        p("iterate limit", Stream.iterate(1, x -> x * 2).limit(10).collect(Collectors.toList()));
        p("iterate pred", Stream.iterate(1, x -> x < 200, x -> x * 3).collect(Collectors.toList()));
        int[] counter = {0};
        p("generate", Stream.generate(() -> counter[0]++).limit(5).map(String::valueOf).collect(Collectors.joining(",")));
        p("generate calls", counter[0]);
        p("intstream iterate", IntStream.iterate(1, x -> x + 2).limit(6).sum());
        p("takeWhile infinite", Stream.iterate(1, x -> x + 1).takeWhile(x -> x < 6).collect(Collectors.toList()));
        p("dropWhile", Stream.of(1, 2, 3, 1, 2).dropWhile(x -> x < 3).collect(Collectors.toList()));
        p("skip limit", IntStream.range(0, 1000000000).skip(5).limit(3).boxed().collect(Collectors.toList()));

        log.setLength(0);
        List<Integer> sorted = Stream.of(3, 1, 2).peek(x -> log.append("u").append(x).append(' ')).sorted()
            .peek(x -> log.append("s").append(x).append(' ')).collect(Collectors.toList());
        p("sorted barrier", log + "| " + sorted);

        log.setLength(0);
        List<Integer> flat = Stream.of(1, 2, 3).peek(x -> log.append("o").append(x).append(' '))
            .flatMap(x -> Stream.of(x, x * 100).peek(y -> log.append("i").append(y).append(' '))).limit(3).collect(Collectors.toList());
        p("flatMap limit", log + "| " + flat);

        log.setLength(0);
        List<Integer> dist = Stream.of(1, 2, 1, 3, 2).peek(x -> log.append(x)).distinct().collect(Collectors.toList());
        p("distinct", log + "|" + dist);

        p("concat", Stream.concat(Stream.of(1, 2), Stream.iterate(10, x -> x + 1)).limit(5).collect(Collectors.toList()));
        p("reduce", Stream.of(1, 2, 3, 4).reduce(Integer::sum).get() + "," + Stream.of(1, 2, 3).reduce(10, Integer::sum));
        p("min max", Stream.of(4, 2, 9).min(Integer::compare).get() + "," + Stream.of(4, 2, 9).max(Integer::compare).get()
            + "," + IntStream.of(4, 2, 9).min().getAsInt() + "," + IntStream.of(4, 2, 9).max().getAsInt()
            + "," + Stream.<Integer>empty().max(Integer::compare).isPresent());
        p("average", IntStream.of(1, 2, 4).average().getAsDouble() + "," + IntStream.empty().average().isPresent());
        p("count", Stream.of(1, 2, 3).filter(x -> x > 1).count());
        Iterator<Integer> it = Stream.iterate(0, x -> x + 5).iterator();
        p("iterator", it.next() + "," + it.next() + "," + it.next());
        p("boxed map", IntStream.rangeClosed(1, 5).mapToObj(i -> "n" + i).collect(Collectors.joining("|", "<", ">")));
        p("groupingBy", Stream.of("aa", "b", "cc", "d", "eee").collect(Collectors.groupingBy(String::length, TreeMap::new, Collectors.toList())));
        p("partition", Stream.of(1, 2, 3, 4, 5).collect(Collectors.partitioningBy(x -> x % 2 == 0)));
        p("toMap", Stream.of("a", "bb", "ccc").collect(Collectors.toMap(s -> s, String::length, (x, y) -> x, TreeMap::new)));
        p("summary", IntStream.of(3, 1, 2).summaryStatistics());
        try {
            Stream<Integer> s = Stream.of(1);
            s.count();
            s.count();
        } catch (IllegalStateException e) { p("reuse", "ise"); }
        p("flatMapToInt", Stream.of("ab", "c").flatMapToInt(String::chars).sum());
        p("double stream", DoubleStream.iterate(0.5, d -> d * 2).limit(4).boxed().collect(Collectors.toList()));
        p("long stream", LongStream.rangeClosed(1, 20).reduce(1L, (a, b) -> a * b));
        return out.toString();
    }
}
