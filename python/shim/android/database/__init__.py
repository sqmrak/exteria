"""android.database: Cursor and the cursors made of lists, DatabaseUtils, the observers and the exceptions

a cursor holds all its rows: the sqlite cursor of android pages them out of a window, this one reads the result set whole, so a query that answers
millions of rows needs the memory for them. column types follow sqlite: an integer is a long, a real a double, text a string, a blob a byte[]"""

from java.lang import IllegalArgumentException, Object, RuntimeException

FIELD_TYPE_NULL = 0
FIELD_TYPE_INTEGER = 1
FIELD_TYPE_FLOAT = 2
FIELD_TYPE_STRING = 3
FIELD_TYPE_BLOB = 4


class SQLException(RuntimeException):
    pass


class CursorIndexOutOfBoundsException(RuntimeException):
    pass


class StaleDataException(RuntimeException):
    pass


class CharArrayBuffer(Object):
    def __init__(self, size=0):
        self.data = [0] * size
        self.sizeCopied = 0


class DataSetObserver(Object):
    def onChanged(self):
        return None

    def onInvalidated(self):
        return None


class DataSetObservable(Object):
    def __init__(self):
        self._observers = []

    def registerObserver(self, observer):
        if observer in self._observers:
            raise IllegalArgumentException("Observer %s is already registered." % observer)
        self._observers.append(observer)

    def unregisterObserver(self, observer):
        if observer not in self._observers:
            raise IllegalArgumentException("Observer %s was not registered." % observer)
        self._observers.remove(observer)

    def unregisterAll(self):
        self._observers = []

    def notifyChanged(self):
        for observer in list(self._observers):
            observer.onChanged()

    def notifyInvalidated(self):
        for observer in list(self._observers):
            observer.onInvalidated()


class ContentObserver(Object):
    """told by a content provider when its data changes; there are no content providers here, so only a program that calls onChange itself reaches it"""

    def __init__(self, handler=None):
        self._handler = handler

    def deliverSelfNotifications(self):
        return False

    def onChange(self, self_change, uri=None):
        return None

    def dispatchChange(self, self_change, uri=None):
        self.onChange(self_change, uri)


class Cursor:
    FIELD_TYPE_NULL = FIELD_TYPE_NULL
    FIELD_TYPE_INTEGER = FIELD_TYPE_INTEGER
    FIELD_TYPE_FLOAT = FIELD_TYPE_FLOAT
    FIELD_TYPE_STRING = FIELD_TYPE_STRING
    FIELD_TYPE_BLOB = FIELD_TYPE_BLOB
    _jinterface = True


def _blob(value):
    from dexvm.jio import to_java_bytes
    return to_java_bytes(bytes(value))


