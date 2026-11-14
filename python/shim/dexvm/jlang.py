"""java.lang for the vm: Object, Throwable and the errors the vm raises, String, StringBuilder, the boxes, Math, System

methods that need an exact overload carry @jmethod; the rest are found by name. a char argument or result of a
by-name method is a one character str, of a typed method a code unit int, as the descriptor says"""

import math
import struct
import sys
import threading
import time

from . import api, limits, runtime
from .api import caller_sensitive, host_class, jmethod, jstatic, register_value_type
from .format import utf16_units

_SENTINEL = object()


def jstr(text):
    """a python str as the java string of its utf-16 code units"""
    return utf16_units(text)


def pystr(text):
    """a java string as an ordinary python str; unpaired surrogates become U+FFFD"""
    if text.isascii():
        return text
    return text.encode("utf-16-le", "surrogatepass").decode("utf-16-le", "replace")


def utf8_bytes(text):
    return pystr(text).encode("utf-8")


@host_class("java.lang.Object")
class Object:
    __slots__ = ()

    @jmethod("<init>", "()V")
    def _object_init(self):
        return None

    def __str__(self):
        return self.toString()

    @jmethod("equals", "(Ljava/lang/Object;)Z")
    def equals(self, other):
        return 1 if self is other else 0

    @jmethod("hashCode", "()I")
    def hashCode(self):
        return id(self) >> 4 & 0x7FFFFFFF

    @jmethod("toString", "()Ljava/lang/String;")
    def toString(self):
        return "%s@%x" % (runtime.class_of(self).getName(), self.hashCode())

    @jmethod("getClass", "()Ljava/lang/Class;")
    def getClass(self):
        return runtime.class_of(self)

    @jmethod("notify", "()V")
    def notify(self):
        runtime.monitor_notify(self)

    @jmethod("notifyAll", "()V")
    def notifyAll(self):
        runtime.monitor_notify(self, True)

    @jmethod("wait", "()V")
    @jmethod("wait", "(J)V")
    def wait(self, timeout=0):
        runtime.monitor_wait(self, timeout)

    @jmethod("clone", "()Ljava/lang/Object;")
    def clone(self):
        raise runtime.make_throwable(api.lookup_host("java.lang.CloneNotSupportedException").py, None)

    @jmethod("finalize", "()V")
    def finalize(self):
        return None


@host_class("java.lang.Class", final=True)
class _ClassHolder:
    """java.lang.Class is JType itself, this class only carries the registration and the static methods"""

    @jstatic("forName", "(Ljava/lang/String;)Ljava/lang/Class;")
    @caller_sensitive
    def forName(name, caller=None):
        from . import classes
        return classes.class_for_name(name, caller)

    @jstatic("forName", "(Ljava/lang/String;ZLjava/lang/ClassLoader;)Ljava/lang/Class;")
    def forName_loader(name, initialize, loader):
        from . import classes, jloader
        return classes.class_for_name(name, None, jloader._vm_of(loader), initialize)


api._classes["java.lang.Class"].pytype = api.JType
api._by_pytype[api.JType] = api._classes["java.lang.Class"]


@host_class("java.lang.Cloneable", interface=True)
class Cloneable:
    __slots__ = ()


@host_class("java.io.Serializable", interface=True)
class Serializable:
    __slots__ = ()


@host_class("java.lang.Comparable", interface=True)
class Comparable:
    __slots__ = ()


@host_class("java.lang.CharSequence", interface=True)
class CharSequence:
    __slots__ = ()


@host_class("java.lang.Runnable", interface=True)
class Runnable:
    __slots__ = ()


@host_class("java.lang.AutoCloseable", interface=True)
class AutoCloseable:
    __slots__ = ()


@host_class("java.lang.Iterable", interface=True)
class Iterable:
    __slots__ = ()


@host_class("java.lang.Throwable")
class Throwable(Object, Exception):
    _message = None
    _cause = None
    _suppressed = None

    @jmethod("<init>", "()V")
    def _init0(self):
        self._message = None
        self._cause = None

    @jmethod("<init>", "(Ljava/lang/String;)V")
    def _init1(self, message):
        self._message = message
        self._cause = None

    @jmethod("<init>", "(Ljava/lang/String;Ljava/lang/Throwable;)V")
    def _init2(self, message, cause):
        self._message = message
        self._cause = cause

    @jmethod("<init>", "(Ljava/lang/Throwable;)V")
    def _init_cause(self, cause):
        self._message = None if cause is None else cause.toString()
        self._cause = cause

    @jmethod("<init>", "(Ljava/lang/String;Ljava/lang/Throwable;ZZ)V")
    def _init4(self, message, cause, suppression, writable):
        self._message = message
        self._cause = cause

    def __init__(self, message=None, cause=None):
        # a host caller builds an exception the python way
        Exception.__init__(self)
        self._message = message
        self._cause = cause

    def __str__(self):
        return self.toString()

    @jmethod("getMessage", "()Ljava/lang/String;")
    def getMessage(self):
        return self._message

    @jmethod("getLocalizedMessage", "()Ljava/lang/String;")
    def getLocalizedMessage(self):
        return self.getMessage()

    @jmethod("getCause", "()Ljava/lang/Throwable;")
    def getCause(self):
        return self._cause

    @jmethod("initCause", "(Ljava/lang/Throwable;)Ljava/lang/Throwable;")
    def initCause(self, cause):
        self._cause = cause
        return self

    @jmethod("toString", "()Ljava/lang/String;")
    def toString(self):
        message = self.getLocalizedMessage()
        name = runtime.class_of(self).getName()
        return name if message is None else name + ": " + message

    @jmethod("fillInStackTrace", "()Ljava/lang/Throwable;")
    def fillInStackTrace(self):
        return self

    @jmethod("getStackTrace", "()[Ljava/lang/StackTraceElement;")
    def getStackTrace(self):
        return runtime.new_array("[Ljava/lang/StackTraceElement;", 0)

    @jmethod("setStackTrace", "([Ljava/lang/StackTraceElement;)V")
    def setStackTrace(self, trace):
        return None

    @jmethod("addSuppressed", "(Ljava/lang/Throwable;)V")
    def addSuppressed(self, other):
        if self._suppressed is None:
            self._suppressed = []
        self._suppressed.append(other)

    @jmethod("getSuppressed", "()[Ljava/lang/Throwable;")
    def getSuppressed(self):
        array = runtime.new_array("[Ljava/lang/Throwable;", 0)
        array.extend(self._suppressed or ())
        return array

    @jmethod("printStackTrace", "()V")
    def printStackTrace(self):
        System.err.println(self.toString())
        cause = self._cause
        while cause is not None:
            System.err.println("Caused by: " + cause.toString())
            cause = cause.getCause()


@host_class("java.lang.StackTraceElement")
class StackTraceElement(Object):
    """a frame of a trace: the vm keeps no frames of java methods, so a trace is empty; the class is here for programs that build and read one"""

    def __init__(self, declaring_class="", method="", file=None, line=-1):
        self._c, self._m, self._f, self._l = declaring_class, method, file, line

    @jmethod("<init>", "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;I)V")
    def _init(self, declaring_class, method, file, line):
        StackTraceElement.__init__(self, declaring_class, method, file, line)

    @jmethod("getClassName", "()Ljava/lang/String;")
    def getClassName(self):
        return self._c

    @jmethod("getMethodName", "()Ljava/lang/String;")
    def getMethodName(self):
        return self._m

    @jmethod("getFileName", "()Ljava/lang/String;")
    def getFileName(self):
        return self._f

    @jmethod("getLineNumber", "()I")
    def getLineNumber(self):
        return self._l

    @jmethod("toString", "()Ljava/lang/String;")
    def toString(self):
        return "%s.%s(%s)" % (self._c, self._m, "Unknown Source" if self._f is None else (
            self._f if self._l < 0 else "%s:%d" % (self._f, self._l)))


