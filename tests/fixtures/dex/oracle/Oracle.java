public final class Oracle {
    public static void main(String[] args) throws Exception {
        Object result = Class.forName(args[0]).getMethod("run").invoke(null);
        System.out.print(result);
    }
}
