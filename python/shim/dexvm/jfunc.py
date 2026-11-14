"""java.util.function and the helpers every collection shares: equality, hashing and ordering as java defines them

an interface the vm knows is a python class with the default methods of the java interface. a dex class that implements
it does not inherit them (interfaces are not python bases of dex classes), the vm finds them through the interface
list of the class, see classes.find_host_virtual"""

from . import runtime
from .api import host_class, jmethod, jstatic
from .jlang import (Boolean, Byte, Character, Double, Float, Integer, Long, Object, Short, _StringImpl, _cs,
                    _compare_double)

_BOX_TYPES = (Integer, Long, Short, Byte, Character, Boolean, Float, Double)
_string_hashes = {}


def string_hash(text):
    found = _string_hashes.get(text)
    if found is None:
        found = _StringImpl.hashCode(text)
        if len(_string_hashes) > 20000:
            _string_hashes.clear()
        _string_hashes[text] = found
    return found


def jequals(a, b):
    """a.equals(b) with null on either side allowed"""
    if a is b:
        return True
    if a is None or b is None:
        return False
    if a.__class__ is str:
        return b.__class__ is str and a == b
    return bool(a.equals(b))


def jhash(value):
    if value is None:
        return 0
    if value.__class__ is str:
        return string_hash(value)
    return value.hashCode()


def jstring(value):
    """String.valueOf(Object)"""
    if value is None:
        return "null"
    if value.__class__ is str:
        return value
    return value.toString()


def compare_natural(a, b):
    """a.compareTo(b) for Comparable values; a null or a value that is not Comparable is an exception"""
    if a is None or b is None:
        runtime.npe()
    if a.__class__ is str:
        if b.__class__ is not str:
            runtime.throw_new("java.lang.ClassCastException", "%s cannot be cast to java.lang.String" % runtime.type_name_of(b))
        return _StringImpl.compareTo(a, b)
    method = getattr(a, "compareTo", None)
    if method is None:
        runtime.throw_new("java.lang.ClassCastException", "%s cannot be cast to java.lang.Comparable" % runtime.type_name_of(a))
    return method(b)


def compare_with(comparator, a, b):
    return compare_natural(a, b) if comparator is None else comparator.compare(a, b)


class _FunctionalDefaults:
    __slots__ = ()


@host_class("java.util.function.Function", interface=True)
class Function(_FunctionalDefaults):
    @jmethod("andThen", "(Ljava/util/function/Function;)Ljava/util/function/Function;")
    def andThen(self, after):
        return _Lambda("apply", lambda x: after.apply(self.apply(x)), Function)

    @jmethod("compose", "(Ljava/util/function/Function;)Ljava/util/function/Function;")
    def compose(self, before):
        return _Lambda("apply", lambda x: self.apply(before.apply(x)), Function)

    @jstatic("identity", "()Ljava/util/function/Function;")
    def identity():
        return _Lambda("apply", lambda x: x, Function)


@host_class("java.util.function.BiFunction", interface=True)
class BiFunction(_FunctionalDefaults):
    @jmethod("andThen", "(Ljava/util/function/Function;)Ljava/util/function/BiFunction;")
    def andThen(self, after):
        return _Lambda("apply", lambda a, b: after.apply(self.apply(a, b)), BiFunction)


@host_class("java.util.function.UnaryOperator", interface=True, interfaces=("java.util.function.Function",))
class UnaryOperator(Function):
    @jstatic("identity", "()Ljava/util/function/UnaryOperator;")
    def identity():
        return _Lambda("apply", lambda x: x, UnaryOperator)


@host_class("java.util.function.BinaryOperator", interface=True, interfaces=("java.util.function.BiFunction",))
class BinaryOperator(BiFunction):
    pass


@host_class("java.util.function.Consumer", interface=True)
class Consumer(_FunctionalDefaults):
    @jmethod("andThen", "(Ljava/util/function/Consumer;)Ljava/util/function/Consumer;")
    def andThen(self, after):
        def both(x):
            self.accept(x)
            after.accept(x)
        return _Lambda("accept", both, Consumer)


@host_class("java.util.function.BiConsumer", interface=True)
class BiConsumer(_FunctionalDefaults):
    pass


@host_class("java.util.function.Supplier", interface=True)
class Supplier(_FunctionalDefaults):
    pass


@host_class("java.util.function.Predicate", interface=True)
class Predicate(_FunctionalDefaults):
    @jmethod("negate", "()Ljava/util/function/Predicate;")
    def negate(self):
        return _Lambda("test", lambda x: not self.test(x), Predicate)

    @jmethod("and", "(Ljava/util/function/Predicate;)Ljava/util/function/Predicate;")
    def and_(self, other):
        return _Lambda("test", lambda x: bool(self.test(x)) and bool(other.test(x)), Predicate)

    @jmethod("or", "(Ljava/util/function/Predicate;)Ljava/util/function/Predicate;")
    def or_(self, other):
        return _Lambda("test", lambda x: bool(self.test(x)) or bool(other.test(x)), Predicate)


