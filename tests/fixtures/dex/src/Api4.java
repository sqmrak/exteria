import java.io.*;
import java.math.BigInteger;
import java.net.*;
import java.security.*;
import java.security.spec.*;
import java.util.*;
import javax.net.*;
import javax.net.ssl.*;
import javax.security.auth.*;

/** permissions, key specs, SNI names, Destroyable and ServerSocketFactory */
public class Api4 {
    static StringBuilder out;
    static void p(String name, Object v) { out.append(name).append('=').append(v).append('\n'); }

    static class Secret implements Destroyable {
        boolean gone;
        public void destroy() { gone = true; }
        public boolean isDestroyed() { return gone; }
    }
    static class Plain implements Destroyable { }
    static class Custom extends BasicPermission {
        Custom(String n) { super(n); }
    }

    public static String run() throws Exception {
        out = new StringBuilder();

        BasicPermission wild = new RuntimePermission("accessDeclared.*");
        p("basic implies", wild.implies(new RuntimePermission("accessDeclared.members")) + "," + wild.implies(new RuntimePermission("accessDeclared"))
            + "," + wild.implies(new RuntimePermission("other")) + "," + new RuntimePermission("*").implies(new RuntimePermission("x.y"))
            + "," + wild.implies(new SecurityPermission("accessDeclared.members")));
        p("basic text", new RuntimePermission("exitVM") + "|" + new RuntimePermission("exitVM").getActions().isEmpty() + "|" + new RuntimePermission("a").equals(new RuntimePermission("a"))
            + "|" + (new RuntimePermission("a").hashCode() == "a".hashCode()) + "|" + new Custom("z").getName());
        try { new RuntimePermission(""); } catch (IllegalArgumentException e) { p("empty name", e.getMessage()); }
        AllPermission all = new AllPermission();
        p("all", all + "|" + all.implies(new RuntimePermission("x")) + "|" + all.getName() + "|" + all.getActions() + "|" + all.equals(new AllPermission()));
        FilePermission fp = new FilePermission("/tmp/-", "write,read");
        p("file actions", fp.getActions() + "," + fp.implies(new FilePermission("/tmp/a/b.txt", "read")) + "," + fp.implies(new FilePermission("/tmp/a", "execute"))
            + "," + new FilePermission("/tmp/*", "read").implies(new FilePermission("/tmp/x", "read")) + "," + new FilePermission("/tmp/*", "read").implies(new FilePermission("/tmp/x/y", "read"))
            + "," + new FilePermission("<<ALL FILES>>", "read").implies(new FilePermission("/etc/passwd", "read")) + "," + fp);
        PropertyPermission pp = new PropertyPermission("java.*", "read");
        p("property", pp.implies(new PropertyPermission("java.version", "read")) + "," + pp.implies(new PropertyPermission("java.version", "write")) + "," + pp.getActions());
        Permissions perms = new Permissions();
        perms.add(new RuntimePermission("a.*"));
        perms.add(new FilePermission("/x", "read"));
        int count = 0;
        for (Enumeration<Permission> e = perms.elements(); e.hasMoreElements(); e.nextElement()) count++;
        p("permissions", count + "," + perms.implies(new RuntimePermission("a.b")) + "," + perms.implies(new RuntimePermission("b")) + "," + perms.implies(new FilePermission("/x", "read")));

        BigInteger prime = new BigInteger("115792089210356248762697446949407573530086143415290314195533631308867097853951");
        ECFieldFp field = new ECFieldFp(prime);
        p("field", field.getFieldSize() + "," + field.getP().equals(prime) + "," + field.equals(new ECFieldFp(prime)));
        BigInteger minus3 = prime.subtract(BigInteger.valueOf(3));
        EllipticCurve curve = new EllipticCurve(field, minus3, BigInteger.TEN);
        try { new EllipticCurve(field, BigInteger.valueOf(-3), BigInteger.TEN); } catch (IllegalArgumentException e) { p("neg coefficient", e.getMessage()); }
        try { new EllipticCurve(field, BigInteger.ONE, prime); } catch (IllegalArgumentException e) { p("big coefficient", e.getMessage()); }
        ECPoint g = new ECPoint(BigInteger.valueOf(5), BigInteger.valueOf(6));
        ECParameterSpec spec = new ECParameterSpec(curve, g, BigInteger.valueOf(1234567), 1);
        p("curve", curve.getA() + "," + curve.getB() + "," + curve.getSeed() + "," + curve.equals(new EllipticCurve(new ECFieldFp(prime), minus3, BigInteger.TEN))
            + "," + spec.getCofactor() + "," + spec.getOrder() + "," + spec.getGenerator().getAffineX() + "," + spec.getCurve().getField().getFieldSize());
        p("point", ECPoint.POINT_INFINITY.getAffineX() + "," + g.equals(new ECPoint(BigInteger.valueOf(5), BigInteger.valueOf(6))) + "," + g.equals(ECPoint.POINT_INFINITY));
        try { new ECParameterSpec(curve, g, BigInteger.ZERO, 1); } catch (IllegalArgumentException e) { p("bad order", e.getMessage()); }
        try { new ECFieldFp(BigInteger.ZERO); } catch (IllegalArgumentException e) { p("bad field", e.getMessage()); }
        ECPublicKeySpec pub = new ECPublicKeySpec(g, spec);
        ECPrivateKeySpec priv = new ECPrivateKeySpec(BigInteger.valueOf(77), spec);
        p("ec specs", pub.getW().getAffineY() + "," + pub.getParams().getCofactor() + "," + priv.getS() + "," + new ECGenParameterSpec("secp256r1").getName());
        try { new ECPublicKeySpec(ECPoint.POINT_INFINITY, spec); } catch (IllegalArgumentException e) { p("infinity key", e.getMessage()); }
        p("mgf1", MGF1ParameterSpec.SHA256.getDigestAlgorithm() + "," + MGF1ParameterSpec.SHA1.getDigestAlgorithm() + "," + MGF1ParameterSpec.SHA512_256.getDigestAlgorithm());
        PSSParameterSpec def = PSSParameterSpec.DEFAULT;
        PSSParameterSpec pss = new PSSParameterSpec("SHA-256", "MGF1", MGF1ParameterSpec.SHA256, 32, 1);
        p("pss", def.getDigestAlgorithm() + "," + def.getMGFAlgorithm() + "," + def.getSaltLength() + "," + def.getTrailerField() + "," + pss.getDigestAlgorithm() + ","
            + ((MGF1ParameterSpec) pss.getMGFParameters()).getDigestAlgorithm() + "," + pss.getSaltLength() + "," + new PSSParameterSpec(16).getSaltLength());
        try { new PSSParameterSpec(-1); } catch (IllegalArgumentException e) { p("bad salt", e.getMessage()); }
        RSAPrivateCrtKeySpec crt = new RSAPrivateCrtKeySpec(BigInteger.valueOf(3233), BigInteger.valueOf(17), BigInteger.valueOf(2753), BigInteger.valueOf(61),
            BigInteger.valueOf(53), BigInteger.valueOf(53), BigInteger.valueOf(49), BigInteger.valueOf(38));
        p("rsa crt", crt.getModulus() + "," + crt.getPublicExponent() + "," + crt.getPrivateExponent() + "," + crt.getPrimeP() + "," + crt.getPrimeQ() + ","
            + crt.getPrimeExponentP() + "," + crt.getPrimeExponentQ() + "," + crt.getCrtCoefficient());
        p("named", NamedParameterSpec.X25519.getName() + "," + NamedParameterSpec.X448.getName() + "," + new NamedParameterSpec("X448").getName());

        SNIHostName host = new SNIHostName("Example.COM");
        p("sni", host.getAsciiName() + "," + host.getType() + "," + host + "," + host.equals(new SNIHostName("example.com")) + "," + (host.hashCode() == new SNIHostName("EXAMPLE.com").hashCode())
            + "," + StandardConstants.SNI_HOST_NAME + "," + Arrays.toString(host.getEncoded()).length());
        SNIMatcher matcher = SNIHostName.createSNIMatcher(".*\\.example\\.com");
        p("sni matcher", matcher.matches(new SNIHostName("www.example.com")) + "," + matcher.matches(new SNIHostName("example.org")) + "," + matcher.getType());
        try { new SNIHostName("trailing."); } catch (IllegalArgumentException e) { p("sni dot", e.getMessage()); }
        try { new SNIHostName("1.2.3.4"); } catch (IllegalArgumentException e) { p("sni ip", e.getMessage()); }
        try { new SNIHostName(""); } catch (IllegalArgumentException e) { p("sni empty", e.getMessage()); }

        Secret secret = new Secret();
        p("destroyable", secret.isDestroyed() + ",");
        secret.destroy();
        p("destroyed", secret.isDestroyed());
        Plain plain = new Plain();
        p("default destroyable", plain.isDestroyed());
        try { plain.destroy(); } catch (DestroyFailedException e) { p("default destroy", "failed"); }

        ServerSocketFactory factory = ServerSocketFactory.getDefault();
        try (ServerSocket server = factory.createServerSocket(0)) {
            p("server socket", (server.getLocalPort() > 0) + "," + !server.isClosed() + "," + (factory == ServerSocketFactory.getDefault()));
        }
        return out.toString();
    }
}