class AbstractCursor(Object):
    """a cursor over rows kept in a list of tuples; a subclass fills _columns and _rows"""

    def __init__(self, columns=(), rows=()):
        self._columns = list(columns)
        self._rows = [tuple(row) for row in rows]
        self._pos = -1
        self._closed = False
        self._observable = DataSetObservable()
        self._extras = None

    def _check(self):
        if self._closed:
            raise StaleDataException("Attempted to access a cursor after it has been closed.")
        if self._pos < 0 or self._pos >= len(self._rows):
            raise CursorIndexOutOfBoundsException("Index %d requested, with a size of %d" % (self._pos, len(self._rows)))

    def _value(self, column):
        self._check()
        if not 0 <= column < len(self._columns):
            raise CursorIndexOutOfBoundsException("column %d out of range of %d columns" % (column, len(self._columns)))
        return self._rows[self._pos][column]

    def getCount(self):
        return len(self._rows)

    def getPosition(self):
        return self._pos

    def moveToPosition(self, position):
        if position < -1:
            position = -1
        if position > len(self._rows):
            position = len(self._rows)
        self._pos = position
        return 0 <= position < len(self._rows)

    def move(self, offset):
        return self.moveToPosition(self._pos + offset)

    def moveToFirst(self):
        return self.moveToPosition(0)

    def moveToLast(self):
        return self.moveToPosition(len(self._rows) - 1)

    def moveToNext(self):
        return self.moveToPosition(self._pos + 1)

    def moveToPrevious(self):
        return self.moveToPosition(self._pos - 1)

    def isFirst(self):
        return self._pos == 0 and len(self._rows) > 0

    def isLast(self):
        return len(self._rows) > 0 and self._pos == len(self._rows) - 1

    def isBeforeFirst(self):
        return len(self._rows) == 0 or self._pos == -1

    def isAfterLast(self):
        return len(self._rows) == 0 or self._pos == len(self._rows)

    def getColumnIndex(self, name):
        if name is None:
            raise IllegalArgumentException("columnName must not be null")
        lowered = name.lower()
        dot = lowered.rfind(".")
        for index, column in enumerate(self._columns):
            if column.lower() == lowered:
                return index
        if dot >= 0:
            return self.getColumnIndex(name[dot + 1:])
        return -1

    def getColumnIndexOrThrow(self, name):
        index = self.getColumnIndex(name)
        if index < 0:
            raise IllegalArgumentException("column '%s' does not exist. Available columns: %s" % (name, self._columns))
        return index

    def getColumnName(self, index):
        return self._columns[index]

    def getColumnNames(self):
        from dexvm import runtime
        array = runtime.new_array("[Ljava/lang/String;", 0)
        array.extend(self._columns)
        return array

    def getColumnCount(self):
        return len(self._columns)

    def getString(self, column):
        value = self._value(column)
        if value is None:
            return None
        if isinstance(value, (bytes, bytearray)):
            raise RuntimeException("unable to convert BLOB to string")
        if isinstance(value, float):
            from dexvm.jlang import float_to_string
            return float_to_string(value, False)
        return str(value)

    def getLong(self, column):
        value = self._value(column)
        if value is None:
            return 0
        if isinstance(value, (bytes, bytearray)):
            raise RuntimeException("unable to convert BLOB to long")
        try:
            return int(value) if not isinstance(value, str) else int(float(value))
        except ValueError:
            return 0

    def getInt(self, column):
        from dexvm import runtime
        return runtime.wrap32(self.getLong(column))

    def getShort(self, column):
        return (self.getLong(column) + 32768 & 0xFFFF) - 32768

    def getDouble(self, column):
        value = self._value(column)
        if value is None:
            return 0.0
        if isinstance(value, (bytes, bytearray)):
            raise RuntimeException("unable to convert BLOB to double")
        try:
            return float(value)
        except ValueError:
            return 0.0

    def getFloat(self, column):
        from dexvm import runtime
        return runtime.f32(self.getDouble(column))

    def getBlob(self, column):
        value = self._value(column)
        if value is None:
            return None
        if isinstance(value, str):
            return _blob(value.encode("utf-8"))
        return _blob(value)

    def getType(self, column):
        value = self._value(column)
        if value is None:
            return FIELD_TYPE_NULL
        if isinstance(value, bool) or isinstance(value, int):
            return FIELD_TYPE_INTEGER
        if isinstance(value, float):
            return FIELD_TYPE_FLOAT
        if isinstance(value, (bytes, bytearray)):
            return FIELD_TYPE_BLOB
        return FIELD_TYPE_STRING

    def isNull(self, column):
        return self._value(column) is None

    def copyStringToBuffer(self, column, buffer):
        text = self.getString(column) or ""
        buffer.data = [ord(c) for c in text]
        buffer.sizeCopied = len(text)

    def close(self):
        self._closed = True
        self._observable.unregisterAll()

    def isClosed(self):
        return self._closed

    def requery(self):
        return False

    def deactivate(self):
        return None

    def registerDataSetObserver(self, observer):
        self._observable.registerObserver(observer)

    def unregisterDataSetObserver(self, observer):
        self._observable.unregisterObserver(observer)

    def registerContentObserver(self, observer):
        return None

    def unregisterContentObserver(self, observer):
        return None

    def setNotificationUri(self, resolver, uri):
        self._uri = uri

    def getNotificationUri(self):
        return getattr(self, "_uri", None)

    def getExtras(self):
        from android.os import Bundle
        if self._extras is None:
            self._extras = Bundle()
        return self._extras

    def setExtras(self, extras):
        self._extras = extras

    def respond(self, extras):
        return extras

    def getWantsAllOnMoveCalls(self):
        return False


