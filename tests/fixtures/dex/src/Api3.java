import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;
import java.time.*;
import java.time.temporal.*;

/** executors, queues, synchronizers, field updaters, SimpleTimeZone, MonthDay and ValueRange */
public class Api3 {
    static StringBuilder out;
    static void p(String name, Object v) { out.append(name).append('=').append(v).append('\n'); }

    static class Direct extends AbstractExecutorService {
        boolean down;
        public void execute(Runnable r) { r.run(); }
        public void shutdown() { down = true; }
        public List<Runnable> shutdownNow() { down = true; return new ArrayList<>(); }
        public boolean isShutdown() { return down; }
        public boolean isTerminated() { return down; }
        public boolean awaitTermination(long t, TimeUnit u) { return down; }
    }

    static class Later implements Delayed {
        final String name; final long at;
        Later(String name, long inMillis) { this.name = name; this.at = System.nanoTime() + inMillis * 1000000L; }
        public long getDelay(TimeUnit unit) { return unit.convert(at - System.nanoTime(), TimeUnit.NANOSECONDS); }
        public int compareTo(Delayed o) { return Long.compare(at, ((Later) o).at); }
        public String toString() { return name; }
    }

    static class Counter {
        volatile int count;
        volatile long total;
        volatile String label = "start";
    }

    static class Steps extends Phaser {
        final int last;
        Steps(int parties, int last) { super(parties); this.last = last; }
        protected boolean onAdvance(int phase, int parties) { return phase >= last || parties == 0; }
    }

    static long at(int y, int mo, int d, int h) { return LocalDateTime.of(y, mo, d, h, 0).toInstant(ZoneOffset.UTC).toEpochMilli(); }

