import java.lang.classfile.ClassFile;
import java.lang.classfile.CodeBuilder;
import java.lang.constant.ClassDesc;
import java.lang.constant.ConstantDescs;
import java.lang.constant.DirectMethodHandleDesc;
import java.lang.constant.DynamicCallSiteDesc;
import java.lang.constant.MethodHandleDesc;
import java.lang.constant.MethodTypeDesc;
import java.nio.file.Files;
import java.nio.file.Path;

/** writes CustomIndy.class: one static run() that makes the call sites javac has no syntax for */
public class CustomIndyGen {
    static final ClassDesc BOOT = ClassDesc.of("Bootstraps");
    static final ClassDesc STRING = ConstantDescs.CD_String;
    static final ClassDesc OUT = ClassDesc.of("CustomIndy");

    static DirectMethodHandleDesc bootstrap(String name, MethodTypeDesc type) {
        return MethodHandleDesc.ofMethod(DirectMethodHandleDesc.Kind.STATIC, BOOT, name, type);
    }

    static final MethodTypeDesc PLAIN = MethodTypeDesc.of(ConstantDescs.CD_CallSite, ConstantDescs.CD_MethodHandles_Lookup,
            STRING, ConstantDescs.CD_MethodType);

    /** appends name=<value of the call>\n to the builder held in local 0 */
    static void record(CodeBuilder b, String label, java.util.function.Consumer<CodeBuilder> call, ClassDesc result) {
        b.aload(0).ldc(label + "=");
        b.invokevirtual(ClassDesc.of("java.lang.StringBuilder"), "append", MethodTypeDesc.of(ClassDesc.of("java.lang.StringBuilder"), STRING));
        call.accept(b);
        String sig = result.equals(ConstantDescs.CD_int) ? "I" : result.equals(ConstantDescs.CD_long) ? "J" : "S";
        ClassDesc param = sig.equals("S") ? STRING : result;
        b.invokevirtual(ClassDesc.of("java.lang.StringBuilder"), "append", MethodTypeDesc.of(ClassDesc.of("java.lang.StringBuilder"), param));
        b.bipush(10);
        b.invokevirtual(ClassDesc.of("java.lang.StringBuilder"), "append", MethodTypeDesc.of(ClassDesc.of("java.lang.StringBuilder"), ConstantDescs.CD_char));
        b.pop();
    }

