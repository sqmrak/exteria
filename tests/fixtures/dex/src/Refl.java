import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.reflect.*;
import java.util.Arrays;

public class Refl {
    static StringBuilder out;

    static void p(String name, Object v) {
        out.append(name).append('=').append(v).append('\n');
    }

    enum Kind { A, B, C }

    @Retention(RetentionPolicy.RUNTIME)
    @interface Info {
        String name();
        int n() default 7;
        String[] tags() default {"x"};
        Kind kind() default Kind.A;
        Class<?> type() default Object.class;
        long big() default 1L << 40;
        boolean flag() default true;
        double ratio() default 0.5;
    }

    @Retention(RetentionPolicy.RUNTIME)
    @interface Marker {}

    @Retention(RetentionPolicy.CLASS)
    @interface Hidden {}

    interface Shape {
        double area();
        String name(String prefix);
        default String describe() { return name("shape") + area(); }
    }

    @Info(name = "target", tags = {"a", "b"}, kind = Kind.C, type = String.class)
    @Marker
    @Hidden
    public static class Target implements Shape {
        public int pub = 5;
        private String secret = "s";
        protected long prot = 9L;
        public static int count = 3;
        public static final String LABEL = "lbl";
        public double ratio = 1.5;
        public boolean on;
        public char ch = 'q';
        public byte by = -3;
        public short sh = 300;
        public float fl = 2.5f;

        public Target() {}
        public Target(int pub) { this.pub = pub; }
        public Target(String s, long l) { this.secret = s; this.prot = l; }
        private Target(boolean hidden) { this.secret = "hidden"; }

        @Info(name = "m", n = 1)
        public int add(int a, int b) { return a + b; }
        public long wide(long a, double b, float c) { return a + (long) b + (long) c; }
        public String join(String a, Object b, char c) { return a + b + c; }
        public void fail() { throw new IllegalStateException("inner"); }
        public static int twice(int x) { return x * 2; }
        public static String hello() { return "hello"; }
        private String hidden() { return "hid" + secret; }
        public double area() { return pub * 2.0; }
        public String name(String prefix) { return prefix + ":" + pub; }
        public int[] arr(int n) { return new int[n]; }
        public String over(int x) { return "int"; }
        public String over(long x) { return "long"; }
        public String over(Object x) { return "obj"; }
        public static void stat(String... rest) { out.append("stat").append(rest.length).append(';'); }
    }

    static String join(Object[] items) {
        StringBuilder b = new StringBuilder();
        for (Object o : items) b.append(o).append(',');
        return b.toString();
    }

    static String sortedNames(Method[] methods) {
        String[] names = new String[methods.length];
        int n = 0;
        for (Method m : methods) if (!m.isSynthetic()) names[n++] = m.getName() + m.getParameterTypes().length;
        String[] used = Arrays.copyOf(names, n);
        Arrays.sort(used);
        return join(used);
    }