class MatrixCursor(AbstractCursor):
    class RowBuilder(Object):
        def __init__(self, cursor):
            self._c, self._row = cursor, []

        def add(self, *args):
            if len(args) == 1:
                self._row.append(args[0])
            else:
                column, value = args
                index = self._c.getColumnIndexOrThrow(column) if isinstance(column, str) else column
                while len(self._row) <= index:
                    self._row.append(None)
                self._row[index] = value
            return self

    def __init__(self, columns, capacity=16):
        AbstractCursor.__init__(self, list(columns), [])

    def addRow(self, values):
        values = list(values)
        if len(values) != len(self._columns):
            raise IllegalArgumentException("columnNames.length = %d, columnValues.length = %d" % (len(self._columns), len(values)))
        self._rows.append(tuple(_plain(v) for v in values))

    def newRow(self):
        builder = MatrixCursor.RowBuilder(self)
        self._pending = builder
        original = builder.add

        def add(*args):
            result = original(*args)
            if len(builder._row) == len(self._columns) and not getattr(builder, "_done", False):
                builder._done = True
                self._rows.append(tuple(_plain(v) for v in builder._row))
            return result
        builder.add = add
        return builder


class MergeCursor(AbstractCursor):
    def __init__(self, cursors):
        cursors = [c for c in cursors if c is not None]
        columns = cursors[0]._columns if cursors else []
        rows = [row for c in cursors for row in c._rows]
        AbstractCursor.__init__(self, columns, rows)


class CursorWrapper(Object):
    def __init__(self, cursor):
        self._cursor = cursor

    def getWrappedCursor(self):
        return self._cursor

    def __getattr__(self, name):
        return getattr(self._cursor, name)


def _plain(value):
    """a java value as the python value sqlite stores: boxes by their value, byte[] as bytes"""
    if value is None or isinstance(value, (str, bytes, bool, int, float)):
        return value
    if hasattr(value, "value") and isinstance(value.value, (int, float, bool)):
        return value.value
    if hasattr(value, "jtype") and value.jtype.descriptor == "[B":
        return bytes(b & 0xFF for b in value)
    if isinstance(value, (list, tuple)):
        return bytes(b & 0xFF for b in value)
    return value.toString() if hasattr(value, "toString") else str(value)


class DatabaseUtils(Object):
    @staticmethod
    def sqlEscapeString(value):
        return "'" + str(value).replace("'", "''") + "'"

    @staticmethod
    def appendEscapedSQLString(builder, value):
        builder.append(DatabaseUtils.sqlEscapeString(value))

    @staticmethod
    def appendValueToSql(builder, value):
        if value is None:
            builder.append("NULL")
        elif isinstance(value, bool) or hasattr(value, "booleanValue"):
            builder.append("1" if _plain(value) else "0")
        else:
            plain = _plain(value)
            builder.append(str(plain) if isinstance(plain, (int, float)) else DatabaseUtils.sqlEscapeString(plain))

    @staticmethod
    def longForQuery(database, query, args=None):
        return database.compileStatement(query).bound(args).simpleQueryForLong()

    @staticmethod
    def stringForQuery(database, query, args=None):
        return database.compileStatement(query).bound(args).simpleQueryForString()

    @staticmethod
    def queryNumEntries(database, table, selection=None, args=None):
        sql = "select count(*) from " + table + (" where " + selection if selection else "")
        return DatabaseUtils.longForQuery(database, sql, args)

    @staticmethod
    def concatenateWhere(a, b):
        if not a:
            return b
        if not b:
            return a
        return "(" + a + ") AND (" + b + ")"

    @staticmethod
    def getCollationKey(name):
        return name