# (name, parent) in an order that defines parents first
_EXCEPTIONS = """
java.lang.Exception java.lang.Throwable
java.lang.Error java.lang.Throwable
java.lang.RuntimeException java.lang.Exception
java.lang.ArithmeticException java.lang.RuntimeException
java.lang.ArrayStoreException java.lang.RuntimeException
java.lang.ClassCastException java.lang.RuntimeException
java.lang.IllegalArgumentException java.lang.RuntimeException
java.lang.IllegalMonitorStateException java.lang.RuntimeException
java.lang.IllegalStateException java.lang.RuntimeException
java.lang.IllegalThreadStateException java.lang.IllegalArgumentException
java.lang.NumberFormatException java.lang.IllegalArgumentException
java.lang.IndexOutOfBoundsException java.lang.RuntimeException
java.lang.ArrayIndexOutOfBoundsException java.lang.IndexOutOfBoundsException
java.lang.StringIndexOutOfBoundsException java.lang.IndexOutOfBoundsException
java.lang.NegativeArraySizeException java.lang.RuntimeException
java.lang.NullPointerException java.lang.RuntimeException
java.lang.SecurityException java.lang.RuntimeException
java.lang.UnsupportedOperationException java.lang.RuntimeException
java.lang.invoke.WrongMethodTypeException java.lang.RuntimeException
java.lang.EnumConstantNotPresentException java.lang.RuntimeException
java.lang.annotation.IncompleteAnnotationException java.lang.RuntimeException
java.util.regex.PatternSyntaxException java.lang.IllegalArgumentException
java.util.IllegalFormatException java.lang.IllegalArgumentException
java.util.MissingFormatArgumentException java.util.IllegalFormatException
java.util.UnknownFormatConversionException java.util.IllegalFormatException
java.util.IllegalFormatConversionException java.util.IllegalFormatException
java.util.IllegalFormatCodePointException java.util.IllegalFormatException
java.util.IllegalFormatPrecisionException java.util.IllegalFormatException
java.util.MissingFormatWidthException java.util.IllegalFormatException
java.util.IllegalFormatFlagsException java.util.IllegalFormatException
java.util.FormatFlagsConversionMismatchException java.util.IllegalFormatException
java.io.UTFDataFormatException java.io.IOException
java.util.zip.DataFormatException java.lang.Exception
java.util.zip.ZipException java.io.IOException
java.lang.TypeNotPresentException java.lang.RuntimeException
java.lang.CloneNotSupportedException java.lang.Exception
java.lang.InterruptedException java.lang.Exception
java.lang.ReflectiveOperationException java.lang.Exception
java.lang.ClassNotFoundException java.lang.ReflectiveOperationException
java.lang.IllegalAccessException java.lang.ReflectiveOperationException
java.lang.InstantiationException java.lang.ReflectiveOperationException
java.lang.NoSuchFieldException java.lang.ReflectiveOperationException
java.lang.NoSuchMethodException java.lang.ReflectiveOperationException
java.lang.AssertionError java.lang.Error
java.lang.LinkageError java.lang.Error
java.lang.ClassCircularityError java.lang.LinkageError
java.lang.ClassFormatError java.lang.LinkageError
java.lang.UnsupportedClassVersionError java.lang.ClassFormatError
java.lang.ExceptionInInitializerError java.lang.LinkageError
java.lang.BootstrapMethodError java.lang.LinkageError
java.lang.invoke.LambdaConversionException java.lang.Exception
java.lang.invoke.StringConcatException java.lang.Exception
java.lang.IncompatibleClassChangeError java.lang.LinkageError
java.lang.AbstractMethodError java.lang.IncompatibleClassChangeError
java.lang.IllegalAccessError java.lang.IncompatibleClassChangeError
java.lang.InstantiationError java.lang.IncompatibleClassChangeError
java.lang.NoSuchFieldError java.lang.IncompatibleClassChangeError
java.lang.NoSuchMethodError java.lang.IncompatibleClassChangeError
java.lang.NoClassDefFoundError java.lang.LinkageError
java.lang.UnsatisfiedLinkError java.lang.LinkageError
java.lang.VerifyError java.lang.LinkageError
java.lang.VirtualMachineError java.lang.Error
java.lang.InternalError java.lang.VirtualMachineError
java.lang.OutOfMemoryError java.lang.VirtualMachineError
java.lang.StackOverflowError java.lang.VirtualMachineError
java.lang.UnknownError java.lang.VirtualMachineError
java.lang.ThreadDeath java.lang.Error
java.io.IOException java.lang.Exception
java.io.FileNotFoundException java.io.IOException
java.io.EOFException java.io.IOException
java.io.UnsupportedEncodingException java.io.IOException
java.io.UncheckedIOException java.lang.RuntimeException
java.util.NoSuchElementException java.lang.RuntimeException
java.util.InputMismatchException java.util.NoSuchElementException
java.util.ConcurrentModificationException java.lang.RuntimeException
java.util.EmptyStackException java.lang.RuntimeException
java.util.MissingResourceException java.lang.RuntimeException
java.util.concurrent.ExecutionException java.lang.Exception
java.util.concurrent.TimeoutException java.lang.Exception
java.util.concurrent.CancellationException java.lang.IllegalStateException
java.util.concurrent.RejectedExecutionException java.lang.RuntimeException
java.util.concurrent.CompletionException java.lang.RuntimeException
java.util.concurrent.BrokenBarrierException java.lang.Exception
java.lang.reflect.InvocationTargetException java.lang.ReflectiveOperationException
java.lang.reflect.UndeclaredThrowableException java.lang.RuntimeException
java.lang.reflect.MalformedParametersException java.lang.RuntimeException
java.net.MalformedURLException java.io.IOException
java.net.SocketException java.io.IOException
java.net.SocketTimeoutException java.io.IOException
java.net.UnknownHostException java.io.IOException
java.net.ConnectException java.net.SocketException
java.security.GeneralSecurityException java.lang.Exception
java.security.NoSuchAlgorithmException java.security.GeneralSecurityException
java.security.InvalidKeyException java.security.GeneralSecurityException
java.security.DigestException java.security.GeneralSecurityException
java.security.SignatureException java.security.GeneralSecurityException
java.nio.BufferOverflowException java.lang.RuntimeException
java.nio.BufferUnderflowException java.lang.RuntimeException
java.nio.charset.CharacterCodingException java.io.IOException
java.nio.charset.UnsupportedCharsetException java.lang.IllegalArgumentException
java.time.DateTimeException java.lang.RuntimeException
"""


def _define_exceptions():
    pending = [line.split() for line in _EXCEPTIONS.strip().splitlines()]
    while pending:
        waiting = []
        for name, parent in pending:
            parent_host = api.lookup_host(parent)
            if parent_host is None:
                waiting.append((name, parent))
                continue
            py = type(name.rsplit(".", 1)[1], (parent_host.py,), {"__module__": __name__})
            host_class(name)(py)
        if len(waiting) == len(pending):
            raise RuntimeError("exception parents are missing: %r" % waiting)
        pending = waiting


_define_exceptions()


@host_class("java.lang.Number")
class Number(Object):
    __slots__ = ()


class _Box(Number):
    __slots__ = ("value",)

    def __init__(self, value):
        self.value = value

    def __eq__(self, other):
        return self is other

    def __ne__(self, other):
        return self is not other

    __hash__ = object.__hash__

    def intValue(self):
        return runtime.wrap32(int(self.value)) if not isinstance(self.value, float) else runtime.d2i(self.value)

    def longValue(self):
        return int(self.value) if not isinstance(self.value, float) else runtime.d2l(self.value)

    def floatValue(self):
        return runtime.f32(float(self.value))

    def doubleValue(self):
        return float(self.value)

    def shortValue(self):
        return (self.intValue() + 32768 & 0xFFFF) - 32768

    def byteValue(self):
        return (self.intValue() + 128 & 0xFF) - 128


@host_class("java.lang.Integer", final=True)
class Integer(_Box):
    MAX_VALUE = runtime.INT_MAX
    MIN_VALUE = runtime.INT_MIN
    SIZE = 32
    BYTES = 4
    _cache = {}

    @jmethod("<init>", "(I)V")
    def _init(self, value):
        self.value = value

    @jstatic("valueOf", "(I)Ljava/lang/Integer;")
    def valueOf(value):
        if -128 <= value <= 127:
            found = Integer._cache.get(value)
            if found is None:
                found = Integer._cache[value] = Integer(value)
            return found
        return Integer(value)

    @jstatic("valueOf", "(Ljava/lang/String;)Ljava/lang/Integer;")
    def valueOf_str(text):
        return Integer.valueOf(Integer.parseInt(text))

    @jstatic("valueOf", "(Ljava/lang/String;I)Ljava/lang/Integer;")
    def valueOf_radix(text, radix):
        return Integer.valueOf(Integer.parseInt(text, radix))

    @jstatic("parseInt", "(Ljava/lang/String;)I")
    @jstatic("parseInt", "(Ljava/lang/String;I)I")
    def parseInt(text, radix=10):
        return _parse_integer(text, radix, runtime.INT_MIN, runtime.INT_MAX)

    @jstatic("toString", "(I)Ljava/lang/String;")
    def toString_int(value):
        return str(value)

    @jstatic("toString", "(II)Ljava/lang/String;")
    def toString_radix(value, radix):
        return _to_radix(value, radix)

    @jstatic("toHexString", "(I)Ljava/lang/String;")
    def toHexString(value):
        return "%x" % (value & 0xFFFFFFFF)

    @jstatic("toBinaryString", "(I)Ljava/lang/String;")
    def toBinaryString(value):
        return bin(value & 0xFFFFFFFF)[2:]

    @jstatic("toOctalString", "(I)Ljava/lang/String;")
    def toOctalString(value):
        return "%o" % (value & 0xFFFFFFFF)

    @jstatic("compare", "(II)I")
    def compare(a, b):
        return (a > b) - (a < b)

    @jstatic("signum", "(I)I")
    def signum(a):
        return (a > 0) - (a < 0)

    @jstatic("bitCount", "(I)I")
    def bitCount(a):
        return bin(a & 0xFFFFFFFF).count("1")

    @jstatic("hashCode", "(I)I")
    def hashCode_int(a):
        return a

    @jstatic("max", "(II)I")
    def max(a, b):
        return a if a > b else b

    @jstatic("min", "(II)I")
    def min(a, b):
        return a if a < b else b

    @jstatic("sum", "(II)I")
    def sum(a, b):
        return runtime.wrap32(a + b)

    @jstatic("reverse", "(I)I")
    def reverse(a):
        return runtime.wrap32(int(format(a & 0xFFFFFFFF, "032b")[::-1], 2))

    @jstatic("numberOfLeadingZeros", "(I)I")
    def numberOfLeadingZeros(a):
        return 32 - (a & 0xFFFFFFFF).bit_length()

    @jstatic("numberOfTrailingZeros", "(I)I")
    def numberOfTrailingZeros(a):
        a &= 0xFFFFFFFF
        return 32 if a == 0 else (a & -a).bit_length() - 1

    @jstatic("highestOneBit", "(I)I")
    def highestOneBit(a):
        a &= 0xFFFFFFFF
        return 0 if a == 0 else runtime.wrap32(1 << (a.bit_length() - 1))

    @jstatic("lowestOneBit", "(I)I")
    def lowestOneBit(a):
        return runtime.wrap32(a & -a)

    @jstatic("rotateLeft", "(II)I")
    def rotateLeft(a, n):
        n &= 31
        a &= 0xFFFFFFFF
        return runtime.wrap32((a << n | a >> (32 - n)) & 0xFFFFFFFF)

    @jstatic("rotateRight", "(II)I")
    def rotateRight(a, n):
        return Integer.rotateLeft(a, -n & 31)

    @jstatic("reverseBytes", "(I)I")
    def reverseBytes(a):
        return runtime.wrap32(int.from_bytes((a & 0xFFFFFFFF).to_bytes(4, "little"), "big"))

    @jmethod("equals", "(Ljava/lang/Object;)Z")
    def equals(self, other):
        return 1 if isinstance(other, Integer) and other.value == self.value else 0

    @jmethod("hashCode", "()I")
    def hashCode(self):
        return self.value

    @jmethod("toString", "()Ljava/lang/String;")
    def toString(self):
        return str(self.value)

    @jmethod("compareTo", "(Ljava/lang/Integer;)I")
    @jmethod("compareTo", "(Ljava/lang/Object;)I")
    def compareTo(self, other):
        return (self.value > other.value) - (self.value < other.value)

    @jmethod("intValue", "()I")
    def intValue(self):
        return self.value