    public static String run() throws Exception {
        out = new StringBuilder();
        Class<?> c = Class.forName("Refl$Target");
        p("name", c.getName() + "," + c.getSimpleName() + "," + (c == Target.class) + "," + c.isInterface());
        p("modifiers", Modifier.toString(c.getModifiers()));
        p("super", c.getSuperclass().getName() + "," + c.getInterfaces().length + "," + c.getInterfaces()[0].getSimpleName());
        p("assignable", Shape.class.isAssignableFrom(c) + "," + c.isAssignableFrom(Shape.class) + "," + Object.class.isAssignableFrom(c));
        Object o = c.getConstructor().newInstance();
        p("new", c.isInstance(o) + "," + (o instanceof Shape));
        Object o2 = c.getConstructor(int.class).newInstance(41);
        Object o3 = c.getConstructor(String.class, long.class).newInstance("x", 7L);
        Constructor<?> hidden = c.getDeclaredConstructor(boolean.class);
        hidden.setAccessible(true);
        Object o4 = hidden.newInstance(true);
        p("ctors", c.getConstructors().length + "," + c.getDeclaredConstructors().length + "," + Modifier.isPrivate(hidden.getModifiers()));
        Method add = c.getMethod("add", int.class, int.class);
        p("add", add.invoke(o, 2, 3) + "," + add.invoke(o2, 40, 2) + "," + add.getReturnType().getName() + "," + add.getParameterTypes().length);
        p("wide", c.getMethod("wide", long.class, double.class, float.class).invoke(o, 1L, 2.9, 3.9f));
        p("join", c.getMethod("join", String.class, Object.class, char.class).invoke(o, "a", 1.5, 'z'));
        p("widen", add.invoke(o, (byte) 1, (short) 2));
        p("static", c.getMethod("twice", int.class).invoke(null, 21) + "," + c.getMethod("hello").invoke(null));
        p("hidden", invokeHidden(c, o3));
        String ite;
        try { c.getMethod("fail").invoke(o); ite = "no"; }
        catch (InvocationTargetException e) { ite = e.getCause().getClass().getName() + ":" + e.getCause().getMessage(); }
        p("ite", ite);
        String bad;
        try { add.invoke(o, "x", 1); bad = "no"; } catch (IllegalArgumentException e) { bad = "iae"; }
        try { add.invoke(o, 1); bad += ",no"; } catch (IllegalArgumentException e) { bad += ",iae"; }
        try { add.invoke(null, 1, 2); bad += ",no"; } catch (NullPointerException e) { bad += ",npe"; }
        try { add.invoke("str", 1, 2); bad += ",no"; } catch (IllegalArgumentException e) { bad += ",iae"; }
        p("bad", bad);
        String nsm;
        try { c.getMethod("nothing"); nsm = "no"; } catch (NoSuchMethodException e) { nsm = "nsme"; }
        try { c.getDeclaredMethod("hidden").invoke(o); nsm += ",ok"; } catch (Exception e) { nsm += ",fail"; }
        p("nsme", nsm);
        p("over", c.getMethod("over", int.class).invoke(o, 1) + "," + c.getMethod("over", long.class).invoke(o, 1L)
            + "," + c.getMethod("over", Object.class).invoke(o, "s"));
        p("methods", sortedNames(c.getDeclaredMethods()));
        Method[] pub = c.getMethods();
        int objectMethods = 0;
        for (Method m : pub) if (m.getDeclaringClass() == Object.class) objectMethods++;
        p("publicmethods", pub.length > 10 && objectMethods > 0);
        p("arrret", ((int[]) c.getMethod("arr", int.class).invoke(o, 4)).length);
        c.getMethod("stat", String[].class).invoke(null, (Object) new String[]{"a", "b"});
        p("varargs", out.toString().contains("stat2;") + "," + c.getMethod("stat", String[].class).isVarArgs());
        Field pub1 = c.getField("pub");
        p("get", pub1.get(o) + "," + pub1.getInt(o2) + "," + pub1.getType().getName() + "," + Modifier.toString(pub1.getModifiers()));
        pub1.set(o, 99);
        pub1.setInt(o2, 100);
        p("set", pub1.get(o) + "," + pub1.get(o2));
        Field secret = c.getDeclaredField("secret");
        secret.setAccessible(true);
        p("secret", secret.get(o) + "," + secret.get(o3) + "," + secret.get(o4));
        Field prot = c.getDeclaredField("prot");
        prot.setAccessible(true);
        p("prot", prot.getLong(o3) + "," + Modifier.isProtected(prot.getModifiers()));
        p("static field", c.getField("count").get(null) + "," + c.getField("LABEL").get(null) + "," + Modifier.toString(c.getField("LABEL").getModifiers()));
        c.getField("count").set(null, 10);
        p("static set", Target.count);
        p("prims", c.getField("ratio").getDouble(o) + "," + c.getField("on").getBoolean(o) + "," + c.getField("ch").get(o)
            + "," + c.getField("by").get(o) + "," + c.getField("sh").getLong(o) + "," + c.getField("fl").getFloat(o)
            + "," + c.getField("sh").getInt(o));
        String fe;
        try { c.getDeclaredField("none"); fe = "no"; } catch (NoSuchFieldException e) { fe = "nsfe"; }
        try { c.getField("secret"); fe += ",no"; } catch (NoSuchFieldException e) { fe += ",nsfe"; }
        try { c.getField("on").getInt(o); fe += ",no"; } catch (IllegalArgumentException e) { fe += ",iae"; }
        try { pub1.get("wrong"); fe += ",no"; } catch (IllegalArgumentException e) { fe += ",iae"; }
        p("fielderr", fe);
        int pubCount = 0;
        for (Field f : c.getDeclaredFields()) if (!f.isSynthetic()) pubCount++;
        p("fields", pubCount + "," + c.getFields().length);

        Info info = c.getAnnotation(Info.class);
        p("anno", info.name() + "," + info.n() + "," + join(info.tags()) + "," + info.kind() + "," + info.type().getName()
            + "," + info.big() + "," + info.flag() + "," + info.ratio() + "," + (info.annotationType() == Info.class));
        p("marker", c.isAnnotationPresent(Marker.class) + "," + c.isAnnotationPresent(Hidden.class) + "," + c.getAnnotations().length);
        Info mi = add.getAnnotation(Info.class);
        p("methodanno", mi.name() + "," + mi.n() + "," + join(mi.tags()) + "," + (c.getMethod("twice", int.class).getAnnotation(Info.class) == null));

        Shape proxy = (Shape) Proxy.newProxyInstance(Refl.class.getClassLoader(), new Class<?>[]{Shape.class},
            new InvocationHandler() {
                public Object invoke(Object self, Method m, Object[] args) throws Throwable {
                    if (m.getName().equals("area")) return 2.5;
                    if (m.getName().equals("name")) return "p-" + args[0];
                    if (m.getName().equals("toString")) return "PROXY";
                    if (m.getName().equals("hashCode")) return 77;
                    if (m.getName().equals("equals")) return self == args[0];
                    return null;
                }
            });
        p("proxy", proxy.area() + "," + proxy.name("q") + "," + proxy + "," + proxy.hashCode() + "," + proxy.equals(proxy)
            + "," + Proxy.isProxyClass(proxy.getClass()) + "," + (proxy instanceof Shape));
        Shape thrower = (Shape) Proxy.newProxyInstance(Refl.class.getClassLoader(), new Class<?>[]{Shape.class},
            new InvocationHandler() {
                public Object invoke(Object self, Method m, Object[] args) { throw new IllegalStateException("from-handler"); }
            });
        String pe;
        try { thrower.area(); pe = "no"; } catch (IllegalStateException e) { pe = e.getMessage(); }
        p("proxythrow", pe);
        Object arr = Array.newInstance(int.class, 3);
        Array.setInt(arr, 1, 7);
        Array.set(arr, 2, 9);
        p("array", Array.getLength(arr) + "," + Array.get(arr, 1) + "," + Array.getInt(arr, 2) + "," + arr.getClass().getName());
        Object grid = Array.newInstance(String.class, 2, 3);
        p("grid", grid.getClass().getName() + "," + ((Object[]) grid).length);
        p("enum", Kind.class.isEnum() + "," + Kind.class.getEnumConstants().length + "," + Kind.valueOf("B").ordinal()
            + "," + Kind.class.getEnumConstants()[2]);
        p("misc", Info.class.isAnnotation() + "," + Shape.class.isInterface() + "," + int.class.isPrimitive() + ","
            + int[].class.isArray() + "," + int[].class.getComponentType().getName() + "," + Target.class.getEnclosingClass().getSimpleName()
            + "," + void.class.getName());
        p("cast", c.cast(o) == o);
        String cce;
        try { c.cast("s"); cce = "no"; } catch (ClassCastException e) { cce = "cce"; }
        p("castfail", cce);
        return out.toString();
    }

    static Object invokeHidden(Class<?> c, Object target) throws Exception {
        Method m = c.getDeclaredMethod("hidden");
        m.setAccessible(true);
        return m.invoke(target);
    }
}
