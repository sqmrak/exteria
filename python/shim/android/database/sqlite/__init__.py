"""android.database.sqlite over the sqlite3 module of python: SQLiteDatabase, SQLiteOpenHelper, SQLiteStatement, SQLiteQueryBuilder and the exceptions

a database is a file; the connection is shared by the threads of the process under one lock, like the connection pool of android with a single
connection. a transaction is BEGIN IMMEDIATE and nests by counting, as beginTransaction and endTransaction do"""

import os
import sqlite3
import threading

from android.database import AbstractCursor, SQLException, _plain
from java.lang import IllegalArgumentException, IllegalStateException, Object

CONFLICT_NONE = 0
CONFLICT_ROLLBACK = 1
CONFLICT_ABORT = 2
CONFLICT_FAIL = 3
CONFLICT_IGNORE = 4
CONFLICT_REPLACE = 5
_CONFLICT = ["", " OR ROLLBACK ", " OR ABORT ", " OR FAIL ", " OR IGNORE ", " OR REPLACE "]


class SQLiteException(SQLException):
    pass


def _subclass(name, parent=SQLiteException):
    return type(name, (parent,), {"__module__": __name__})


SQLiteAbortException = _subclass("SQLiteAbortException")
SQLiteAccessPermException = _subclass("SQLiteAccessPermException")
SQLiteBindOrColumnIndexOutOfRangeException = _subclass("SQLiteBindOrColumnIndexOutOfRangeException")
SQLiteBlobTooBigException = _subclass("SQLiteBlobTooBigException")
SQLiteCantOpenDatabaseException = _subclass("SQLiteCantOpenDatabaseException")
SQLiteConstraintException = _subclass("SQLiteConstraintException")
SQLiteDatabaseCorruptException = _subclass("SQLiteDatabaseCorruptException")
SQLiteDatabaseLockedException = _subclass("SQLiteDatabaseLockedException")
SQLiteDatatypeMismatchException = _subclass("SQLiteDatatypeMismatchException")
SQLiteDiskIOException = _subclass("SQLiteDiskIOException")
SQLiteDoneException = _subclass("SQLiteDoneException")
SQLiteFullException = _subclass("SQLiteFullException")
SQLiteMisuseException = _subclass("SQLiteMisuseException")
SQLiteOutOfMemoryException = _subclass("SQLiteOutOfMemoryException")
SQLiteReadOnlyDatabaseException = _subclass("SQLiteReadOnlyDatabaseException")
SQLiteTableLockedException = _subclass("SQLiteTableLockedException")


def _translate(error, sql=""):
    """the android exception for a sqlite3 error"""
    text = "%s (code %s): while compiling: %s" % (error, getattr(error, "sqlite_errorcode", ""), sql)
    if isinstance(error, sqlite3.IntegrityError):
        return SQLiteConstraintException(text)
    if isinstance(error, sqlite3.OperationalError):
        message = str(error).lower()
        if "locked" in message or "busy" in message:
            return SQLiteDatabaseLockedException(text)
        if "unable to open" in message:
            return SQLiteCantOpenDatabaseException(text)
        if "readonly" in message or "read-only" in message:
            return SQLiteReadOnlyDatabaseException(text)
        if "full" in message:
            return SQLiteFullException(text)
        return SQLiteException(text)
    if isinstance(error, sqlite3.DatabaseError):
        message = str(error).lower()
        if "malformed" in message or "not a database" in message:
            return SQLiteDatabaseCorruptException(text)
        return SQLiteException(text)
    if isinstance(error, sqlite3.ProgrammingError):
        return SQLiteMisuseException(text) if "binding" not in str(error).lower() else IllegalArgumentException(str(error))
    if isinstance(error, sqlite3.InterfaceError):
        return SQLiteMisuseException(text)
    return SQLiteException(text)


def _args(values):
    if values is None:
        return ()
    return tuple(_plain(v) if v is not None else None for v in values)


class SQLiteClosable(Object):
    pass


