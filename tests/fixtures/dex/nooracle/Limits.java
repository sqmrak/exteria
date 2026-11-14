/** code that does not stop by itself, for the tests of the execution budget */
public class Limits {
    static int sink;

    public static int spin() {
        int i = 0;
        while (true) {
            i++;
            sink = i;
        }
    }

    public static int fib(int n) {
        return n < 2 ? n : fib(n - 1) + fib(n - 2);
    }

    public static int recurse(int n) {
        return recurse(n + 1) + 1;
    }

    public static int finite(int n) {
        int sum = 0;
        for (int i = 0; i < n; i++) sum += i;
        return sum;
    }

    public static int[] allocate(int n) {
        return new int[n];
    }

    public static int swallow() {
        try {
            spin();
        } catch (Throwable t) {
            return 1;
        }
        return 0;
    }

    public static int swallowFinally() {
        try {
            spin();
        } finally {
            sink = -1;
        }
        return 0;
    }

    public static int spinInThread() throws Exception {
        Thread t = new Thread(new Runnable() {
            public void run() { spin(); }
        });
        t.start();
        t.join();
        return 7;
    }
}
