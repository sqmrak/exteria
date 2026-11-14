import java.lang.invoke.CallSite;
import java.lang.invoke.ConstantCallSite;
import java.lang.invoke.MethodHandle;
import java.lang.invoke.MethodHandles;
import java.lang.invoke.MethodType;
import java.lang.invoke.MutableCallSite;

/** bootstrap methods and targets for the call sites CustomIndyGen writes into CustomIndy */
public class Bootstraps {
    static int hits;
    static int field = 11;
    int inst = 21;

    public static int add(int a, int b) { return a + b; }
    public static String greet(String who) { return "hello " + who; }
    public static long mix(long a, int b, double c) { return a * 100 + b + (long) c; }
    public static String describe(String a, Object b) { return a + ":" + b; }
    public static boolean even(int v) { return v % 2 == 0; }
    public static String first(String v) { return "first:" + v; }
    public static String second(String v) { return "second:" + v; }
    public static int fail(int v) { throw new IllegalArgumentException("bad " + v); }
    public static int recover(Throwable t, int v) { return -v; }
    public static String label(Object v) { return "<" + v + ">"; }
    public static int twice(int v) { return v * 2; }
    public int plus(int v) { return inst + v; }
    public Bootstraps() {}
    public Bootstraps(int inst) { this.inst = inst; }

    /** the target is the static method of this class named by the call site, looked up with the type of the site */
    public static CallSite byName(MethodHandles.Lookup lookup, String name, MethodType type) throws Exception {
        return new ConstantCallSite(lookup.findStatic(Bootstraps.class, name, type));
    }

    /** every kind of static argument: int, String, long, Class, MethodType, MethodHandle, double, float */
    public static CallSite arguments(MethodHandles.Lookup lookup, String name, MethodType type, int i, String s, long l,
                                     Class<?> c, MethodType mt, MethodHandle mh, double d, float f) throws Exception {
        String text = i + "," + s + "," + l + "," + c.getName() + "," + mt + "," + mh.type() + "," + d + "," + f;
        return new ConstantCallSite(MethodHandles.dropArguments(MethodHandles.constant(String.class, text), 0,
                type.parameterArray()));
    }

    /** the static arguments arrive as an array */
    public static CallSite varargs(MethodHandles.Lookup lookup, String name, MethodType type, Object... extras) throws Exception {
        StringBuilder text = new StringBuilder();
        for (Object extra : extras) text.append(extra instanceof Class ? ((Class<?>) extra).getSimpleName() : extra).append('|');
        return new ConstantCallSite(MethodHandles.dropArguments(MethodHandles.constant(String.class, text.toString()), 0,
                type.parameterArray()));
    }

    /** a mutable site: the first call runs `first`, the target is switched to `second` for the rest */
    public static CallSite switching(MethodHandles.Lookup lookup, String name, MethodType type) throws Exception {
        MutableCallSite site = new MutableCallSite(type);
        MethodHandle once = lookup.findStatic(Bootstraps.class, "firstThenSecond", MethodType.methodType(String.class, MutableCallSite.class, MethodHandle.class, String.class));
        MethodHandle second = lookup.findStatic(Bootstraps.class, "second", type);
        site.setTarget(MethodHandles.insertArguments(once, 0, site, second));
        return site;
    }
    public static String firstThenSecond(MutableCallSite site, MethodHandle second, String v) throws Throwable {
        site.setTarget(second);
        return first(v);
    }

    /** combinators: guardWithTest(even, first, second) over a dropped-argument shape, filterReturnValue, bindTo, asType */
    public static CallSite combined(MethodHandles.Lookup lookup, String name, MethodType type) throws Exception {
        MethodHandle even = lookup.findStatic(Bootstraps.class, "even", MethodType.methodType(boolean.class, int.class));
        MethodHandle twice = lookup.findStatic(Bootstraps.class, "twice", MethodType.methodType(int.class, int.class));
        MethodHandle add = lookup.findStatic(Bootstraps.class, "add", MethodType.methodType(int.class, int.class, int.class));
        MethodHandle plusTen = MethodHandles.insertArguments(add, 0, 10);
        MethodHandle guarded = MethodHandles.guardWithTest(even, twice, plusTen);
        MethodHandle label = lookup.findStatic(Bootstraps.class, "label", MethodType.methodType(String.class, Object.class));
        MethodHandle filtered = MethodHandles.filterReturnValue(guarded, label.asType(MethodType.methodType(String.class, int.class)));
        MethodHandle bound = lookup.findVirtual(Bootstraps.class, "plus", MethodType.methodType(int.class, int.class)).bindTo(new Bootstraps(1000));
        MethodHandle both = MethodHandles.filterReturnValue(bound, label.asType(MethodType.methodType(String.class, int.class)));
        MethodHandle pick = MethodHandles.guardWithTest(MethodHandles.dropArguments(MethodHandles.constant(boolean.class, Boolean.TRUE), 0, int.class), filtered, both);
        return new ConstantCallSite(pick.asType(type));
    }

    /** fields and constructors through the lookup */
    public static CallSite members(MethodHandles.Lookup lookup, String name, MethodType type) throws Exception {
        MethodHandle get = lookup.findStaticGetter(Bootstraps.class, "field", int.class);
        MethodHandle set = lookup.findStaticSetter(Bootstraps.class, "field", int.class);
        MethodHandle ctor = lookup.findConstructor(Bootstraps.class, MethodType.methodType(void.class, int.class));
        MethodHandle getInst = lookup.findGetter(Bootstraps.class, "inst", int.class);
        MethodHandle setInst = lookup.findSetter(Bootstraps.class, "inst", int.class);
        MethodHandle combo = MethodHandles.filterReturnValue(ctor, getInst);
        MethodHandle swap = new SwapFields(get, set, combo, setInst).handle(type);
        return new ConstantCallSite(swap);
    }

    static final class SwapFields {
        final MethodHandle get, set, combo, setInst;
        SwapFields(MethodHandle get, MethodHandle set, MethodHandle combo, MethodHandle setInst) {
            this.get = get; this.set = set; this.combo = combo; this.setInst = setInst;
        }
        String run(int value) throws Throwable {
            int before = (int) get.invokeExact();
            set.invokeExact(value);
            int after = (int) get.invokeExact();
            int fromCtor = (int) combo.invokeExact(value + 5);
            Bootstraps made = new Bootstraps();
            setInst.invokeExact(made, value + 6);
            return before + "," + after + "," + fromCtor + "," + made.inst;
        }
        MethodHandle handle(MethodType type) throws Exception {
            return MethodHandles.lookup().findVirtual(SwapFields.class, "run", MethodType.methodType(String.class, int.class)).bindTo(this).asType(type);
        }
    }

    /** catchException around a method that throws */
    public static CallSite guarded(MethodHandles.Lookup lookup, String name, MethodType type) throws Exception {
        MethodHandle fail = lookup.findStatic(Bootstraps.class, "fail", MethodType.methodType(int.class, int.class));
        MethodHandle recover = lookup.findStatic(Bootstraps.class, "recover", MethodType.methodType(int.class, Throwable.class, int.class));
        return new ConstantCallSite(MethodHandles.catchException(fail, IllegalArgumentException.class, recover));
    }

    /** a bootstrap that throws: the site fails with BootstrapMethodError */
    public static CallSite broken(MethodHandles.Lookup lookup, String name, MethodType type) {
        throw new IllegalStateException("no bootstrap today");
    }
}