@host_class("java.util.function.BiPredicate", interface=True)
class BiPredicate(_FunctionalDefaults):
    pass


for _name in ("IntFunction", "IntPredicate", "IntConsumer", "IntSupplier", "IntUnaryOperator", "IntBinaryOperator",
              "ToIntFunction", "ToLongFunction", "ToDoubleFunction", "LongFunction", "LongSupplier", "DoubleSupplier",
              "BooleanSupplier", "ObjIntConsumer", "IntToLongFunction", "LongUnaryOperator", "LongBinaryOperator",
              "DoubleUnaryOperator", "DoubleBinaryOperator", "DoubleFunction", "ToIntBiFunction", "IntToDoubleFunction"):
    host_class("java.util.function." + _name, interface=True)(type(_name, (_FunctionalDefaults,), {"__slots__": ()}))


_lambda_classes = {}


def _Lambda(method, function, interface):
    """an object that implements a functional interface with a python function. one class per interface and method, so a call site caches the target by class like for any other object"""
    key = (method, interface)
    cls = _lambda_classes.get(key)
    if cls is None:
        def call(self, *args):
            return self._fn(*args)
        call.__name__ = method
        cls = _lambda_classes[key] = type("Lambda$" + method, (interface, Object), {method: call, "__slots__": ("_fn",)})
    obj = cls.__new__(cls)
    obj._fn = function
    return obj


@host_class("java.util.Comparator", interface=True)
class Comparator(_FunctionalDefaults):
    @jmethod("reversed", "()Ljava/util/Comparator;")
    def reversed(self):
        return _Lambda("compare", lambda a, b: self.compare(b, a), Comparator)

    @jmethod("thenComparing", "(Ljava/util/Comparator;)Ljava/util/Comparator;")
    def thenComparing(self, other):
        def chained(a, b):
            first = self.compare(a, b)
            return first if first != 0 else other.compare(a, b)
        return _Lambda("compare", chained, Comparator)

    @jmethod("thenComparing", "(Ljava/util/function/Function;)Ljava/util/Comparator;")
    def thenComparingKey(self, key):
        return self.thenComparing(Comparator.comparing(key))

    @jstatic("naturalOrder", "()Ljava/util/Comparator;")
    def naturalOrder():
        return _Lambda("compare", compare_natural, Comparator)

    @jstatic("reverseOrder", "()Ljava/util/Comparator;")
    def reverseOrder():
        return _Lambda("compare", lambda a, b: compare_natural(b, a), Comparator)

    @jstatic("comparing", "(Ljava/util/function/Function;)Ljava/util/Comparator;")
    def comparing(key):
        return _Lambda("compare", lambda a, b: compare_natural(key.apply(a), key.apply(b)), Comparator)

    @jstatic("comparing", "(Ljava/util/function/Function;Ljava/util/Comparator;)Ljava/util/Comparator;")
    def comparingWith(key, comparator):
        return _Lambda("compare", lambda a, b: comparator.compare(key.apply(a), key.apply(b)), Comparator)

    @jstatic("comparingInt", "(Ljava/util/function/ToIntFunction;)Ljava/util/Comparator;")
    @jstatic("comparingLong", "(Ljava/util/function/ToLongFunction;)Ljava/util/Comparator;")
    @jstatic("comparingDouble", "(Ljava/util/function/ToDoubleFunction;)Ljava/util/Comparator;")
    def comparingPrimitive(key):
        def compare(a, b):
            x, y = _apply_primitive(key, a), _apply_primitive(key, b)
            return (x > y) - (x < y)
        return _Lambda("compare", compare, Comparator)

    @jstatic("nullsFirst", "(Ljava/util/Comparator;)Ljava/util/Comparator;")
    def nullsFirst(comparator):
        return _Lambda("compare", lambda a, b: 0 if a is None and b is None else -1 if a is None else 1
                       if b is None else compare_with(comparator, a, b), Comparator)

    @jstatic("nullsLast", "(Ljava/util/Comparator;)Ljava/util/Comparator;")
    def nullsLast(comparator):
        return _Lambda("compare", lambda a, b: 0 if a is None and b is None else 1 if a is None else -1
                       if b is None else compare_with(comparator, a, b), Comparator)


def _apply_primitive(function, value):
    for name in ("applyAsInt", "applyAsLong", "applyAsDouble"):
        method = getattr(function, name, None)
        if method is not None:
            return method(value)
    runtime.throw_new("java.lang.AbstractMethodError", "applyAsInt")



def case_insensitive_order():
    return _Lambda("compare", lambda a, b: _StringImpl.compareToIgnoreCase(a, b), Comparator)
