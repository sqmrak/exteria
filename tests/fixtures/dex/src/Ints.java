/** pure integer static methods: the ones the native machine runs. the expected text is what a jvm prints */
public class Ints {
    static StringBuilder out;

    static void p(String name, Object v) {
        out.append(name).append('=').append(v).append('\n');
    }

    static int gcd(int a, int b) { while (b != 0) { int t = a % b; a = b; b = t; } return a; }
    static long gcdL(long a, long b) { while (b != 0) { long t = a % b; a = b; b = t; } return a; }
    static int collatz(int n) { int steps = 0; while (n != 1) { n = (n & 1) == 0 ? n / 2 : 3 * n + 1; steps++; } return steps; }
    static int popcount(int v) { int c = 0; while (v != 0) { v &= v - 1; c++; } return c; }
    static int popcountL(long v) { int c = 0; while (v != 0) { v &= v - 1; c++; } return c; }
    static int fnv(int rounds) { int h = 0x811c9dc5; for (int i = 0; i < rounds; i++) { h ^= i & 0xff; h *= 16777619; } return h; }
    static long fnvL(int rounds) { long h = 0xcbf29ce484222325L; for (int i = 0; i < rounds; i++) { h ^= i & 0xff; h *= 0x100000001b3L; } return h; }
    static int rotl(int v, int n) { return (v << n) | (v >>> (32 - n)); }
    static long rotlL(long v, int n) { return (v << n) | (v >>> (64 - n)); }
    static int xorshift(int seed, int rounds) { int x = seed; for (int i = 0; i < rounds; i++) { x ^= x << 13; x ^= x >>> 17; x ^= x << 5; } return x; }
    static long xorshiftL(long seed, int rounds) { long x = seed; for (int i = 0; i < rounds; i++) { x ^= x << 13; x ^= x >>> 7; x ^= x << 17; } return x; }
    static int isqrt(int n) { int lo = 0, hi = 46341; while (lo < hi) { int mid = (lo + hi + 1) >>> 1; if (mid * mid <= n) lo = mid; else hi = mid - 1; } return lo; }
    static long powmod(long b, long e, long m) { long r = 1; b %= m; while (e > 0) { if ((e & 1) == 1) r = r * b % m; b = b * b % m; e >>= 1; } return r; }
    static boolean isPrime(int n) { if (n < 2) return false; for (int i = 2; (long) i * i <= n; i++) if (n % i == 0) return false; return true; }
    static int primes(int limit) { int c = 0; for (int i = 0; i < limit; i++) if (isPrime(i)) c++; return c; }
    static int crc(int seed, int rounds) {
        int crc = ~seed;
        for (int i = 0; i < rounds; i++) {
            crc ^= (i * 31) & 0xff;
            for (int k = 0; k < 8; k++) crc = (crc >>> 1) ^ (0xEDB88320 & -(crc & 1));
        }
        return ~crc;
    }
    static byte toByte(int v) { return (byte) v; }
    static short toShort(int v) { return (short) v; }
    static char toChar(int v) { return (char) v; }
    static boolean inRange(int v, int lo, int hi) { return v >= lo && v < hi; }
    static int cmp(long a, long b) { return Long.compare(a, b); }
    static int mix(int a, long b, short c, byte d, char e, boolean f) { return (int) (a * 31 + b * 17 + c * 13 + d * 7 + e * 3 + (f ? 1 : 0)); }
    static int lit(int v) { return ((v + 1000) * 12 - 5) / 3 % 7 ^ (v >> 3) | (v >>> 2) & 255; }
    static int neg(int v) { return -v + ~v; }
    static long negL(long v) { return -v + ~v; }
    static int divs(int a, int b) { return a / b + a % b; }
    static long divsL(long a, long b) { return a / b + a % b; }
    static int spinCount(int n) { int c = 0; for (int i = 0; i < n; i++) c += i % 3 == 0 ? 2 : 1; return c; }