@host_class("java.lang.Long", final=True)
class Long(_Box):
    MAX_VALUE = runtime.LONG_MAX
    MIN_VALUE = runtime.LONG_MIN
    SIZE = 64
    BYTES = 8
    _cache = {}

    @jmethod("<init>", "(J)V")
    def _init(self, value):
        self.value = value

    @jstatic("valueOf", "(J)Ljava/lang/Long;")
    def valueOf(value):
        if -128 <= value <= 127:
            found = Long._cache.get(value)
            if found is None:
                found = Long._cache[value] = Long(value)
            return found
        return Long(value)

    @jstatic("valueOf", "(Ljava/lang/String;)Ljava/lang/Long;")
    def valueOf_str(text):
        return Long.valueOf(Long.parseLong(text))

    @jstatic("parseLong", "(Ljava/lang/String;)J")
    @jstatic("parseLong", "(Ljava/lang/String;I)J")
    def parseLong(text, radix=10):
        return _parse_integer(text, radix, runtime.LONG_MIN, runtime.LONG_MAX)

    @jstatic("toString", "(J)Ljava/lang/String;")
    def toString_long(value):
        return str(value)

    @jstatic("toString", "(JI)Ljava/lang/String;")
    def toString_radix(value, radix):
        return _to_radix(value, radix)

    @jstatic("toHexString", "(J)Ljava/lang/String;")
    def toHexString(value):
        return "%x" % (value & 0xFFFFFFFFFFFFFFFF)

    @jstatic("toBinaryString", "(J)Ljava/lang/String;")
    def toBinaryString(value):
        return bin(value & 0xFFFFFFFFFFFFFFFF)[2:]

    @jstatic("compare", "(JJ)I")
    def compare(a, b):
        return (a > b) - (a < b)

    @jstatic("signum", "(J)I")
    def signum(a):
        return (a > 0) - (a < 0)

    @jstatic("bitCount", "(J)I")
    def bitCount(a):
        return bin(a & 0xFFFFFFFFFFFFFFFF).count("1")

    @jstatic("hashCode", "(J)I")
    def hashCode_long(value):
        return runtime.wrap32(value ^ (value & 0xFFFFFFFFFFFFFFFF) >> 32)

    @jstatic("numberOfLeadingZeros", "(J)I")
    def numberOfLeadingZeros(a):
        return 64 - (a & 0xFFFFFFFFFFFFFFFF).bit_length()

    @jstatic("numberOfTrailingZeros", "(J)I")
    def numberOfTrailingZeros(a):
        a &= 0xFFFFFFFFFFFFFFFF
        return 64 if a == 0 else (a & -a).bit_length() - 1

    @jstatic("max", "(JJ)J")
    def max(a, b):
        return a if a > b else b

    @jstatic("min", "(JJ)J")
    def min(a, b):
        return a if a < b else b

    @jstatic("sum", "(JJ)J")
    def sum(a, b):
        return runtime.wrap64(a + b)

    @jmethod("equals", "(Ljava/lang/Object;)Z")
    def equals(self, other):
        return 1 if isinstance(other, Long) and other.value == self.value else 0

    @jmethod("hashCode", "()I")
    def hashCode(self):
        return Long.hashCode_long(self.value)

    @jmethod("toString", "()Ljava/lang/String;")
    def toString(self):
        return str(self.value)

    @jmethod("compareTo", "(Ljava/lang/Long;)I")
    @jmethod("compareTo", "(Ljava/lang/Object;)I")
    def compareTo(self, other):
        return (self.value > other.value) - (self.value < other.value)

    @jmethod("longValue", "()J")
    def longValue(self):
        return self.value


@host_class("java.lang.Short", final=True)
class Short(_Box):
    MAX_VALUE = 32767
    MIN_VALUE = -32768

    @jmethod("<init>", "(S)V")
    def _init(self, value):
        self.value = value

    @jstatic("valueOf", "(S)Ljava/lang/Short;")
    def valueOf(value):
        return Short(value)

    @jstatic("valueOf", "(Ljava/lang/String;)Ljava/lang/Short;")
    def valueOf_str(text):
        return Short(Short.parseShort(text))

    @jstatic("parseShort", "(Ljava/lang/String;)S")
    def parseShort(text):
        return _parse_integer(text, 10, -32768, 32767)

    @jstatic("toString", "(S)Ljava/lang/String;")
    def toString_short(value):
        return str(value)

    @jmethod("equals", "(Ljava/lang/Object;)Z")
    def equals(self, other):
        return 1 if isinstance(other, Short) and other.value == self.value else 0

    @jmethod("hashCode", "()I")
    def hashCode(self):
        return self.value

    @jmethod("toString", "()Ljava/lang/String;")
    def toString(self):
        return str(self.value)


@host_class("java.lang.Byte", final=True)
class Byte(_Box):
    MAX_VALUE = 127
    MIN_VALUE = -128

    @jmethod("<init>", "(B)V")
    def _init(self, value):
        self.value = value

    @jstatic("valueOf", "(B)Ljava/lang/Byte;")
    def valueOf(value):
        return Byte(value)

    @jstatic("valueOf", "(Ljava/lang/String;)Ljava/lang/Byte;")
    def valueOf_str(text):
        return Byte(Byte.parseByte(text))

    @jstatic("parseByte", "(Ljava/lang/String;)B")
    def parseByte(text):
        return _parse_integer(text, 10, -128, 127)

    @jstatic("toString", "(B)Ljava/lang/String;")
    def toString_byte(value):
        return str(value)

    @jstatic("toUnsignedInt", "(B)I")
    def toUnsignedInt(value):
        return value & 0xFF

    @jmethod("equals", "(Ljava/lang/Object;)Z")
    def equals(self, other):
        return 1 if isinstance(other, Byte) and other.value == self.value else 0

    @jmethod("hashCode", "()I")
    def hashCode(self):
        return self.value

    @jmethod("toString", "()Ljava/lang/String;")
    def toString(self):
        return str(self.value)


@host_class("java.lang.Character", final=True)
class Character(Object):
    __slots__ = ("value",)
    MAX_VALUE = 0xFFFF
    MIN_VALUE = 0

    @jmethod("<init>", "(C)V")
    def _init(self, value):
        self.value = value

    @jstatic("valueOf", "(C)Ljava/lang/Character;")
    def valueOf(value):
        box = Character.__new__(Character)
        box.value = value
        return box

    @jstatic("isDigit", "(C)Z")
    def isDigit(c):
        return 1 if chr(c).isdecimal() else 0

    @jstatic("isLetter", "(C)Z")
    def isLetter(c):
        return 1 if chr(c).isalpha() else 0

    @jstatic("isLetterOrDigit", "(C)Z")
    def isLetterOrDigit(c):
        return 1 if chr(c).isalnum() else 0

    @jstatic("isWhitespace", "(C)Z")
    def isWhitespace(c):
        return 1 if chr(c) in " \t\n\x0b\x0c\r\x1c\x1d\x1e\x1f" or (c > 127 and chr(c).isspace() and c not in (0xA0, 0x2007, 0x202F)) else 0

    @jstatic("isUpperCase", "(C)Z")
    def isUpperCase(c):
        return 1 if chr(c).isupper() else 0

    @jstatic("isLowerCase", "(C)Z")
    def isLowerCase(c):
        return 1 if chr(c).islower() else 0

    @jstatic("toUpperCase", "(C)C")
    def toUpperCase(c):
        up = chr(c).upper()
        return ord(up) if len(up) == 1 else c

    @jstatic("toLowerCase", "(C)C")
    def toLowerCase(c):
        low = chr(c).lower()
        return ord(low) if len(low) == 1 else c

    @jstatic("toString", "(C)Ljava/lang/String;")
    def toString_char(c):
        return chr(c)

    @jstatic("getNumericValue", "(C)I")
    def getNumericValue(c):
        ch = chr(c)
        if ch.isdecimal():
            return int(ch)
        if "a" <= ch.lower() <= "z" and ch.isascii():
            return ord(ch.lower()) - 87
        return -1

    @jstatic("digit", "(CI)I")
    def digit(c, radix):
        value = Character.getNumericValue(c)
        return value if 0 <= value < radix else -1

    @jstatic("forDigit", "(II)C")
    def forDigit(digit, radix):
        if digit < 0 or digit >= radix or not 2 <= radix <= 36:
            return 0
        return ord("0123456789abcdefghijklmnopqrstuvwxyz"[digit])

    @jstatic("compare", "(CC)I")
    def compare(a, b):
        return a - b

    @jstatic("hashCode", "(C)I")
    def hashCode_char(c):
        return c

    @jmethod("charValue", "()C")
    def charValue(self):
        return self.value

    @jmethod("equals", "(Ljava/lang/Object;)Z")
    def equals(self, other):
        return 1 if isinstance(other, Character) and other.value == self.value else 0

    @jmethod("hashCode", "()I")
    def hashCode(self):
        return self.value

    @jmethod("toString", "()Ljava/lang/String;")
    def toString(self):
        return chr(self.value)