class SQLiteDatabase(SQLiteClosable):
    CONFLICT_NONE, CONFLICT_ROLLBACK, CONFLICT_ABORT, CONFLICT_FAIL, CONFLICT_IGNORE, CONFLICT_REPLACE = range(6)
    OPEN_READWRITE = 0
    OPEN_READONLY = 1
    CREATE_IF_NECESSARY = 0x10000000
    NO_LOCALIZED_COLLATORS = 0x10
    ENABLE_WRITE_AHEAD_LOGGING = 0x20000000
    MAX_SQL_CACHE_SIZE = 100
    SQLITE_MAX_LIKE_PATTERN_LENGTH = 50000

    class CursorFactory:
        """a program implements newCursor(db, masterQuery, editTable, query)"""

    class OpenParams(Object):
        class Builder(Object):
            def __init__(self, *_a):
                self._flags = 0

            def __getattr__(self, name):
                def keep(*_args):
                    return self
                return keep

            def build(self):
                return SQLiteDatabase.OpenParams()

    def __init__(self, path, flags):
        self._path = path
        self._flags = flags
        self._lock = threading.RLock()
        self._depth = 0
        self._success = False
        self._listener = None
        readonly = flags & 1
        if path == ":memory:":
            uri = ":memory:"
        else:
            uri = "file:%s?mode=%s" % (path, "ro" if readonly else ("rwc" if flags & SQLiteDatabase.CREATE_IF_NECESSARY else "rw"))
        try:
            self._conn = sqlite3.connect(uri, uri=True, isolation_level=None, check_same_thread=False)
        except sqlite3.Error as error:
            raise SQLiteCantOpenDatabaseException("Cannot open database '%s': %s" % (path, error))
        self._conn.execute("PRAGMA foreign_keys=OFF")
        self._open = True
        if flags & SQLiteDatabase.ENABLE_WRITE_AHEAD_LOGGING:
            self.enableWriteAheadLogging()

    @staticmethod
    def openDatabase(path, factory=None, flags=0, handler=None):
        path = path.getPath() if hasattr(path, "getPath") else str(path)
        return SQLiteDatabase(path, flags)

    @staticmethod
    def openOrCreateDatabase(path, factory=None, handler=None):
        path = path.getPath() if hasattr(path, "getPath") else str(path)
        if path != ":memory:":
            os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
        return SQLiteDatabase(path, SQLiteDatabase.CREATE_IF_NECESSARY)

    @staticmethod
    def create(factory=None):
        return SQLiteDatabase(":memory:", SQLiteDatabase.CREATE_IF_NECESSARY)

    @staticmethod
    def deleteDatabase(file):
        path = file.getPath()
        found = False
        for suffix in ("", "-journal", "-wal", "-shm"):
            if os.path.exists(path + suffix):
                os.remove(path + suffix)
                found = found or suffix == ""
        return found

    @staticmethod
    def releaseMemory():
        return sqlite3.sqlite3_soft_heap_limit if False else 0

    def _need_open(self):
        if not self._open:
            raise IllegalStateException("attempt to re-open an already-closed object: SQLiteDatabase: " + self._path)

    def _run(self, sql, args=()):
        self._need_open()
        with self._lock:
            try:
                return self._conn.execute(sql, args)
            except sqlite3.Error as error:
                raise _translate(error, sql) from None
            except (ValueError, OverflowError) as error:
                raise IllegalArgumentException(str(error)) from None

    def isOpen(self):
        return self._open

    def getPath(self):
        return self._path

    def isReadOnly(self):
        return bool(self._flags & 1)

    def isWriteAheadLoggingEnabled(self):
        return str(self._run("PRAGMA journal_mode").fetchone()[0]).lower() == "wal"

    def enableWriteAheadLogging(self):
        return str(self._run("PRAGMA journal_mode=WAL").fetchone()[0]).lower() == "wal"

    def disableWriteAheadLogging(self):
        self._run("PRAGMA journal_mode=DELETE")

    def setForeignKeyConstraintsEnabled(self, enable):
        self._run("PRAGMA foreign_keys=%d" % (1 if enable else 0))

    def getVersion(self):
        return int(self._run("PRAGMA user_version").fetchone()[0])

    def setVersion(self, version):
        self._run("PRAGMA user_version = %d" % int(version))

    def getPageSize(self):
        return int(self._run("PRAGMA page_size").fetchone()[0])

    def setPageSize(self, size):
        self._run("PRAGMA page_size = %d" % int(size))

    def getMaximumSize(self):
        return int(self._run("PRAGMA max_page_count").fetchone()[0]) * self.getPageSize()

    def needUpgrade(self, new_version):
        return self.getVersion() != new_version

    def setLocale(self, locale):
        return None

    def setMaxSqlCacheSize(self, size):
        return None

    def setLockingEnabled(self, flag):
        return None

    def close(self):
        with self._lock:
            if self._open:
                self._open = False
                try:
                    self._conn.close()
                except sqlite3.Error:
                    pass

    def execSQL(self, sql, args=None):
        if sql is None:
            raise IllegalArgumentException("sql must not be null.")
        if args is None:
            for statement in _split_statements(sql):
                self._run(statement)
        else:
            self._run(sql, _args(args))

    def rawQuery(self, sql, args=None, *_signal):
        if sql is None:
            raise IllegalArgumentException("sql must not be null.")
        cursor = self._run(sql, _args(args))
        columns = [d[0] for d in cursor.description] if cursor.description else []
        try:
            rows = cursor.fetchall()
        except sqlite3.Error as error:
            raise _translate(error, sql) from None
        return AbstractCursor(columns, rows)

    rawQueryWithFactory = lambda self, factory, sql, args=None, table=None, *rest: self.rawQuery(sql, args)

    def query(self, *args):
        """query(table, columns, selection, selectionArgs, groupBy, having, orderBy[, limit]) and the same with a leading distinct flag"""
        distinct = False
        if isinstance(args[0], bool):
            distinct, args = args[0], args[1:]
        table, columns, selection, selection_args, group_by, having, order_by = args[:7]
        limit = args[7] if len(args) > 7 else None
        sql = SQLiteQueryBuilder.buildQueryString(distinct, table, columns, selection, group_by, having, order_by, limit)
        return self.rawQuery(sql, selection_args)

    queryWithFactory = lambda self, factory, distinct, table, columns, selection, args, group, having, order, limit=None, *r: self.query(
        distinct, table, columns, selection, args, group, having, order, limit)

    def insert(self, table, null_column_hack, values):
        try:
            return self.insertWithOnConflict(table, null_column_hack, values, CONFLICT_NONE)
        except SQLException as error:
            from android.util import Log
            Log.e("SQLiteDatabase", "Error inserting " + str(values), error)
            return -1

    def insertOrThrow(self, table, null_column_hack, values):
        return self.insertWithOnConflict(table, null_column_hack, values, CONFLICT_NONE)

    def replace(self, table, null_column_hack, values):
        try:
            return self.insertWithOnConflict(table, null_column_hack, values, CONFLICT_REPLACE)
        except SQLException:
            return -1

    def replaceOrThrow(self, table, null_column_hack, values):
        return self.insertWithOnConflict(table, null_column_hack, values, CONFLICT_REPLACE)

    def insertWithOnConflict(self, table, null_column_hack, values, conflict):
        items = values._items() if values is not None else []
        if not items:
            if not null_column_hack:
                raise IllegalArgumentException("Empty values")
            sql = "INSERT%s INTO %s (%s) VALUES (NULL)" % (_CONFLICT[conflict].rstrip(), table, null_column_hack)
            args = ()
        else:
            sql = "INSERT%s INTO %s (%s) VALUES (%s)" % (_CONFLICT[conflict].rstrip(), table, ", ".join(k for k, _ in items), ", ".join("?" for _ in items))
            args = tuple(v for _, v in items)
        cursor = self._run(sql, args)
        return cursor.lastrowid if cursor.rowcount > 0 else -1

    def update(self, table, values, where=None, args=None):
        return self.updateWithOnConflict(table, values, where, args, CONFLICT_NONE)

    def updateWithOnConflict(self, table, values, where, args, conflict):
        items = values._items() if values is not None else []
        if not items:
            raise IllegalArgumentException("Empty values")
        sql = "UPDATE%s %s SET %s%s" % (_CONFLICT[conflict].rstrip(), table, ", ".join(k + "=?" for k, _ in items), " WHERE " + where if where else "")
        return self._run(sql, tuple(v for _, v in items) + _args(args)).rowcount

    def delete(self, table, where=None, args=None):
        return self._run("DELETE FROM " + table + (" WHERE " + where if where else ""), _args(args)).rowcount

    def compileStatement(self, sql):
        self._need_open()
        return SQLiteStatement(self, sql)

    # transactions

    def beginTransaction(self, listener=None):
        self._begin(listener)

    beginTransactionNonExclusive = beginTransactionWithListener = beginTransactionWithListenerNonExclusive = beginTransaction

    def _begin(self, listener):
        self._need_open()
        self._lock.acquire()
        if self._depth == 0:
            try:
                self._conn.execute("BEGIN IMMEDIATE")
            except sqlite3.Error as error:
                self._lock.release()
                raise _translate(error, "BEGIN") from None
            self._success = False
            self._listener = listener
        self._depth += 1
        if self._depth > 1 and not self._success_stack_ok():
            pass

    def _success_stack_ok(self):
        return True

    def setTransactionSuccessful(self):
        if self._depth == 0:
            raise IllegalStateException("no transaction pending")
        self._success = True

    def endTransaction(self):
        if self._depth == 0:
            raise IllegalStateException("no transaction pending")
        self._depth -= 1
        try:
            if self._depth == 0:
                listener, self._listener = self._listener, None
                try:
                    if self._success:
                        self._conn.execute("COMMIT")
                        if listener is not None:
                            listener.onCommit()
                    else:
                        self._conn.execute("ROLLBACK")
                        if listener is not None:
                            listener.onRollback()
                except sqlite3.Error as error:
                    raise _translate(error, "COMMIT") from None
        finally:
            self._lock.release()

    def inTransaction(self):
        return self._depth > 0

    def isDbLockedByCurrentThread(self):
        return self._depth > 0

    def yieldIfContendedSafely(self, *_args):
        return False

    def toString(self):
        return "SQLiteDatabase: " + self._path