    public static String run() {
        out = new StringBuilder();
        int[] ints = {0, 1, -1, 2, 7, -7, 100, 65535, 65536, 1000003, Integer.MAX_VALUE, Integer.MIN_VALUE, Integer.MIN_VALUE + 1};
        long[] longs = {0L, 1L, -1L, 3L, 1L << 40, -(1L << 40), Long.MAX_VALUE, Long.MIN_VALUE, 0x123456789abcdefL};
        p("gcd", gcd(1071, 462) + "," + gcd(0, 5) + "," + gcd(-12, 18) + "," + gcd(Integer.MIN_VALUE, 6));
        p("gcdL", gcdL(1L << 40, 1L << 20) + "," + gcdL(-90L, 60L) + "," + gcdL(Long.MAX_VALUE, 7L));
        StringBuilder sb = new StringBuilder();
        for (int n = 1; n < 40; n++) sb.append(collatz(n)).append(' ');
        p("collatz", sb);
        sb = new StringBuilder();
        for (int v : ints) sb.append(popcount(v)).append(' ');
        p("popcount", sb);
        sb = new StringBuilder();
        for (long v : longs) sb.append(popcountL(v)).append(' ');
        p("popcountL", sb);
        p("fnv", fnv(0) + "," + fnv(1) + "," + fnv(1000) + "," + fnv(123457));
        p("fnvL", fnvL(0) + "," + fnvL(1) + "," + fnvL(1000) + "," + fnvL(123457));
        sb = new StringBuilder();
        for (int v : ints) for (int n : new int[]{1, 5, 16, 31}) sb.append(rotl(v, n)).append(' ');
        p("rotl", sb);
        sb = new StringBuilder();
        for (long v : longs) for (int n : new int[]{1, 13, 32, 63}) sb.append(rotlL(v, n)).append(' ');
        p("rotlL", sb);
        p("xorshift", xorshift(2463534242L > 0 ? 123456789 : 1, 100000) + "," + xorshift(1, 1) + "," + xorshift(-5, 77));
        p("xorshiftL", xorshiftL(88172645463325252L, 100000) + "," + xorshiftL(-1L, 3));
        sb = new StringBuilder();
        for (int v : new int[]{0, 1, 2, 3, 4, 99, 100, 101, 65535, 1000000, 2147395600, Integer.MAX_VALUE}) sb.append(isqrt(v)).append(' ');
        p("isqrt", sb);
        p("powmod", powmod(2, 62, 1000000007L) + "," + powmod(7, 1L << 40, 998244353L) + "," + powmod(3, 0, 5));
        p("primes", primes(5000));
        p("crc", crc(0, 1) + "," + crc(12345, 500) + "," + crc(-1, 3));
        sb = new StringBuilder();
        for (int v : ints) sb.append(toByte(v)).append(',').append(toShort(v)).append(',').append((int) toChar(v)).append(' ');
        p("narrow", sb);
        p("inRange", inRange(5, 0, 10) + "," + inRange(10, 0, 10) + "," + inRange(-1, 0, 10));
        sb = new StringBuilder();
        for (long a : longs) for (long b : longs) sb.append(cmp(a, b)).append(' ');
        p("cmp", sb);
        p("mix", mix(1, 2L, (short) -3, (byte) 4, 'e', true) + "," + mix(Integer.MAX_VALUE, Long.MAX_VALUE, Short.MIN_VALUE, Byte.MIN_VALUE, '￿', false));
        sb = new StringBuilder();
        for (int v : ints) sb.append(lit(v)).append(' ');
        p("lit", sb);
        sb = new StringBuilder();
        for (int v : ints) sb.append(neg(v)).append(' ');
        for (long v : longs) sb.append(negL(v)).append(' ');
        p("neg", sb);
        sb = new StringBuilder();
        for (int a : ints) for (int b : ints) { if (b != 0) sb.append(divs(a, b)).append(' '); }
        p("divs", sb);
        sb = new StringBuilder();
        for (long a : longs) for (long b : longs) { if (b != 0) sb.append(divsL(a, b)).append(' '); }
        p("divsL", sb);
        try { divs(1, 0); } catch (ArithmeticException e) { p("div zero", e.getClass().getName()); }
        try { divsL(1, 0); } catch (ArithmeticException e) { p("div zero L", e.getClass().getName()); }
        p("spin", spinCount(200000));
        return out.toString();
    }
}
