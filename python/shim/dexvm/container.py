"""dex containers: a bare dex file or a zip with classes.dex, classes2.dex ..."""

import io
import re
import zipfile
import zlib

from .format import DexFile, DexFormatError, MAX_FILE_SIZE

_CLASSES = re.compile(r"classes([0-9]*)\.dex\Z")

# a container never needs more; the limits keep a hostile archive from filling memory
MAX_ENTRIES = 4096
MAX_DEX_FILES = 100
MAX_TOTAL_SIZE = 256 * 1024 * 1024


def load_container(data, name="<memory>"):
    """the DexFile list of the bytes: one dex file, or the classes*.dex entries of a zip in numeric order"""
    data = bytes(data)
    if len(data) > MAX_TOTAL_SIZE:
        raise DexFormatError("container is larger than %d bytes" % MAX_TOTAL_SIZE)
    if data[:4] == b"dex\n":
        return [DexFile(data, name)]
    if data[:2] != b"PK":
        raise DexFormatError("neither a dex file nor a zip archive")
    try:
        archive = zipfile.ZipFile(io.BytesIO(data))
    except zipfile.BadZipFile as error:
        raise DexFormatError("bad zip archive: %s" % error) from error
    with archive:
        infos = archive.infolist()
        if len(infos) > MAX_ENTRIES:
            raise DexFormatError("zip archive has more than %d entries" % MAX_ENTRIES)
        found = []
        numbers = set()
        for info in infos:
            match = _CLASSES.match(info.filename)
            if match is None:
                continue
            if info.flag_bits & 0x1:
                raise DexFormatError("encrypted zip entry " + info.filename)
            if info.file_size > MAX_FILE_SIZE:
                raise DexFormatError("zip entry %s is larger than %d bytes" % (info.filename, MAX_FILE_SIZE))
            suffix = match.group(1)
            if suffix and (suffix.startswith("0") or suffix == "1" or len(suffix) > 20):
                raise DexFormatError("invalid dex entry " + info.filename)
            number = int(suffix or 1)
            if number in numbers:
                raise DexFormatError("duplicate dex entry " + info.filename)
            numbers.add(number)
            found.append((number, info))
        if not found:
            raise DexFormatError("zip archive has no classes.dex")
        found.sort(key=lambda item: item[0])
        if len(found) > MAX_DEX_FILES:
            raise DexFormatError("zip archive has more than %d dex files" % MAX_DEX_FILES)
        if sum(info.file_size for _, info in found) > MAX_TOTAL_SIZE:
            raise DexFormatError("dex files of the archive are larger than %d bytes" % MAX_TOTAL_SIZE)
        result = []
        for _, info in found:
            try:
                with archive.open(info) as stream:
                    content = stream.read(MAX_FILE_SIZE + 1)
            except (zipfile.BadZipFile, RuntimeError, EOFError, OSError, zlib.error) as error:
                raise DexFormatError("bad zip entry %s: %s" % (info.filename, error)) from error
            if len(content) != info.file_size:
                raise DexFormatError("zip entry %s differs from its declared size" % info.filename)
            result.append(DexFile(content, info.filename))
        return result