@host_class("java.lang.Boolean", final=True)
class Boolean(Object):
    __slots__ = ("value",)

    @jmethod("<init>", "(Z)V")
    def _init(self, value):
        self.value = value

    @jstatic("valueOf", "(Z)Ljava/lang/Boolean;")
    def valueOf(value):
        return Boolean.TRUE if value else Boolean.FALSE

    @jstatic("valueOf", "(Ljava/lang/String;)Ljava/lang/Boolean;")
    def valueOf_str(text):
        return Boolean.TRUE if Boolean.parseBoolean(text) else Boolean.FALSE

    @jstatic("parseBoolean", "(Ljava/lang/String;)Z")
    def parseBoolean(text):
        return 1 if text is not None and text.lower() == "true" else 0

    @jstatic("toString", "(Z)Ljava/lang/String;")
    def toString_bool(value):
        return "true" if value else "false"

    @jstatic("compare", "(ZZ)I")
    def compare(a, b):
        return (a > b) - (a < b)

    @jstatic("hashCode", "(Z)I")
    def hashCode_bool(value):
        return 1231 if value else 1237

    @jmethod("booleanValue", "()Z")
    def booleanValue(self):
        return self.value

    @jmethod("equals", "(Ljava/lang/Object;)Z")
    def equals(self, other):
        return 1 if isinstance(other, Boolean) and other.value == self.value else 0

    @jmethod("hashCode", "()I")
    def hashCode(self):
        return 1231 if self.value else 1237

    @jmethod("toString", "()Ljava/lang/String;")
    def toString(self):
        return "true" if self.value else "false"


Boolean.TRUE = Boolean.__new__(Boolean)
Boolean.TRUE.value = 1
Boolean.FALSE = Boolean.__new__(Boolean)
Boolean.FALSE.value = 0


def float_to_string(value, single):
    """Float.toString and Double.toString: the shortest digits that read back as the same value, laid out as java does"""
    if value != value:
        return "NaN"
    if value in (math.inf, -math.inf):
        return "Infinity" if value > 0 else "-Infinity"
    if value == 0:
        return "-0.0" if math.copysign(1.0, value) < 0 else "0.0"
    sign = "-" if value < 0 else ""
    magnitude = abs(value)
    if single:
        for precision in range(0, 10):
            text = "%.*e" % (precision, magnitude)
            if runtime.f32(float(text)) == magnitude:
                break
    else:
        text = repr(magnitude)
    if len(text.lower().split("e")[0].replace(".", "").lstrip("0")) == 1:
        # one shortest digit: java prints the two digit decimal nearest to the exact value (4.9E-324, not 5.0E-324)
        text = "%.1e" % magnitude
    if "e" in text or "E" in text:
        mantissa, exponent = text.lower().split("e")
        exponent = int(exponent)
    else:
        mantissa, exponent = text, 0
    integer, _, fraction = mantissa.partition(".")
    digits = integer + fraction
    point = len(integer) + exponent
    stripped = digits.lstrip("0")
    point -= len(digits) - len(stripped)
    digits = stripped.rstrip("0") or "0"
    scientific = point - 1
    if -3 <= scientific < 7:
        if point <= 0:
            body = "0." + "0" * -point + digits
        elif point >= len(digits):
            body = digits + "0" * (point - len(digits)) + ".0"
        else:
            body = digits[:point] + "." + digits[point:]
    else:
        body = digits[0] + "." + (digits[1:] or "0") + "E" + str(scientific)
    return sign + body


def _parse_integer(text, radix, low, high):
    if text is None:
        runtime.throw_new("java.lang.NumberFormatException", "Cannot parse null string")
    if not 2 <= radix <= 36:
        runtime.throw_new("java.lang.NumberFormatException", "radix %d out of range" % radix)
    body = text[1:] if text[:1] in "+-" else text
    if not body or not all(c.isascii() and c.isalnum() for c in body):
        runtime.throw_new("java.lang.NumberFormatException", 'For input string: "%s"' % text)
    try:
        value = int(text, radix)
    except ValueError:
        runtime.throw_new("java.lang.NumberFormatException", 'For input string: "%s"' % text)
    if not low <= value <= high:
        runtime.throw_new("java.lang.NumberFormatException", 'For input string: "%s"' % text)
    return value


def _to_radix(value, radix):
    if not 2 <= radix <= 36:
        radix = 10
    if value == 0:
        return "0"
    digits = "0123456789abcdefghijklmnopqrstuvwxyz"
    out = []
    number = abs(value)
    while number:
        number, rest = divmod(number, radix)
        out.append(digits[rest])
    return ("-" if value < 0 else "") + "".join(reversed(out))


@host_class("java.lang.Float", final=True)
class Float(_Box):
    MAX_VALUE = struct.unpack("<f", struct.pack("<I", 0x7F7FFFFF))[0]
    MIN_VALUE = struct.unpack("<f", struct.pack("<I", 1))[0]
    POSITIVE_INFINITY = math.inf
    NEGATIVE_INFINITY = -math.inf
    NaN = math.nan

    @jmethod("<init>", "(F)V")
    def _init(self, value):
        self.value = value

    @jstatic("valueOf", "(F)Ljava/lang/Float;")
    def valueOf(value):
        return Float(value)

    @jstatic("valueOf", "(Ljava/lang/String;)Ljava/lang/Float;")
    def valueOf_str(text):
        return Float(runtime.f32(_parse_float(text)))

    @jstatic("parseFloat", "(Ljava/lang/String;)F")
    def parseFloat(text):
        return runtime.f32(_parse_float(text))

    @jstatic("toString", "(F)Ljava/lang/String;")
    def toString_float(value):
        return float_to_string(value, True)

    @jstatic("floatToIntBits", "(F)I")
    def floatToIntBits(value):
        return 0x7FC00000 if value != value else runtime.float_bits(value)

    @jstatic("floatToRawIntBits", "(F)I")
    def floatToRawIntBits(value):
        return runtime.float_bits(value)

    @jstatic("intBitsToFloat", "(I)F")
    def intBitsToFloat(bits):
        return runtime.bits_to_float(bits)

    @jstatic("isNaN", "(F)Z")
    def isNaN_static(value):
        return 1 if value != value else 0

    @jstatic("isInfinite", "(F)Z")
    def isInfinite_static(value):
        return 1 if math.isinf(value) else 0

    @jstatic("compare", "(FF)I")
    def compare(a, b):
        return _compare_double(a, b)

    @jstatic("max", "(FF)F")
    def max(a, b):
        return Math.max_double(a, b)

    @jstatic("min", "(FF)F")
    def min(a, b):
        return Math.min_double(a, b)

    @jmethod("isNaN", "()Z")
    def isNaN(self):
        return 1 if self.value != self.value else 0

    @jmethod("floatValue", "()F")
    def floatValue(self):
        return self.value

    @jmethod("equals", "(Ljava/lang/Object;)Z")
    def equals(self, other):
        return 1 if isinstance(other, Float) and Float.floatToIntBits(other.value) == Float.floatToIntBits(self.value) else 0

    @jmethod("hashCode", "()I")
    def hashCode(self):
        return Float.floatToIntBits(self.value)

    @jmethod("toString", "()Ljava/lang/String;")
    def toString(self):
        return float_to_string(self.value, True)


@host_class("java.lang.Double", final=True)
class Double(_Box):
    MAX_VALUE = sys.float_info.max
    MIN_VALUE = 5e-324
    POSITIVE_INFINITY = math.inf
    NEGATIVE_INFINITY = -math.inf
    NaN = math.nan

    @jmethod("<init>", "(D)V")
    def _init(self, value):
        self.value = value

    @jstatic("valueOf", "(D)Ljava/lang/Double;")
    def valueOf(value):
        return Double(value)

    @jstatic("valueOf", "(Ljava/lang/String;)Ljava/lang/Double;")
    def valueOf_str(text):
        return Double(_parse_float(text))

    @jstatic("parseDouble", "(Ljava/lang/String;)D")
    def parseDouble(text):
        return _parse_float(text)

    @jstatic("toString", "(D)Ljava/lang/String;")
    def toString_double(value):
        return float_to_string(value, False)

    @jstatic("doubleToLongBits", "(D)J")
    def doubleToLongBits(value):
        return 0x7FF8000000000000 if value != value else runtime.double_bits(value)

    @jstatic("doubleToRawLongBits", "(D)J")
    def doubleToRawLongBits(value):
        return runtime.double_bits(value)

    @jstatic("longBitsToDouble", "(J)D")
    def longBitsToDouble(bits):
        return runtime.bits_to_double(bits)

    @jstatic("isNaN", "(D)Z")
    def isNaN_static(value):
        return 1 if value != value else 0

    @jstatic("isInfinite", "(D)Z")
    def isInfinite_static(value):
        return 1 if math.isinf(value) else 0

    @jstatic("compare", "(DD)I")
    def compare(a, b):
        return _compare_double(a, b)

    @jstatic("max", "(DD)D")
    def max(a, b):
        return Math.max_double(a, b)

    @jstatic("min", "(DD)D")
    def min(a, b):
        return Math.min_double(a, b)

    @jmethod("isNaN", "()Z")
    def isNaN(self):
        return 1 if self.value != self.value else 0

    @jmethod("doubleValue", "()D")
    def doubleValue(self):
        return self.value

    @jmethod("equals", "(Ljava/lang/Object;)Z")
    def equals(self, other):
        return 1 if isinstance(other, Double) and Double.doubleToLongBits(other.value) == Double.doubleToLongBits(self.value) else 0

    @jmethod("hashCode", "()I")
    def hashCode(self):
        bits = Double.doubleToLongBits(self.value)
        return runtime.wrap32(bits ^ (bits & 0xFFFFFFFFFFFFFFFF) >> 32)

    @jmethod("toString", "()Ljava/lang/String;")
    def toString(self):
        return float_to_string(self.value, False)