    public static String run() throws Exception {
        out = new StringBuilder();

        Direct ex = new Direct();
        Future<Integer> f = ex.submit(() -> 6 * 7);
        p("submit callable", f.get() + "," + f.isDone());
        final int[] ran = {0};
        Future<String> g = ex.submit(() -> { ran[0]++; }, "result");
        p("submit runnable", g.get() + "," + ran[0]);
        List<Callable<Integer>> jobs = Arrays.asList(() -> 1, () -> 2, () -> { throw new IllegalStateException("bad"); });
        StringBuilder sb = new StringBuilder();
        for (Future<Integer> each : ex.invokeAll(jobs)) {
            try { sb.append(each.get()); } catch (ExecutionException e) { sb.append('!').append(e.getCause().getMessage()); }
        }
        p("invokeAll", sb);
        p("invokeAny", ex.invokeAny(Arrays.asList(() -> { throw new RuntimeException("no"); }, () -> 99)));

        ExecutorCompletionService<String> cs = new ExecutorCompletionService<>(ex);
        cs.submit(() -> "one");
        cs.submit(() -> { throw new RuntimeException("two failed"); });
        cs.submit(() -> { }, "three");
        sb.setLength(0);
        for (int i = 0; i < 3; i++) {
            try { sb.append(cs.take().get()); } catch (ExecutionException e) { sb.append("<").append(e.getCause().getMessage()).append(">"); }
            sb.append(';');
        }
        p("completion", sb + " " + (cs.poll() == null));

        DelayQueue<Later> dq = new DelayQueue<>();
        dq.add(new Later("late", 400));
        dq.add(new Later("soon", 60));
        dq.add(new Later("past", -50));
        p("delay poll", dq.poll() + "," + dq.poll() + "," + dq.size() + "," + dq.peek());
        long started = System.nanoTime();
        Later got = dq.take();
        long waited = (System.nanoTime() - started) / 1000000L;
        p("delay take", got + "," + (waited >= 30 && waited < 300));
        p("delay timed poll", dq.poll(10, TimeUnit.MILLISECONDS) + "," + dq.poll(1, TimeUnit.SECONDS));

        Exchanger<String> exchanger = new Exchanger<>();
        final String[] swapped = new String[1];
        Thread other = new Thread(() -> { try { swapped[0] = exchanger.exchange("from other"); } catch (InterruptedException e) { } });
        other.start();
        String mine = exchanger.exchange("from main");
        other.join();
        p("exchanger", mine + "|" + swapped[0]);
        try { exchanger.exchange("alone", 20, TimeUnit.MILLISECONDS); } catch (TimeoutException e) { p("exchanger timeout", "te"); }

        final Steps phaser = new Steps(3, 2);
        final List<String> events = Collections.synchronizedList(new ArrayList<>());
        Thread[] workers = new Thread[3];
        for (int w = 0; w < 3; w++) {
            final int id = w;
            workers[w] = new Thread(() -> {
                while (!phaser.isTerminated()) {
                    int phase = phaser.getPhase();
                    events.add("w" + id + "@" + phase);
                    phaser.arriveAndAwaitAdvance();
                }
            });
            workers[w].start();
        }
        for (Thread w : workers) w.join();
        Collections.sort(events);
        p("phaser", events + " " + phaser.isTerminated() + " " + (phaser.getPhase() < 0));
        Phaser plain = new Phaser(1);
        p("phaser basic", plain.getPhase() + "," + plain.getRegisteredParties() + "," + plain.register() + "," + plain.getRegisteredParties()
            + "," + plain.arrive() + "," + plain.getArrivedParties() + "," + plain.getUnarrivedParties());
        plain.arriveAndDeregister();
        p("phaser dereg", plain.getPhase() + "," + plain.getRegisteredParties() + "," + plain.arriveAndDeregister());
        p("phaser end", plain.isTerminated());

        LinkedTransferQueue<String> ltq = new LinkedTransferQueue<>();
        p("tryTransfer none", ltq.tryTransfer("x") + "," + ltq.hasWaitingConsumer() + "," + ltq.size());
        final String[] taken = new String[1];
        Thread consumer = new Thread(() -> { try { taken[0] = ltq.take(); } catch (InterruptedException e) { } });
        consumer.start();
        for (int i = 0; i < 200 && !ltq.hasWaitingConsumer(); i++) Thread.sleep(5);
        p("waiting consumer", ltq.hasWaitingConsumer() + "," + ltq.getWaitingConsumerCount());
        ltq.transfer("handed over");
        consumer.join();
        p("transfer", taken[0] + "," + ltq.size());
        ltq.offer("queued");
        p("plain queue", ltq.size() + "," + ltq.poll() + "," + ltq.poll());

        Counter c = new Counter();
        AtomicIntegerFieldUpdater<Counter> iu = AtomicIntegerFieldUpdater.newUpdater(Counter.class, "count");
        AtomicLongFieldUpdater<Counter> lu = AtomicLongFieldUpdater.newUpdater(Counter.class, "total");
        AtomicReferenceFieldUpdater<Counter, String> ru = AtomicReferenceFieldUpdater.newUpdater(Counter.class, String.class, "label");
        p("int updater", iu.incrementAndGet(c) + "," + iu.getAndAdd(c, 10) + "," + iu.get(c) + "," + iu.compareAndSet(c, 11, 100) + ","
            + iu.compareAndSet(c, 11, 5) + "," + iu.addAndGet(c, Integer.MAX_VALUE) + "," + iu.updateAndGet(c, v -> v / 2));
        p("long updater", lu.addAndGet(c, 1L << 40) + "," + lu.getAndDecrement(c) + "," + lu.accumulateAndGet(c, 5, Math::max));
        p("ref updater", ru.get(c) + "," + ru.compareAndSet(c, "start", "next") + "," + ru.getAndSet(c, "last") + "," + c.label);
        try { AtomicIntegerFieldUpdater.newUpdater(Counter.class, "missing"); } catch (RuntimeException e) { p("no field", e.getCause().getClass().getSimpleName()); }

        SimpleTimeZone us = new SimpleTimeZone(-8 * 3600000, "PST8PDT", Calendar.APRIL, 1, -Calendar.SUNDAY, 2 * 3600000,
            Calendar.OCTOBER, -1, Calendar.SUNDAY, 2 * 3600000, 3600000);
        sb.setLength(0);
        for (long ms : new long[]{at(2024, 1, 15, 12), at(2024, 4, 6, 9), at(2024, 4, 7, 9), at(2024, 4, 7, 11), at(2024, 7, 1, 0),
                at(2024, 10, 26, 12), at(2024, 10, 27, 8), at(2024, 10, 27, 10), at(2024, 12, 25, 0), at(2025, 4, 6, 10)})
            sb.append(us.getOffset(ms) / 60000).append(us.inDaylightTime(new Date(ms)) ? "d " : "s ");
        p("us rules", sb + us.getID() + " " + us.getRawOffset() + " " + us.useDaylightTime() + " " + us.getDSTSavings());
        SimpleTimeZone au = new SimpleTimeZone(10 * 3600000, "AEST", Calendar.OCTOBER, 1, -Calendar.SUNDAY, 2 * 3600000,
            Calendar.APRIL, 1, -Calendar.SUNDAY, 3 * 3600000, 3600000);
        sb.setLength(0);
        for (long ms : new long[]{at(2024, 1, 15, 12), at(2024, 4, 6, 12), at(2024, 4, 6, 17), at(2024, 7, 1, 0), at(2024, 10, 5, 15),
                at(2024, 10, 5, 17), at(2024, 12, 25, 0)})
            sb.append(au.getOffset(ms) / 60000).append(au.inDaylightTime(new Date(ms)) ? "d " : "s ");
        p("southern rules", sb);
        SimpleTimeZone eu = new SimpleTimeZone(3600000, "CET", Calendar.MARCH, -1, Calendar.SUNDAY, 3600000, SimpleTimeZone.UTC_TIME,
            Calendar.OCTOBER, -1, Calendar.SUNDAY, 3600000, SimpleTimeZone.UTC_TIME, 3600000);
        sb.setLength(0);
        for (long ms : new long[]{at(2024, 3, 31, 0), at(2024, 3, 31, 2), at(2024, 10, 27, 0), at(2024, 10, 27, 2)})
            sb.append(eu.getOffset(ms) / 60000).append(' ');
        p("utc mode", sb);
        SimpleTimeZone fixed = new SimpleTimeZone(5 * 3600000 + 1800000, "IST-ish");
        p("fixed", fixed.getOffset(at(2024, 7, 1, 0)) + "," + fixed.useDaylightTime() + "," + fixed.inDaylightTime(new Date()) + "," + fixed.getDSTSavings()
            + "," + fixed.hasSameRules(new SimpleTimeZone(5 * 3600000 + 1800000, "other")));
        try { new SimpleTimeZone(0, "bad", 12, 1, 0, 0, 1, 1, 0, 0); } catch (IllegalArgumentException e) { p("bad month", e.getMessage()); }

        MonthDay md = MonthDay.of(2, 29);
        p("monthday", md + "," + md.isValidYear(2023) + "," + md.atYear(2023) + "," + md.atYear(2024) + "," + MonthDay.of(Month.DECEMBER, 3).getMonth()
            + "," + MonthDay.parse("--06-15").getDayOfMonth() + "," + md.compareTo(MonthDay.of(3, 1)) + "," + md.isBefore(MonthDay.of(3, 1)) + "," + md.equals(MonthDay.of(2, 29)));
        try { MonthDay.of(4, 31); } catch (DateTimeException e) { p("bad day", e.getMessage()); }
        try { MonthDay.of(13, 1); } catch (DateTimeException e) { p("bad month2", e.getMessage()); }
        ValueRange r = ValueRange.of(1, 28, 31);
        p("range", r + "," + r.isFixed() + "," + r.getMinimum() + "," + r.getSmallestMaximum() + "," + r.getMaximum() + "," + r.isValidValue(30) + "," + r.isIntValue()
            + "," + ValueRange.of(1, 7) + "," + ValueRange.of(0, 10).isFixed() + "," + ValueRange.of(-5, 5).equals(ValueRange.of(-5, 5)));
        try { ChronoField.DAY_OF_MONTH.range().checkValidValue(32, ChronoField.DAY_OF_MONTH); } catch (DateTimeException e) { p("check", e.getMessage()); }
        return out.toString();
    }
}