    public static void main(String[] args) throws Exception {
        byte[] bytes = ClassFile.of().build(OUT, cb -> {
            cb.withVersion(55, 0);
            cb.withFlags(ClassFile.ACC_PUBLIC | ClassFile.ACC_SUPER);
            cb.withMethodBody("run", MethodTypeDesc.of(STRING), ClassFile.ACC_PUBLIC | ClassFile.ACC_STATIC, b -> {
                ClassDesc sb = ClassDesc.of("java.lang.StringBuilder");
                b.new_(sb).dup().invokespecial(sb, "<init>", MethodTypeDesc.of(ConstantDescs.CD_void)).astore(0);

                record(b, "add", c -> c.bipush(40).bipush(2).invokedynamic(
                        DynamicCallSiteDesc.of(bootstrap("byName", PLAIN), "add", MethodTypeDesc.of(ConstantDescs.CD_int, ConstantDescs.CD_int, ConstantDescs.CD_int))), ConstantDescs.CD_int);
                record(b, "greet", c -> c.ldc("world").invokedynamic(
                        DynamicCallSiteDesc.of(bootstrap("byName", PLAIN), "greet", MethodTypeDesc.of(STRING, STRING))), STRING);
                record(b, "mix", c -> c.ldc(7L).iconst_3().ldc(2.75).invokedynamic(
                        DynamicCallSiteDesc.of(bootstrap("byName", PLAIN), "mix", MethodTypeDesc.of(ConstantDescs.CD_long, ConstantDescs.CD_long, ConstantDescs.CD_int, ConstantDescs.CD_double))), ConstantDescs.CD_long);

                MethodTypeDesc argsBoot = MethodTypeDesc.of(ConstantDescs.CD_CallSite, ConstantDescs.CD_MethodHandles_Lookup, STRING,
                        ConstantDescs.CD_MethodType, ConstantDescs.CD_int, STRING, ConstantDescs.CD_long, ConstantDescs.CD_Class,
                        ConstantDescs.CD_MethodType, ConstantDescs.CD_MethodHandle, ConstantDescs.CD_double, ConstantDescs.CD_float);
                record(b, "arguments", c -> c.invokedynamic(DynamicCallSiteDesc.of(bootstrap("arguments", argsBoot), "args",
                        MethodTypeDesc.of(STRING), -17, "text", 1L << 40, ClassDesc.of("java.lang.Integer"),
                        MethodTypeDesc.of(ConstantDescs.CD_int, ConstantDescs.CD_long, STRING),
                        bootstrap("byName", PLAIN), 2.5d, 0.5f)), STRING);

                MethodTypeDesc varBoot = MethodTypeDesc.of(ConstantDescs.CD_CallSite, ConstantDescs.CD_MethodHandles_Lookup, STRING,
                        ConstantDescs.CD_MethodType, ConstantDescs.CD_Object.arrayType());
                record(b, "varargs", c -> c.invokedynamic(DynamicCallSiteDesc.of(bootstrap("varargs", varBoot), "v",
                        MethodTypeDesc.of(STRING), 5, "s", 6L, ClassDesc.of("java.lang.String"))), STRING);
                record(b, "varargs none", c -> c.invokedynamic(DynamicCallSiteDesc.of(bootstrap("varargs", varBoot), "v",
                        MethodTypeDesc.of(STRING))), STRING);

                // one call site executed three times: the bootstrap runs once and the site retargets itself after the first call
                for (int i = 0; i < 3; i++) {
                    record(b, "switching " + i, c -> c.ldc("x").invokestatic(OUT, "sw", MethodTypeDesc.of(STRING, STRING)), STRING);
                }
                for (int v = 0; v < 4; v++) {
                    final int value = v;
                    record(b, "combined " + v, c -> c.bipush(value).invokedynamic(
                            DynamicCallSiteDesc.of(bootstrap("combined", PLAIN), "c", MethodTypeDesc.of(STRING, ConstantDescs.CD_int))), STRING);
                }
                record(b, "members", c -> c.bipush(30).invokedynamic(
                        DynamicCallSiteDesc.of(bootstrap("members", PLAIN), "m", MethodTypeDesc.of(STRING, ConstantDescs.CD_int))), STRING);
                record(b, "guarded", c -> c.bipush(9).invokedynamic(
                        DynamicCallSiteDesc.of(bootstrap("guarded", PLAIN), "g", MethodTypeDesc.of(ConstantDescs.CD_int, ConstantDescs.CD_int))), ConstantDescs.CD_int);

                b.aload(0).invokevirtual(sb, "toString", MethodTypeDesc.of(STRING)).areturn();
            });
            cb.withMethodBody("sw", MethodTypeDesc.of(STRING, STRING), ClassFile.ACC_PUBLIC | ClassFile.ACC_STATIC, b ->
                    b.aload(0).invokedynamic(DynamicCallSiteDesc.of(bootstrap("switching", PLAIN), "s", MethodTypeDesc.of(STRING, STRING))).areturn());
            cb.withMethodBody("broken", MethodTypeDesc.of(STRING), ClassFile.ACC_PUBLIC | ClassFile.ACC_STATIC, b ->
                    b.invokedynamic(DynamicCallSiteDesc.of(bootstrap("broken", PLAIN), "b", MethodTypeDesc.of(STRING))).areturn());
        });
        Files.write(Path.of(args[0], "CustomIndy.class"), bytes);
    }
}