def _parse_float(text):
    if text is None:
        runtime.npe()
    stripped = text.strip()
    candidate = stripped.rstrip("fFdD") if stripped[-1:] in "fFdD" and stripped[:-1] else stripped
    lowered = candidate.lower().lstrip("+-")
    if lowered in ("nan", "inf", "infinity") and lowered not in ("nan", "infinity"):
        runtime.throw_new("java.lang.NumberFormatException", 'For input string: "%s"' % text)
    if lowered == "infinity":
        return -math.inf if candidate.startswith("-") else math.inf
    if lowered == "nan":
        return math.nan
    try:
        return float(candidate)
    except ValueError:
        runtime.throw_new("java.lang.NumberFormatException",
                          'empty String' if not stripped else 'For input string: "%s"' % text)


def _compare_double(a, b):
    if a < b:
        return -1
    if a > b:
        return 1
    bits_a = runtime.double_bits(a) if a == a else 0x7FF8000000000000
    bits_b = runtime.double_bits(b) if b == b else 0x7FF8000000000000
    return (bits_a > bits_b) - (bits_a < bits_b)


class _StringImpl:
    """the methods of java.lang.String over a python str of utf-16 code units; self is the str"""

    @staticmethod
    def length(self):
        return len(self)

    @staticmethod
    def isEmpty(self):
        return 0 if self else 1

    @staticmethod
    def charAt(self, index):
        if index < 0 or index >= len(self):
            runtime.throw_new("java.lang.StringIndexOutOfBoundsException",
                              "length=%d; index=%d" % (len(self), index))
        return ord(self[index])

    @staticmethod
    def codePointAt(self, index):
        if index < 0 or index >= len(self):
            runtime.throw_new("java.lang.StringIndexOutOfBoundsException",
                              "length=%d; index=%d" % (len(self), index))
        high = ord(self[index])
        if 0xD800 <= high < 0xDC00 and index + 1 < len(self) and 0xDC00 <= ord(self[index + 1]) < 0xE000:
            return 0x10000 + (high - 0xD800 << 10) + ord(self[index + 1]) - 0xDC00
        return high

    @staticmethod
    def substring(self, begin, end=None):
        if end is None:
            end = len(self)
        if begin < 0 or end > len(self) or begin > end:
            runtime.throw_new("java.lang.StringIndexOutOfBoundsException",
                              "length=%d; regionStart=%d; regionLength=%d" % (len(self), begin, end - begin))
        return self[begin:end]

    subSequence = substring

    @staticmethod
    def concat(self, other):
        return self + other

    @staticmethod
    def equals(self, other):
        return 1 if isinstance(other, str) and self == other else 0

    @staticmethod
    def equalsIgnoreCase(self, other):
        return 1 if other is not None and len(self) == len(other) and self.upper().lower() == other.upper().lower() else 0

    @staticmethod
    def hashCode(self):
        h = 0
        for char in self:
            h = (31 * h + ord(char)) & 0xFFFFFFFF
        return h - 0x100000000 if h & 0x80000000 else h

    @staticmethod
    def toString(self):
        return self

    @staticmethod
    def intern(self):
        return sys.intern(self)

    @staticmethod
    def compareTo(self, other):
        for a, b in zip(self, other):
            if a != b:
                return ord(a) - ord(b)
        return len(self) - len(other)

    @staticmethod
    def compareToIgnoreCase(self, other):
        return _StringImpl.compareTo(self.upper().lower(), other.upper().lower())

    @staticmethod
    def indexOf(self, target, start=0):
        if not isinstance(target, str):
            target = chr(target) if target < 0x10000 else jstr(chr(target))
        return self.find(target, max(start, 0))

    @staticmethod
    def lastIndexOf(self, target, start=None):
        if not isinstance(target, str):
            target = chr(target) if target < 0x10000 else jstr(chr(target))
        if start is None:
            return self.rfind(target)
        if start < 0:
            return -1
        return self.rfind(target, 0, start + len(target))

    @staticmethod
    def contains(self, other):
        return 1 if _cs(other) in self else 0

    @staticmethod
    def startsWith(self, prefix, offset=0):
        return 1 if offset >= 0 and self.startswith(prefix, offset) else 0

    @staticmethod
    def chars(self):
        from .jstream import BaseStream
        return BaseStream.from_items([ord(c) for c in self], "int")

    @staticmethod
    def codePoints(self):
        from .jstream import BaseStream
        points = []
        index = 0
        while index < len(self):
            high = ord(self[index])
            if 0xD800 <= high < 0xDC00 and index + 1 < len(self) and 0xDC00 <= ord(self[index + 1]) < 0xE000:
                points.append(0x10000 + ((high - 0xD800) << 10) + (ord(self[index + 1]) - 0xDC00))
                index += 2
            else:
                points.append(high)
                index += 1
        return BaseStream.from_items(points, "int")

    @staticmethod
    def endsWith(self, suffix):
        return 1 if self.endswith(suffix) else 0

    @staticmethod
    def trim(self):
        start = 0
        end = len(self)
        while start < end and ord(self[start]) <= 32:
            start += 1
        while end > start and ord(self[end - 1]) <= 32:
            end -= 1
        return self[start:end]

    @staticmethod
    def toUpperCase(self, locale=None):
        return jstr(pystr(self).upper())

    @staticmethod
    def toLowerCase(self, locale=None):
        return jstr(pystr(self).lower())

    @staticmethod
    def replace(self, old, new):
        if not isinstance(old, str):
            old, new = chr(old), chr(new)
        else:
            old, new = _cs(old), _cs(new)
        return self.replace(old, new)

    @staticmethod
    def toCharArray(self):
        array = runtime.new_array("[C", 0)
        array.extend(map(ord, self))
        return array

    @staticmethod
    def getBytes(self, charset=None):
        if charset is None:
            data = utf8_bytes(self)
        else:
            data = pystr(self).encode(_charset_name(charset), "replace")
        array = runtime.new_array("[B", 0)
        array.extend(b - 256 if b > 127 else b for b in data)
        return array

    @staticmethod
    def getClass(self):
        return api.lookup_host("java.lang.String")


def _charset_name(charset):
    name = charset if isinstance(charset, str) else charset.name()
    return name.lower().replace("_", "-")


String = register_value_type(
    "java.lang.String", str, _StringImpl, final=True,
    interfaces=("java.lang.CharSequence", "java.lang.Comparable", "java.io.Serializable"))


def _install_string_typed():
    """typed overloads the by-name methods cannot tell apart, registered as the table of the class"""
    table = {}
    for name, descriptor, function in (
        ("indexOf", "(I)I", lambda s, c: s.find(chr(c)) if c < 0x10000 else s.find(jstr(chr(c)))),
        ("indexOf", "(II)I", lambda s, c, start: s.find(chr(c) if c < 0x10000 else jstr(chr(c)), max(start, 0))),
        ("indexOf", "(Ljava/lang/String;)I", lambda s, t: s.find(t)),
        ("indexOf", "(Ljava/lang/String;I)I", lambda s, t, start: s.find(t, max(start, 0))),
        ("lastIndexOf", "(I)I", lambda s, c: s.rfind(chr(c))),
        ("lastIndexOf", "(Ljava/lang/String;)I", lambda s, t: s.rfind(t)),
        ("replace", "(CC)Ljava/lang/String;", lambda s, a, b: s.replace(chr(a), chr(b))),
        ("replace", "(Ljava/lang/CharSequence;Ljava/lang/CharSequence;)Ljava/lang/String;",
         lambda s, a, b: s.replace(_cs(a), _cs(b))),
        ("contains", "(Ljava/lang/CharSequence;)Z", lambda s, t: 1 if _cs(t) in s else 0),
        ("charAt", "(I)C", _StringImpl.charAt),
        ("length", "()I", _StringImpl.length),
        ("isEmpty", "()Z", _StringImpl.isEmpty),
        ("equals", "(Ljava/lang/Object;)Z", _StringImpl.equals),
        ("hashCode", "()I", _StringImpl.hashCode),
        ("toString", "()Ljava/lang/String;", _StringImpl.toString),
        ("substring", "(I)Ljava/lang/String;", _StringImpl.substring),
        ("substring", "(II)Ljava/lang/String;", _StringImpl.substring),
        ("compareTo", "(Ljava/lang/String;)I", _StringImpl.compareTo),
        ("compareTo", "(Ljava/lang/Object;)I", _StringImpl.compareTo),
        ("startsWith", "(Ljava/lang/String;)Z", _StringImpl.startsWith),
        ("startsWith", "(Ljava/lang/String;I)Z", _StringImpl.startsWith),
        ("endsWith", "(Ljava/lang/String;)Z", _StringImpl.endsWith),
        ("trim", "()Ljava/lang/String;", _StringImpl.trim),
        ("toUpperCase", "()Ljava/lang/String;", _StringImpl.toUpperCase),
        ("toLowerCase", "()Ljava/lang/String;", _StringImpl.toLowerCase),
        ("concat", "(Ljava/lang/String;)Ljava/lang/String;", _StringImpl.concat),
        ("intern", "()Ljava/lang/String;", _StringImpl.intern),
        ("toCharArray", "()[C", _StringImpl.toCharArray),
        ("getBytes", "()[B", _StringImpl.getBytes),
        ("equalsIgnoreCase", "(Ljava/lang/String;)Z", _StringImpl.equalsIgnoreCase),
        ("codePointAt", "(I)I", _StringImpl.codePointAt),
    ):
        table[(name, descriptor)] = (staticmethod(function), False)
    String._typed = table


