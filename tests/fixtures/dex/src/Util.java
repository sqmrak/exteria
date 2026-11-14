import java.math.*;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;
import java.util.zip.CRC32;

public class Util {
    static StringBuilder out;

    static void p(String name, Object v) {
        out.append(name).append('=').append(v).append('\n');
    }

    static class Pt implements Comparable<Pt> {
        final int x, y;
        Pt(int x, int y) { this.x = x; this.y = y; }
        public boolean equals(Object o) { return o instanceof Pt && ((Pt) o).x == x && ((Pt) o).y == y; }
        public int hashCode() { return 31 * x + y; }
        public int compareTo(Pt o) { return x != o.x ? Integer.compare(x, o.x) : Integer.compare(y, o.y); }
        public String toString() { return "(" + x + "," + y + ")"; }
    }

    static String hex(byte[] b) {
        StringBuilder s = new StringBuilder();
        for (byte x : b) s.append(String.format("%02x", x & 0xFF));
        return s.toString();
    }

    public static String run() throws Exception {
        out = new StringBuilder();
        List<Integer> list = new ArrayList<>();
        for (int i = 0; i < 10; i++) list.add(i * 3 % 7);
        p("list", list + "," + list.size() + "," + list.indexOf(5) + "," + list.contains(6) + "," + list.lastIndexOf(0));
        list.remove(Integer.valueOf(5));
        list.remove(0);
        list.add(2, 99);
        list.set(0, -1);
        p("list2", list + "," + list.subList(1, 4) + "," + list.get(3));
        Collections.sort(list);
        p("sorted", list + "," + Collections.max(list) + "," + Collections.min(list) + "," + Collections.binarySearch(list, 99));
        Collections.reverse(list);
        Collections.swap(list, 0, 1);
        p("reversed", list + "," + Collections.frequency(list, 3));
        list.sort(Comparator.reverseOrder());
        p("cmp", list + "," + new ArrayList<>(list).equals(list) + "," + list.hashCode());
        Iterator<Integer> it = list.iterator();
        while (it.hasNext()) if (it.next() % 2 == 0) it.remove();
        p("iterremove", list);
        String cme;
        try { for (Integer x : list) list.add(x); cme = "no"; } catch (ConcurrentModificationException e) { cme = "cme"; }
        String oob;
        try { list.get(100); oob = "no"; } catch (IndexOutOfBoundsException e) { oob = "ioobe"; }
        p("errors", cme + "," + oob);

        Map<String, Integer> map = new HashMap<>();
        String[] words = "the quick brown fox jumps over the lazy dog and then the fox runs away from a big dog".split(" ");
        for (String w : words) map.merge(w, 1, Integer::sum);
        p("hashmap", map);
        p("keyset", map.keySet() + "," + map.values());
        Set<String> hs = new HashSet<>(Arrays.asList(words));
        p("hashset", hs);
        Map<Integer, String> im = new HashMap<>();
        for (int i = 0; i < 40; i += 3) im.put(i * 37 % 101, "v" + i);
        p("intmap", im);
        Map<Integer, Integer> big = new HashMap<>();
        for (int i = 0; i < 200; i++) big.put(i * 7919 % 1009, i);
        StringBuilder bs = new StringBuilder();
        int n = 0;
        for (Map.Entry<Integer, Integer> e : big.entrySet()) { if (n++ < 12) bs.append(e.getKey()).append(':').append(e.getValue()).append(' '); }
        p("bigmap", bs.toString() + big.size());
        Map<Pt, String> pm = new HashMap<>();
        pm.put(new Pt(1, 2), "a"); pm.put(new Pt(1, 2), "b"); pm.put(new Pt(3, 4), "c"); pm.put(new Pt(0, 0), "d");
        p("objkeys", pm + "," + pm.get(new Pt(3, 4)) + "," + pm.containsKey(new Pt(9, 9)));
        Map<String, Integer> lhm = new LinkedHashMap<>(16, 0.75f, true);
        lhm.put("a", 1); lhm.put("b", 2); lhm.put("c", 3);
        lhm.get("a");
        lhm.put("d", 4);
        p("accessorder", lhm);
        Map<String, Integer> tm = new TreeMap<>(map);
        p("treemap", tm);
        TreeMap<Integer, String> nav = new TreeMap<>();
        for (int i = 10; i <= 50; i += 10) nav.put(i, "n" + i);
        p("nav", nav.floorKey(25) + "," + nav.ceilingKey(25) + "," + nav.lowerKey(10) + "," + nav.higherKey(50) + ","
            + nav.firstKey() + "," + nav.lastEntry() + "," + nav.headMap(30) + "," + nav.tailMap(30, false) + "," + nav.descendingMap());
        TreeSet<String> ts = new TreeSet<>(Arrays.asList(words));
        p("treeset", ts + "," + ts.first() + "," + ts.last() + "," + ts.headSet("fox") + "," + ts.ceiling("g"));
        Map<String, List<Integer>> multi = new TreeMap<>();
        for (int i = 0; i < 8; i++) multi.computeIfAbsent(i % 3 == 0 ? "fizz" : "other", k -> new ArrayList<>()).add(i);
        p("computeIfAbsent", multi);
        map.remove("the");
        map.replaceAll((k, v) -> v * 10);
        map.putIfAbsent("new", 5);
        p("mapops", map.getOrDefault("fox", -1) + "," + map.getOrDefault("zzz", -1) + "," + map.size() + "," + map.containsValue(10));

        Deque<Integer> dq = new ArrayDeque<>();
        dq.push(1); dq.addLast(2); dq.offerFirst(0); dq.add(3);
        p("deque", dq + "," + dq.peekFirst() + "," + dq.pollLast() + "," + dq.pop() + "," + dq);
        LinkedList<String> ll = new LinkedList<>(Arrays.asList("x", "y", "z"));
        ll.addFirst("w"); ll.removeLast(); ll.add(1, "m");
        p("linked", ll + "," + ll.getFirst() + "," + ll.indexOf("y"));
        PriorityQueue<Integer> pq = new PriorityQueue<>();
        for (int x : new int[]{5, 3, 8, 1, 9, 2, 7}) pq.add(x);
        StringBuilder pqs = new StringBuilder(pq.toString()).append(" -> ");
        while (!pq.isEmpty()) pqs.append(pq.poll()).append(' ');
        p("pq", pqs);
        PriorityQueue<String> pq2 = new PriorityQueue<>(Comparator.comparing(String::length).thenComparing(Comparator.naturalOrder()));
        pq2.addAll(Arrays.asList("ccc", "a", "bb", "aa", "b"));
        p("pq2", pq2.poll() + pq2.poll() + pq2.poll() + "," + pq2);
        Stack<Integer> st = new Stack<>();
        st.push(1); st.push(2); st.push(3);
        p("stack", st + "," + st.pop() + "," + st.peek() + "," + st.search(1));

        Random r = new Random(42);
        p("random", r.nextInt() + "," + r.nextInt(100) + "," + r.nextLong() + "," + r.nextDouble() + "," + r.nextBoolean() + "," + r.nextFloat() + "," + r.nextGaussian() + "," + r.nextInt(7) + "," + r.nextInt(1 << 20));
        byte[] rb = new byte[6];
        new Random(7).nextBytes(rb);
        p("randbytes", Arrays.toString(rb));
        List<Integer> sh = new ArrayList<>();
        for (int i = 0; i < 10; i++) sh.add(i);
        Collections.shuffle(sh, new Random(123));
        p("shuffle", sh);

        int[] ia = {5, 2, 9, 1, 7};
        Arrays.sort(ia);
        int[] copy = Arrays.copyOf(ia, 7);
        p("arrays", Arrays.toString(ia) + Arrays.toString(copy) + Arrays.toString(Arrays.copyOfRange(ia, 1, 3)) + Arrays.binarySearch(ia, 7)
            + Arrays.equals(ia, ia.clone()) + Arrays.hashCode(ia) + Arrays.asList(1, 2, 3) + Arrays.deepToString(new int[][]{{1}, {2, 3}}));
        String[] sa = {"pear", "Apple", "fig"};
        Arrays.sort(sa);
        Arrays.sort(sa, String.CASE_INSENSITIVE_ORDER);
        p("sortstr", Arrays.toString(sa));
        double[] da = {3.5, -1.0, 2.25};
        Arrays.sort(da);
        long[] la = new long[3];
        Arrays.fill(la, 7L);
        p("prim", Arrays.toString(da) + Arrays.toString(la));

        Optional<String> opt = Optional.of("v");
        p("optional", opt + "," + opt.map(String::toUpperCase).get() + "," + Optional.empty().isPresent() + "," + Optional.ofNullable(null).orElse("dflt")
            + "," + opt.filter(s -> s.length() > 3).isPresent());
        StringJoiner sj = new StringJoiner(", ", "{", "}");
        sj.add("a").add("b");
        p("joiner", sj + "," + new StringJoiner("-").toString().isEmpty() + "," + String.join("|", "x", "y", "z") + "," + String.join("/", Arrays.asList("p", "q")));
        p("objects", Objects.hash(1, "a", 2.5) + "," + Objects.equals(null, null) + "," + Objects.toString(null) + "," + Objects.hashCode("abc") + "," + Objects.requireNonNullElse(null, "e"));

        BigInteger bi = new BigInteger("123456789012345678901234567890");
        p("bigint", bi.multiply(bi) + "," + bi.mod(BigInteger.valueOf(97)) + "," + bi.pow(3).bitLength() + "," + BigInteger.valueOf(-17).divide(BigInteger.valueOf(5))
            + "," + BigInteger.valueOf(-17).remainder(BigInteger.valueOf(5)) + "," + BigInteger.valueOf(-17).mod(BigInteger.valueOf(5)) + "," + bi.hashCode()
            + "," + BigInteger.TEN.modPow(BigInteger.valueOf(20), BigInteger.valueOf(1000007)) + "," + new BigInteger("ff", 16) + "," + bi.toString(16)
            + "," + BigInteger.valueOf(97).isProbablePrime(10) + "," + bi.gcd(BigInteger.valueOf(30)));
        BigDecimal bd = new BigDecimal("123.456");
        p("bigdec", bd.add(new BigDecimal("0.544")) + "," + bd.multiply(new BigDecimal("2.5")) + "," + bd.setScale(1, RoundingMode.HALF_UP) + "," + bd.setScale(2, RoundingMode.DOWN)
            + "," + new BigDecimal("10").divide(new BigDecimal("4")) + "," + new BigDecimal("1").divide(new BigDecimal("3"), 5, RoundingMode.HALF_EVEN)
            + "," + bd.negate().setScale(0, RoundingMode.CEILING) + "," + new BigDecimal("2.50").stripTrailingZeros() + "," + bd.compareTo(new BigDecimal("123.4560"))
            + "," + bd.equals(new BigDecimal("123.4560")) + "," + new BigDecimal("1E+3").toPlainString() + "," + new BigDecimal(0.5) + "," + BigDecimal.valueOf(2.50));
        String ae;
        try { BigDecimal.ONE.divide(new BigDecimal(3)); ae = "no"; } catch (ArithmeticException e) { ae = "ae"; }
        p("bigdecerr", ae);

        MessageDigest md = MessageDigest.getInstance("SHA-256");
        p("sha256", hex(md.digest("hello".getBytes(StandardCharsets.UTF_8))));
        p("md5", hex(MessageDigest.getInstance("MD5").digest("hello".getBytes())));
        p("sha1", hex(MessageDigest.getInstance("SHA-1").digest(new byte[0])));
        p("base64", Base64.getEncoder().encodeToString("hello world!?".getBytes()) + "," + new String(Base64.getDecoder().decode("aGVsbG8=")) + ","
            + Base64.getUrlEncoder().withoutPadding().encodeToString(new byte[]{(byte) 0xfb, (byte) 0xff}) + "," + Base64.getEncoder().encodeToString(new byte[]{1}));
        CRC32 crc = new CRC32();
        crc.update("hello".getBytes());
        p("crc32", crc.getValue());
        p("uuid", UUID.nameUUIDFromBytes("x".getBytes()) + "," + UUID.fromString("123e4567-e89b-12d3-a456-426614174000").getMostSignificantBits());

        AtomicInteger ai = new AtomicInteger(5);
        AtomicLong al = new AtomicLong(Long.MAX_VALUE);
        p("atomic", ai.incrementAndGet() + "," + ai.getAndAdd(10) + "," + ai.compareAndSet(16, 1) + "," + ai.get() + "," + al.incrementAndGet()
            + "," + new AtomicBoolean(true).getAndSet(false) + "," + ai.updateAndGet(x -> x * 7) + "," + ai.accumulateAndGet(3, Integer::sum));
        ExecutorService ex = Executors.newFixedThreadPool(3);
        List<Future<Integer>> fs = new ArrayList<>();
        for (int i = 1; i <= 5; i++) { final int k = i; fs.add(ex.submit(() -> k * k)); }
        int total = 0;
        for (Future<Integer> f : fs) total += f.get();
        Future<?> bad = ex.submit(() -> { throw new IllegalStateException("task"); });
        String exec;
        try { bad.get(); exec = "no"; } catch (ExecutionException e) { exec = e.getCause().getMessage(); }
        ex.shutdown();
        p("executor", total + "," + exec + "," + ex.awaitTermination(5, TimeUnit.SECONDS) + "," + ex.isShutdown());
        CountDownLatch latch = new CountDownLatch(3);
        AtomicInteger hits = new AtomicInteger();
        for (int i = 0; i < 3; i++) new Thread(() -> { hits.incrementAndGet(); latch.countDown(); }).start();
        latch.await();
        p("latch", hits.get() + "," + latch.getCount());
        CompletableFuture<Integer> cf = CompletableFuture.supplyAsync(() -> 20).thenApply(x -> x + 1).thenApply(x -> x * 2);
        p("completable", cf.get() + "," + CompletableFuture.completedFuture("c").thenApply(String::toUpperCase).join());
        BlockingQueue<Integer> bq = new LinkedBlockingQueue<>();
        Thread prod = new Thread(() -> { for (int i = 0; i < 5; i++) bq.add(i * i); });
        prod.start();
        int sum = 0;
        for (int i = 0; i < 5; i++) sum += bq.take();
        p("blockingqueue", sum);
        p("timeunit", TimeUnit.SECONDS.toMillis(3) + "," + TimeUnit.MILLISECONDS.toSeconds(4500) + "," + TimeUnit.HOURS.convert(180, TimeUnit.MINUTES) + "," + TimeUnit.DAYS);
        ConcurrentHashMap<String, Integer> chm = new ConcurrentHashMap<>();
        chm.put("k", 1); chm.merge("k", 5, Integer::sum); chm.putIfAbsent("j", 2);
        p("chm", new TreeMap<>(chm));
        ThreadLocal<Integer> tl = ThreadLocal.withInitial(() -> 7);
        tl.set(tl.get() + 1);
        final int[] other = new int[1];
        Thread tt = new Thread(() -> other[0] = tl.get());
        tt.start(); tt.join();
        p("threadlocal", tl.get() + "," + other[0]);
        return out.toString();
    }
}