def _split_statements(sql):
    """the statements of a script, split where sqlite3 says a statement is complete"""
    parts, current = [], ""
    for line in sql.splitlines(True):
        current += line
        if sqlite3.complete_statement(current):
            parts.append(current.strip())
            current = ""
    if current.strip():
        parts.append(current.strip())
    return parts or [sql]


class SQLiteProgram(SQLiteClosable):
    def __init__(self, database, sql):
        self._db, self._sql, self._binds = database, sql, {}

    def bound(self, args):
        for index, value in enumerate(args or ()):
            self._binds[index + 1] = _plain(value)
        return self

    def _params(self):
        count = max(self._binds, default=0)
        return tuple(self._binds.get(i) for i in range(1, count + 1))

    def bindNull(self, index):
        self._binds[index] = None

    def bindLong(self, index, value):
        self._binds[index] = int(value)

    def bindDouble(self, index, value):
        self._binds[index] = float(value)

    def bindString(self, index, value):
        if value is None:
            raise IllegalArgumentException("the bind value at index %d is null" % index)
        self._binds[index] = str(value)

    def bindBlob(self, index, value):
        if value is None:
            raise IllegalArgumentException("the bind value at index %d is null" % index)
        self._binds[index] = _plain(value)

    def bindAllArgsAsStrings(self, args):
        for index, value in enumerate(args or (), 1):
            self._binds[index] = None if value is None else str(value)

    def clearBindings(self):
        self._binds = {}

    def close(self):
        return None