def _install_string_statics():
    def value_of_object(value):
        return "null" if value is None else (value if isinstance(value, str) else value.toString())

    def value_of_chars(chars, offset=0, count=None):
        if chars is None:
            runtime.npe()
        if count is None:
            count = len(chars) - offset
        if offset < 0 or count < 0 or offset + count > len(chars):
            runtime.throw_new("java.lang.StringIndexOutOfBoundsException",
                              "length=%d; regionStart=%d; regionLength=%d" % (len(chars), offset, count))
        return "".join(map(chr, chars[offset:offset + count]))

    def join(delimiter, items):
        delimiter = _cs(delimiter)
        if isinstance(items, runtime.JArray):
            return delimiter.join(_text_of(item) for item in items)
        out = []
        iterator = items.iterator()
        while iterator.hasNext():
            out.append(_text_of(iterator.next()))
        return delimiter.join(out)

    entries = (
        ("valueOf", "(I)Ljava/lang/String;", str), ("valueOf", "(J)Ljava/lang/String;", str),
        ("valueOf", "(C)Ljava/lang/String;", chr),
        ("valueOf", "(Z)Ljava/lang/String;", lambda v: "true" if v else "false"),
        ("valueOf", "(F)Ljava/lang/String;", lambda v: float_to_string(v, True)),
        ("valueOf", "(D)Ljava/lang/String;", lambda v: float_to_string(v, False)),
        ("valueOf", "(Ljava/lang/Object;)Ljava/lang/String;", value_of_object),
        ("valueOf", "([C)Ljava/lang/String;", value_of_chars),
        ("valueOf", "([CII)Ljava/lang/String;", value_of_chars),
        ("copyValueOf", "([C)Ljava/lang/String;", value_of_chars),
        ("copyValueOf", "([CII)Ljava/lang/String;", value_of_chars),
        ("join", "(Ljava/lang/CharSequence;[Ljava/lang/CharSequence;)Ljava/lang/String;", join),
        ("join", "(Ljava/lang/CharSequence;Ljava/lang/Iterable;)Ljava/lang/String;", join),
    )
    for name, descriptor, function in entries:
        String._typed[(name, descriptor)] = (staticmethod(function), True)


_install_string_typed()
_install_string_statics()


def _string_new(*args):
    """new String(...): the constructors that produce a value"""
    if not args:
        return ""
    first = args[0]
    if isinstance(first, str):
        return first
    if isinstance(first, runtime.JArray):
        code = first.jtype.descriptor[1]
        if code == "C":
            if len(args) >= 3:
                first = first[args[1]:args[1] + args[2]]
            return "".join(map(chr, first))
        if code == "B":
            data = bytes(b & 0xFF for b in first)
            if len(args) == 3 and isinstance(args[1], int):
                data = data[args[1]:args[1] + args[2]]
                charset = None
            else:
                charset = args[-1] if len(args) == 2 or len(args) == 4 else None
            return jstr(data.decode(_charset_name(charset) if charset is not None else "utf-8", "replace"))
    if hasattr(first, "toString"):
        return first.toString()
    runtime.throw_new("java.lang.IllegalArgumentException", "unsupported String constructor")


String.construct = _string_new


@host_class("java.lang.AbstractStringBuilder")
class _AbstractStringBuilder(Object):
    __slots__ = ("_parts",)


def _text_of(value):
    return "null" if value is None else (value if isinstance(value, str) else value.toString())


def _cs(value):
    """the text of a CharSequence argument; null is a NullPointerException"""
    if value is None:
        runtime.npe()
    return value if isinstance(value, str) else value.toString()


@host_class("java.lang.StringBuilder", final=True)
class StringBuilder(_AbstractStringBuilder):
    """appends collect into a list of pieces that is joined when the content is read; a java char or number is formatted the way its overload says"""

    __slots__ = ()

    @jmethod("<init>", "()V")
    @jmethod("<init>", "(I)V")
    def _init(self, capacity=0):
        self._parts = []

    @jmethod("<init>", "(Ljava/lang/String;)V")
    @jmethod("<init>", "(Ljava/lang/CharSequence;)V")
    def _init_text(self, text):
        self._parts = [_cs(text)]

    def _text(self):
        parts = self._parts
        if len(parts) != 1:
            joined = "".join(parts)
            parts[:] = [joined]
            return joined
        return parts[0]

    @jmethod("append", "(Ljava/lang/String;)Ljava/lang/StringBuilder;")
    @jmethod("append", "(Ljava/lang/Object;)Ljava/lang/StringBuilder;")
    @jmethod("append", "(Ljava/lang/CharSequence;)Ljava/lang/StringBuilder;")
    def append(self, value):
        self._parts.append(_text_of(value))
        return self

    @jmethod("append", "(I)Ljava/lang/StringBuilder;")
    @jmethod("append", "(J)Ljava/lang/StringBuilder;")
    def append_int(self, value):
        self._parts.append(str(value))
        return self

    @jmethod("append", "(C)Ljava/lang/StringBuilder;")
    def append_char(self, value):
        self._parts.append(chr(value))
        return self

    @jmethod("append", "(Z)Ljava/lang/StringBuilder;")
    def append_bool(self, value):
        self._parts.append("true" if value else "false")
        return self

    @jmethod("append", "(F)Ljava/lang/StringBuilder;")
    def append_float(self, value):
        self._parts.append(float_to_string(value, True))
        return self

    @jmethod("append", "(D)Ljava/lang/StringBuilder;")
    def append_double(self, value):
        self._parts.append(float_to_string(value, False))
        return self

    @jmethod("append", "([C)Ljava/lang/StringBuilder;")
    def append_chars(self, value):
        self._parts.append("".join(map(chr, value)))
        return self

    @jmethod("append", "(Ljava/lang/CharSequence;II)Ljava/lang/StringBuilder;")
    def append_range(self, value, start, end):
        self._parts.append(_cs(value)[start:end])
        return self

    @jmethod("length", "()I")
    def length(self):
        return len(self._text())

    @jmethod("toString", "()Ljava/lang/String;")
    def toString(self):
        return self._text()

    @jmethod("charAt", "(I)C")
    def charAt(self, index):
        return _StringImpl.charAt(self._text(), index)

    @jmethod("reverse", "()Ljava/lang/StringBuilder;")
    def reverse(self):
        self._parts[:] = [self._text()[::-1]]
        return self

    @jmethod("insert", "(ILjava/lang/String;)Ljava/lang/StringBuilder;")
    def insert(self, index, value):
        text = self._text()
        if index < 0 or index > len(text):
            runtime.throw_new("java.lang.StringIndexOutOfBoundsException", "offset %d, length %d" % (index, len(text)))
        self._parts[:] = [text[:index] + _text_of(value) + text[index:]]
        return self

    @jmethod("insert", "(IC)Ljava/lang/StringBuilder;")
    def insert_char(self, index, value):
        return self.insert(index, chr(value))

    @jmethod("insert", "(II)Ljava/lang/StringBuilder;")
    def insert_int(self, index, value):
        return self.insert(index, str(value))

    @jmethod("setLength", "(I)V")
    def setLength(self, length):
        text = self._text()
        if length < 0:
            runtime.throw_new("java.lang.StringIndexOutOfBoundsException", "length " + str(length))
        self._parts[:] = [text[:length] + "\0" * (length - len(text))]

    @jmethod("setCharAt", "(IC)V")
    def setCharAt(self, index, value):
        text = self._text()
        if index < 0 or index >= len(text):
            runtime.throw_new("java.lang.StringIndexOutOfBoundsException", "index %d,length %d" % (index, len(text)))
        self._parts[:] = [text[:index] + chr(value) + text[index + 1:]]

    @jmethod("deleteCharAt", "(I)Ljava/lang/StringBuilder;")
    def deleteCharAt(self, index):
        text = self._text()
        if index < 0 or index >= len(text):
            runtime.throw_new("java.lang.StringIndexOutOfBoundsException", "index %d,length %d" % (index, len(text)))
        self._parts[:] = [text[:index] + text[index + 1:]]
        return self

    @jmethod("delete", "(II)Ljava/lang/StringBuilder;")
    def delete(self, start, end):
        text = self._text()
        end = min(end, len(text))
        if start < 0 or start > end:
            runtime.throw_new("java.lang.StringIndexOutOfBoundsException", "start %d, end %d, length %d" % (start, end, len(text)))
        self._parts[:] = [text[:start] + text[end:]]
        return self

    @jmethod("replace", "(IILjava/lang/String;)Ljava/lang/StringBuilder;")
    def replace(self, start, end, value):
        text = self._text()
        end = min(end, len(text))
        if start < 0 or start > len(text) or start > end:
            runtime.throw_new("java.lang.StringIndexOutOfBoundsException", "start %d, end %d, length %d" % (start, end, len(text)))
        self._parts[:] = [text[:start] + value + text[end:]]
        return self

    @jmethod("indexOf", "(Ljava/lang/String;)I")
    def indexOf(self, target):
        return self._text().find(target)

    @jmethod("substring", "(I)Ljava/lang/String;")
    @jmethod("substring", "(II)Ljava/lang/String;")
    def substring(self, begin, end=None):
        return _StringImpl.substring(self._text(), begin, end)

    @jmethod("isEmpty", "()Z")
    def isEmpty(self):
        return 0 if self._text() else 1


@host_class("java.lang.StringBuffer", final=True)
class StringBuffer(StringBuilder):
    __slots__ = ()


