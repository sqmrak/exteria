public class Sync {
    static StringBuilder out;
    static int shared;
    static final Object lock = new Object();
    static int blockShared;
    int inst;

    static void p(String name, Object v) {
        out.append(name).append('=').append(v).append('\n');
    }

    static synchronized void incStatic() { shared++; }
    synchronized void incInst() { inst++; }
    synchronized int nested() { return inner() + 1; }
    synchronized int inner() { return 41; }

    static class Worker extends Thread {
        final Sync target;
        final int n;
        Worker(Sync target, int n) { this.target = target; this.n = n; }
        public void run() {
            for (int i = 0; i < n; i++) {
                incStatic();
                target.incInst();
                synchronized (lock) { blockShared++; }
            }
        }
    }

    static class Box {
        int value;
        boolean full;
        synchronized void put(int v) throws InterruptedException {
            while (full) wait();
            value = v;
            full = true;
            notifyAll();
        }
        synchronized int take() throws InterruptedException {
            while (!full) wait();
            full = false;
            notifyAll();
            return value;
        }
    }

    public static String run() throws Exception {
        out = new StringBuilder();
        Sync s = new Sync();
        Worker[] ws = new Worker[4];
        for (int i = 0; i < ws.length; i++) { ws[i] = new Worker(s, 500); ws[i].start(); }
        for (Worker w : ws) w.join();
        p("counts", shared + "," + s.inst + "," + blockShared);
        p("reentrant", s.nested());
        final Box box = new Box();
        final StringBuilder got = new StringBuilder();
        Thread consumer = new Thread(new Runnable() {
            public void run() {
                try {
                    for (int i = 0; i < 20; i++) got.append(box.take()).append(',');
                } catch (InterruptedException e) { got.append("interrupted"); }
            }
        });
        consumer.start();
        for (int i = 0; i < 20; i++) box.put(i * i);
        consumer.join();
        p("pingpong", got);
        String ims;
        try { lock.notify(); ims = "no"; } catch (IllegalMonitorStateException e) { ims = "imse"; }
        p("imse", ims);
        try { lock.wait(); ims = "no"; } catch (IllegalMonitorStateException e) { ims = "imse"; }
        p("imse2", ims);
        synchronized (lock) { lock.notifyAll(); ims = "ok"; }
        p("held", ims);
        Thread named = new Thread(new Runnable() { public void run() { } }, "worker-x");
        p("name", named.getName() + "," + named.isAlive());
        named.start();
        named.join();
        p("done", named.isAlive());
        Thread t = new Thread() { public void run() { throw new IllegalStateException("boom"); } };
        t.setName("thrower");
        t.start();
        t.join();
        p("thrown", "joined");
        p("main", Thread.currentThread().getName());
        long start = System.currentTimeMillis();
        Thread.sleep(30);
        p("slept", System.currentTimeMillis() - start >= 25);
        return out.toString();
    }
}