class SQLiteStatement(SQLiteProgram):
    def execute(self):
        self._db._run(self._sql, self._params())

    def executeUpdateDelete(self):
        return self._db._run(self._sql, self._params()).rowcount

    def executeInsert(self):
        cursor = self._db._run(self._sql, self._params())
        return cursor.lastrowid if cursor.rowcount > 0 else -1

    def simpleQueryForLong(self):
        row = self._db._run(self._sql, self._params()).fetchone()
        if row is None or row[0] is None:
            raise SQLiteDoneException("query returned no rows")
        return int(row[0])

    def simpleQueryForString(self):
        row = self._db._run(self._sql, self._params()).fetchone()
        if row is None:
            raise SQLiteDoneException("query returned no rows")
        return None if row[0] is None else str(row[0])


class SQLiteQueryBuilder(Object):
    def __init__(self):
        self._tables = ""
        self._where = []
        self._distinct = False
        self._projection_map = None
        self._strict = False

    def setTables(self, tables):
        self._tables = tables

    def getTables(self):
        return self._tables

    def setDistinct(self, flag):
        self._distinct = bool(flag)

    def appendWhere(self, text):
        self._where.append(str(text))

    def appendWhereEscapeString(self, text):
        self._where.append("'" + str(text).replace("'", "''") + "'")

    def setProjectionMap(self, mapping):
        self._projection_map = mapping

    def setStrict(self, flag):
        self._strict = bool(flag)

    def setCursorFactory(self, factory):
        return None

    @staticmethod
    def buildQueryString(distinct, tables, columns, where, group_by, having, order_by, limit):
        if not group_by and having:
            raise IllegalArgumentException("HAVING clauses are only permitted when using a groupBy clause")
        names = ", ".join(columns) if columns else "*"
        sql = "SELECT " + ("DISTINCT " if distinct else "") + names + " FROM " + tables
        if where:
            sql += " WHERE " + where
        if group_by:
            sql += " GROUP BY " + group_by
        if having:
            sql += " HAVING " + having
        if order_by:
            sql += " ORDER BY " + order_by
        if limit:
            sql += " LIMIT " + str(limit)
        return sql

    def buildQuery(self, columns, selection, group_by, having, order_by, limit):
        where = " AND ".join("(" + w + ")" for w in self._where + ([selection] if selection else []))
        return SQLiteQueryBuilder.buildQueryString(self._distinct, self._tables, columns, where or None, group_by, having, order_by, limit)

    def query(self, database, columns, selection, selection_args, group_by, having, order_by, limit=None, *_signal):
        if not self._tables:
            return None
        return database.rawQuery(self.buildQuery(columns, selection, group_by, having, order_by, limit), selection_args)