@host_class("java.lang.Math", final=True)
class Math:
    PI = math.pi
    E = math.e

    @jstatic("abs", "(I)I")
    def abs_int(a):
        return a if a >= 0 else runtime.wrap32(-a)

    @jstatic("abs", "(J)J")
    def abs_long(a):
        return a if a >= 0 else runtime.wrap64(-a)

    @jstatic("abs", "(F)F")
    @jstatic("abs", "(D)D")
    def abs_double(a):
        return abs(a)

    @jstatic("max", "(II)I")
    @jstatic("max", "(JJ)J")
    def max_int(a, b):
        return a if a > b else b

    @jstatic("min", "(II)I")
    @jstatic("min", "(JJ)J")
    def min_int(a, b):
        return a if a < b else b

    @jstatic("max", "(DD)D")
    @jstatic("max", "(FF)F")
    def max_double(a, b):
        if a != a or b != b:
            return math.nan
        if a == 0 and b == 0:
            return b if math.copysign(1.0, a) < 0 else a
        return a if a > b else b

    @jstatic("min", "(DD)D")
    @jstatic("min", "(FF)F")
    def min_double(a, b):
        if a != a or b != b:
            return math.nan
        if a == 0 and b == 0:
            return a if math.copysign(1.0, a) < 0 else b
        return a if a < b else b

    @jstatic("sqrt", "(D)D")
    def sqrt(a):
        return math.sqrt(a) if a >= 0 else math.nan

    @jstatic("pow", "(DD)D")
    def pow(a, b):
        try:
            return math.pow(a, b)
        except OverflowError:
            return math.inf
        except ValueError:
            return math.nan

    @jstatic("floor", "(D)D")
    def floor(a):
        return float(math.floor(a)) if a == a and not math.isinf(a) else a

    @jstatic("ceil", "(D)D")
    def ceil(a):
        return float(math.ceil(a)) if a == a and not math.isinf(a) else a

    @jstatic("round", "(D)J")
    def round_double(a):
        return runtime.d2l(math.floor(a + 0.5)) if a == a and not math.isinf(a) else runtime.d2l(a)

    @jstatic("round", "(F)I")
    def round_float(a):
        return runtime.d2i(math.floor(a + 0.5)) if a == a and not math.isinf(a) else runtime.d2i(a)

    @jstatic("sin", "(D)D")
    def sin(a):
        return math.sin(a) if not math.isinf(a) else math.nan

    @jstatic("cos", "(D)D")
    def cos(a):
        return math.cos(a) if not math.isinf(a) else math.nan

    @jstatic("tan", "(D)D")
    def tan(a):
        return math.tan(a) if not math.isinf(a) else math.nan

    @jstatic("atan2", "(DD)D")
    def atan2(a, b):
        return math.atan2(a, b)

    @jstatic("exp", "(D)D")
    def exp(a):
        try:
            return math.exp(a)
        except OverflowError:
            return math.inf

    @jstatic("log", "(D)D")
    def log(a):
        if a == 0:
            return -math.inf
        return math.log(a) if a > 0 else math.nan

    @jstatic("log10", "(D)D")
    def log10(a):
        if a == 0:
            return -math.inf
        return math.log10(a) if a > 0 else math.nan

    @jstatic("floorDiv", "(II)I")
    @jstatic("floorDiv", "(JJ)J")
    def floorDiv(a, b):
        if b == 0:
            runtime.throw_new("java.lang.ArithmeticException", "divide by zero")
        return a // b

    @jstatic("floorMod", "(II)I")
    @jstatic("floorMod", "(JJ)J")
    def floorMod(a, b):
        if b == 0:
            runtime.throw_new("java.lang.ArithmeticException", "divide by zero")
        return a % b

    @jstatic("addExact", "(II)I")
    def addExact_int(a, b):
        r = a + b
        if not runtime.INT_MIN <= r <= runtime.INT_MAX:
            runtime.throw_new("java.lang.ArithmeticException", "integer overflow")
        return r

    @jstatic("multiplyExact", "(II)I")
    def multiplyExact_int(a, b):
        r = a * b
        if not runtime.INT_MIN <= r <= runtime.INT_MAX:
            runtime.throw_new("java.lang.ArithmeticException", "integer overflow")
        return r

    @jstatic("toIntExact", "(J)I")
    def toIntExact(a):
        if not runtime.INT_MIN <= a <= runtime.INT_MAX:
            runtime.throw_new("java.lang.ArithmeticException", "integer overflow")
        return a

    @jstatic("signum", "(D)D")
    def signum(a):
        return a if a == 0 or a != a else math.copysign(1.0, a)

    @jstatic("hypot", "(DD)D")
    def hypot(a, b):
        return math.hypot(a, b)

    @jstatic("random", "()D")
    def random():
        import random as _random
        return _random.random()


@host_class("java.io.PrintStream")
class PrintStream(Object):
    """a print stream that hands every written text to a python callable"""

    def __init__(self, sink):
        self._sink = sink

    def _write(self, text):
        self._sink(text)

    @jmethod("close", "()V")
    def close(self):
        return None

    @jmethod("println", "()V")
    def _println0(self):
        self._write("\n")

    @jmethod("println", "(Ljava/lang/String;)V")
    @jmethod("println", "(Ljava/lang/Object;)V")
    def println(self, value):
        self._write(_text_of(value) + "\n")

    @jmethod("println", "(I)V")
    @jmethod("println", "(J)V")
    def println_int(self, value):
        self._write(str(value) + "\n")

    @jmethod("println", "(Z)V")
    def println_bool(self, value):
        self._write(("true" if value else "false") + "\n")

    @jmethod("println", "(C)V")
    def println_char(self, value):
        self._write(chr(value) + "\n")

    @jmethod("println", "(F)V")
    def println_float(self, value):
        self._write(float_to_string(value, True) + "\n")

    @jmethod("println", "(D)V")
    def println_double(self, value):
        self._write(float_to_string(value, False) + "\n")

    @jmethod("print", "(Ljava/lang/String;)V")
    @jmethod("print", "(Ljava/lang/Object;)V")
    def print(self, value):
        self._write(_text_of(value))

    @jmethod("print", "(I)V")
    @jmethod("print", "(J)V")
    def print_int(self, value):
        self._write(str(value))

    @jmethod("print", "(C)V")
    def print_char(self, value):
        self._write(chr(value))

    @jmethod("print", "(Z)V")
    def print_bool(self, value):
        self._write("true" if value else "false")

    @jmethod("flush", "()V")
    def flush(self):
        return None


@host_class("java.lang.System", final=True)
class System:
    out = PrintStream(lambda text: sys.stdout.write(pystr(text)))
    err = PrintStream(lambda text: sys.stderr.write(pystr(text)))

    @jstatic("currentTimeMillis", "()J")
    def currentTimeMillis():
        return int(time.time() * 1000)

    @jstatic("nanoTime", "()J")
    def nanoTime():
        return time.monotonic_ns()

    @jstatic("identityHashCode", "(Ljava/lang/Object;)I")
    def identityHashCode(value):
        return 0 if value is None else id(value) >> 4 & 0x7FFFFFFF

    @jstatic("lineSeparator", "()Ljava/lang/String;")
    def lineSeparator():
        return "\n"

    @jstatic("arraycopy", "(Ljava/lang/Object;ILjava/lang/Object;II)V")
    def arraycopy(source, source_pos, dest, dest_pos, length):
        if source is None or dest is None:
            runtime.npe()
        if not isinstance(source, runtime.JArray) or not isinstance(dest, runtime.JArray):
            runtime.throw_new("java.lang.ArrayStoreException", "source and destination must be arrays")
        if source.jtype.component.isPrimitive() != dest.jtype.component.isPrimitive() or (
                source.jtype.component.isPrimitive() and source.jtype.component is not dest.jtype.component):
            runtime.throw_new("java.lang.ArrayStoreException", "arraycopy: type mismatch")
        if source_pos < 0 or dest_pos < 0 or length < 0 or source_pos + length > len(source) \
                or dest_pos + length > len(dest):
            runtime.throw_new("java.lang.ArrayIndexOutOfBoundsException",
                              "arraycopy: length %d is out of bounds for array" % length)
        chunk = source[source_pos:source_pos + length]
        if not dest.jtype.component.isPrimitive() and dest.jtype is not source.jtype:
            for item in chunk:
                runtime.array_store_check(dest, item)
        dest[dest_pos:dest_pos + length] = chunk

    _properties = {"line.separator": "\n", "file.separator": "/", "path.separator": ":", "java.vm.name": "Dalvik",
                   "java.vm.version": "2.1.0", "java.vendor": "The Android Project", "os.name": "Linux",
                   "os.arch": "aarch64", "user.language": "en", "file.encoding": "UTF-8", "java.io.tmpdir": "/tmp",
                   "http.agent": "Dalvik/2.1.0 (Linux; U; Android; exteria)"}

    @jstatic("getProperty", "(Ljava/lang/String;)Ljava/lang/String;")
    @jstatic("getProperty", "(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;")
    def getProperty(key, fallback=None):
        if not key:
            runtime.throw_new("java.lang.IllegalArgumentException", "key can't be empty" if key == "" else None)
        return System._properties.get(key, fallback)

    @jstatic("setProperty", "(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;")
    def setProperty(key, value):
        if not key:
            runtime.throw_new("java.lang.IllegalArgumentException", "key can't be empty" if key == "" else None)
        old = System._properties.get(key)
        System._properties[key] = value
        return old

    @jstatic("clearProperty", "(Ljava/lang/String;)Ljava/lang/String;")
    def clearProperty(key):
        return System._properties.pop(key, None)

    @jstatic("getenv", "(Ljava/lang/String;)Ljava/lang/String;")
    def getenv(name):
        import os
        return os.environ.get(name)

    @jstatic("gc", "()V")
    def gc():
        import gc
        gc.collect()

    @jstatic("getProperties", "()Ljava/util/Properties;")
    def getProperties():
        from .jcoll import Properties
        result = Properties()
        for key, value in System._properties.items():
            result.setProperty(key, value)
        return result

    @jstatic("load", "(Ljava/lang/String;)V")
    @jstatic("loadLibrary", "(Ljava/lang/String;)V")
    def load(name):
        runtime.throw_new("java.lang.UnsatisfiedLinkError",
                          "%s: native android libraries cannot be loaded in this process" % name)

    @jstatic("exit", "(I)V")
    def exit(status):
        runtime.throw_new("java.lang.SecurityException", "exit(%d) is not allowed" % status)


@host_class("java.lang.Enum", interfaces=("java.lang.Comparable", "java.io.Serializable"))
class Enum(Object):
    """the base of every enum: name and ordinal are set by the generated constructor of the dex class"""

    _name = None
    _ordinal = 0

    @jmethod("<init>", "(Ljava/lang/String;I)V")
    def _init(self, name, ordinal):
        self._name = name
        self._ordinal = ordinal

    @jstatic("valueOf", "(Ljava/lang/Class;Ljava/lang/String;)Ljava/lang/Enum;")
    def valueOf(enum_class, name):
        if enum_class is None or name is None:
            runtime.npe()
        constants = enum_class.getEnumConstants()
        if constants is None:
            runtime.throw_new("java.lang.ClassCastException", enum_class.getName() + " is not an enum type")
        for constant in constants:
            if constant._name == name:
                return constant
        runtime.throw_new("java.lang.IllegalArgumentException",
                          "No enum constant %s.%s" % (enum_class.getCanonicalName(), name))

    @jmethod("name", "()Ljava/lang/String;")
    def name(self):
        return self._name

    @jmethod("ordinal", "()I")
    def ordinal(self):
        return self._ordinal

    @jmethod("toString", "()Ljava/lang/String;")
    def toString(self):
        return self._name

    @jmethod("compareTo", "(Ljava/lang/Enum;)I")
    @jmethod("compareTo", "(Ljava/lang/Object;)I")
    def compareTo(self, other):
        return self._ordinal - other._ordinal

    @jmethod("getDeclaringClass", "()Ljava/lang/Class;")
    def getDeclaringClass(self):
        jtype = runtime.class_of(self)
        parent = jtype.getSuperclass()
        return parent if parent is not None and parent.getName() != "java.lang.Enum" else jtype

    @jmethod("equals", "(Ljava/lang/Object;)Z")
    def equals(self, other):
        return 1 if self is other else 0

    @jmethod("hashCode", "()I")
    def hashCode(self):
        return id(self) >> 4 & 0x7FFFFFFF


for _box, _code in ((Integer, "I"), (Long, "J"), (Short, "S"), (Byte, "B"), (Character, "C"), (Boolean, "Z"),
                    (Float, "F"), (Double, "D")):
    _box.TYPE = api.PRIMITIVES[_code]


@host_class("java.lang.Thread", interfaces=("java.lang.Runnable",))
class Thread(Object):
    """a java thread over a python thread. run() calls the target, an exception that leaves it is printed to System.err as the default handler of a jvm does"""

    _counter = 0
    _by_ident = {}
    _lock = threading.Lock()

    _target = None
    _name = None
    _thread = None
    _daemon = 0
    _interrupted = 0
    _started = False

    def __init__(self, target=None, name=None):
        self._init_state(target, name)

    def _init_state(self, target, name):
        self._target = target
        if name is None:
            with Thread._lock:
                name = "Thread-%d" % Thread._counter
                Thread._counter += 1
        self._name = name

    @jmethod("<init>", "()V")
    def _init0(self):
        self._init_state(None, None)

    @jmethod("<init>", "(Ljava/lang/Runnable;)V")
    def _init1(self, target):
        self._init_state(target, None)

    @jmethod("<init>", "(Ljava/lang/String;)V")
    def _init_name(self, name):
        self._init_state(None, name)

    @jmethod("<init>", "(Ljava/lang/Runnable;Ljava/lang/String;)V")
    def _init2(self, target, name):
        self._init_state(target, name)

    @jmethod("run", "()V")
    def run(self):
        if self._target is not None:
            self._target.run()

    @jmethod("start", "()V")
    def start(self):
        if self._started:
            runtime.throw_new("java.lang.IllegalThreadStateException", None)
        self._started = True
        # the new thread spends from the budget of the thread that starts it, or a loop in a thread would escape it
        inherited = [hook() for hook in runtime.THREAD_START_HOOKS]
        self._thread = threading.Thread(target=self._bootstrap, args=(limits.current(), inherited), name=self._name,
                                        daemon=bool(self._daemon))
        self._thread.start()

    def _bootstrap(self, shared=None, inherited=()):
        Thread._by_ident[threading.get_ident()] = self
        try:
            for apply in inherited:
                apply()
            with limits.adopt(shared):
                self.run()
        except limits.BudgetExceeded as error:
            # no output from here: the owner of the budget raises this when its call returns
            if shared is not None:
                shared.failure = error
        except Exception as error:
            failure = runtime.to_throwable(error)
            System.err.println('Exception in thread "%s" %s' % (self.getName(), failure.toString()))
        finally:
            Thread._by_ident.pop(threading.get_ident(), None)

    @jmethod("join", "()V")
    @jmethod("join", "(J)V")
    def join(self, millis=0):
        if self._thread is not None:
            self._thread.join(millis / 1000.0 if millis else None)

    @jstatic("getAllStackTraces", "()Ljava/util/Map;")
    def getAllStackTraces():
        """the live threads the vm knows: the ones it started and the ones that ran vm code, each with an empty trace"""
        from .jmap import HashMap
        result = HashMap()
        with Thread._lock:
            known = list(Thread._by_ident.values())
        for thread in known:
            if thread._thread is None or thread._thread.is_alive():
                result.put(thread, runtime.new_array("[Ljava/lang/StackTraceElement;", 0))
        return result

    @jmethod("isAlive", "()Z")
    def isAlive(self):
        return 1 if self._thread is not None and self._thread.is_alive() else 0

    @jmethod("getName", "()Ljava/lang/String;")
    def getName(self):
        return self._name

    @jmethod("setPriority", "(I)V")
    def setPriority(self, priority):
        if not 1 <= priority <= 10:
            runtime.throw_new("java.lang.IllegalArgumentException", None)
        self._priority = priority

    @jmethod("setContextClassLoader", "(Ljava/lang/ClassLoader;)V")
    def setContextClassLoader(self, loader):
        self._context_loader = loader

    @jmethod("getStackTrace", "()[Ljava/lang/StackTraceElement;")
    def getStackTrace(self):
        return runtime.new_array("[Ljava/lang/StackTraceElement;", 0)

    @jmethod("setName", "(Ljava/lang/String;)V")
    def setName(self, name):
        self._name = name

    @jmethod("setDaemon", "(Z)V")
    def setDaemon(self, flag):
        if self._started:
            runtime.throw_new("java.lang.IllegalThreadStateException", None)
        self._daemon = flag

    @jmethod("isDaemon", "()Z")
    def isDaemon(self):
        return self._daemon

    @jmethod("interrupt", "()V")
    def interrupt(self):
        self._interrupted = 1

    @jmethod("isInterrupted", "()Z")
    def isInterrupted(self):
        return self._interrupted

    @jmethod("getId", "()J")
    def getId(self):
        return self._thread.ident if self._thread is not None else 0

    @jstatic("currentThread", "()Ljava/lang/Thread;")
    def currentThread():
        ident = threading.get_ident()
        found = Thread._by_ident.get(ident)
        if found is None:
            found = Thread.__new__(Thread)
            found._init_state(None, "main" if threading.current_thread() is threading.main_thread()
                              else threading.current_thread().name)
            found._started = True
            found._thread = threading.current_thread()
            Thread._by_ident[ident] = found
        return found

    @jstatic("sleep", "(J)V")
    def sleep(millis):
        if millis < 0:
            runtime.throw_new("java.lang.IllegalArgumentException", "millis < 0: %d" % millis)
        time.sleep(millis / 1000.0)

    @jstatic("yield", "()V")
    def yield_():
        time.sleep(0)


@host_class("java.lang.Void", final=True)
class Void(Object):
    TYPE = api.PRIMITIVES["V"]


def _box_compare(self, other):
    if other is None:
        runtime.npe()
    if isinstance(self.value, float):
        return _compare_double(self.value, other.value)
    return (self.value > other.value) - (self.value < other.value)


for _box in (Integer, Long, Short, Byte, Character, Boolean, Float, Double):
    if "compareTo" not in vars(_box):
        _box.compareTo = _box_compare


def _text_call(name, *, receiver=False):
    """String methods that need the formatter or the regex translator: the module with them is imported by the first call"""
    def call(*args):
        from . import jtext
        return getattr(jtext, name)(*args)
    call.__name__ = name
    return staticmethod(call)


def _install_text_stubs():
    table = String._typed
    for key, name, static in (
            (("format", "(Ljava/lang/String;[Ljava/lang/Object;)Ljava/lang/String;"), "string_format", True),
            (("format", "(Ljava/util/Locale;Ljava/lang/String;[Ljava/lang/Object;)Ljava/lang/String;"), "string_format_locale", True),
            (("formatted", "([Ljava/lang/Object;)Ljava/lang/String;"), "string_formatted", False),
            (("matches", "(Ljava/lang/String;)Z"), "string_matches", False),
            (("replaceAll", "(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;"), "string_replace_all", False),
            (("replaceFirst", "(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;"), "string_replace_first", False),
            (("split", "(Ljava/lang/String;)[Ljava/lang/String;"), "string_split", False),
            (("split", "(Ljava/lang/String;I)[Ljava/lang/String;"), "string_split", False)):
        table[key] = (_text_call(name), static)
    for name, attribute in (("matches", "string_matches"), ("replaceAll", "string_replace_all"),
                            ("replaceFirst", "string_replace_first"), ("split", "string_split")):
        setattr(_StringImpl, name, _text_call(attribute))

    def printf(self, template, args):
        from . import jtext
        self._write(jtext.java_format(None, template, args))
        return self
    printf._jsigs = [("printf", "(Ljava/lang/String;[Ljava/lang/Object;)Ljava/io/PrintStream;"),
                     ("format", "(Ljava/lang/String;[Ljava/lang/Object;)Ljava/io/PrintStream;")]
    PrintStream.printf = printf
    PrintStream.format = printf


class _LazyComparator:
    """String.CASE_INSENSITIVE_ORDER is built by jfunc, which is imported when the field is first read"""

    def __get__(self, obj, owner):
        from . import jfunc
        value = jfunc.case_insensitive_order()
        _StringImpl.CASE_INSENSITIVE_ORDER = value
        return value


_StringImpl.CASE_INSENSITIVE_ORDER = _LazyComparator()
_install_text_stubs()