class SQLiteOpenHelper(Object):
    def __init__(self, context, name, factory=None, version=1, *_rest):
        if version < 1:
            raise IllegalArgumentException("Version must be >= 1, was %d" % version)
        self._context, self._name, self._version = context, name, version
        self._db = None
        self._lock = threading.RLock()

    def getDatabaseName(self):
        return self._name

    def onConfigure(self, db):
        return None

    def onCreate(self, db):
        raise NotImplementedError("onCreate")

    def onUpgrade(self, db, old_version, new_version):
        raise NotImplementedError("onUpgrade")

    def onDowngrade(self, db, old_version, new_version):
        raise SQLiteException("Can't downgrade database from version %d to %d" % (old_version, new_version))

    def onOpen(self, db):
        return None

    def setWriteAheadLoggingEnabled(self, flag):
        self._wal = bool(flag)

    def setIdleConnectionTimeout(self, ms):
        return None

    def _open(self, writable):
        with self._lock:
            if self._db is not None and self._db.isOpen():
                return self._db
            if self._name is None:
                db = SQLiteDatabase.create()
            else:
                path = self._context.getDatabasePath(self._name).getPath()
                os.makedirs(os.path.dirname(path), exist_ok=True)
                db = SQLiteDatabase(path, SQLiteDatabase.CREATE_IF_NECESSARY if writable else 0)
            self.onConfigure(db)
            version = db.getVersion()
            if version != self._version:
                db.beginTransaction()
                try:
                    if version == 0:
                        self.onCreate(db)
                    elif version > self._version:
                        self.onDowngrade(db, version, self._version)
                    else:
                        self.onUpgrade(db, version, self._version)
                    db.setVersion(self._version)
                    db.setTransactionSuccessful()
                finally:
                    db.endTransaction()
            self.onOpen(db)
            self._db = db
            return db

    def getWritableDatabase(self):
        return self._open(True)

    getReadableDatabase = getWritableDatabase

    def close(self):
        with self._lock:
            if self._db is not None:
                self._db.close()
                self._db = None
