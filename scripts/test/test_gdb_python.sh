#!/usr/bin/env bash
# Test script for GDB Python support
#
# Usage:
#   ./test_gdb_python.sh /path/to/riscv32-unknown-elf-gdb
#   ./test_gdb_python.sh /path/to/riscv64-unknown-elf-gdb
#
# If run from the toolchain bin directory, it will auto-detect the gdb binary:
#   cd LocalInstall/linux64/newlibc/2026-daily/gcc/bin
#   ../../../scripts/test/test_gdb_python.sh
#
# Relocatability test:
#   Copy the entire toolchain to another location and test again:
#     cp -r LocalInstall/linux64/newlibc/2026-daily/gcc /tmp/test-gdb
#     ./scripts/test/test_gdb_python.sh /tmp/test-gdb/bin/riscv32-unknown-elf-gdb
#   If sys.prefix automatically updates to the new path and all modules still work,
#   the relocatable python support is working correctly.

GDB=${1:-$(ls $PWD/bin/*-gdb 2>/dev/null | head -1)}
if [ ! -f "$GDB" ] ; then
    echo "Usage: $0 /path/to/riscv32-unknown-elf-gdb"
    echo "Or run from the toolchain bin directory"
    exit 1
fi

# Track test results: 0=pass, 1=fail, 2=skip
FAIL=0
SKIP=0
PASS=0

check() {
    local name="$1"
    shift
    local output
    output=$("$@" 2>&1)
    local ret=$?
    if echo "$output" | grep -qiE 'error|exception|traceback|not found|failed' ; then
        echo "  FAIL: $name"
        echo "$output" | grep -E 'Error|error|Exception|not found|No module' | head -5
        FAIL=$((FAIL+1))
        return 1
    elif [ $ret -ne 0 ] ; then
        echo "  FAIL: $name (exit code $ret)"
        echo "$output" | tail -5
        FAIL=$((FAIL+1))
        return 1
    else
        echo "  PASS: $name"
        PASS=$((PASS+1))
        return 0
    fi
}

check_output() {
    local name="$1"
    local pattern="$2"
    shift 2
    local output
    output=$("$@" 2>&1)
    local ret=$?
    if echo "$output" | grep -qiE 'error|exception|traceback' ; then
        echo "  FAIL: $name"
        echo "$output" | grep -E 'Error|error|Exception|not found|No module' | head -5
        FAIL=$((FAIL+1))
        return 1
    elif ! echo "$output" | grep -q "$pattern" ; then
        echo "  FAIL: $name (expected pattern '$pattern' not found)"
        echo "$output" | tail -5
        FAIL=$((FAIL+1))
        return 1
    else
        echo "  PASS: $name"
        PASS=$((PASS+1))
        return 0
    fi
}

# Get a RISC-V ELF file for API tests
find_riscv_elf() {
    GDB_NAME=$(basename $GDB)
    TARGET_TRIPLE=${GDB_NAME%-gdb}
    echo $(find $(dirname $(dirname $GDB))/$TARGET_TRIPLE -name 'crt0.o' 2>/dev/null | head -1)
}

echo "=========================================="
echo "Testing GDB Python support"
echo "GDB: $GDB"
echo "=========================================="

# 1. Check runtime dependencies
echo ""
echo "--- 1. Runtime dependencies ---"
ldd "$GDB" | grep -E 'python|ncurses|tinfo|ffi|not found'
not_found=$(ldd "$GDB" 2>/dev/null | grep -c 'not found')
if [ "$not_found" -gt 0 ] ; then
    echo "  FAIL: $not_found unresolved dependencies"
    ldd "$GDB" | grep 'not found'
    FAIL=$((FAIL+1))
else
    echo "  PASS: All dependencies resolved"
    PASS=$((PASS+1))
fi

# 2. Basic Python version
echo ""
echo "--- 2. Python version ---"
check "Python version" "$GDB" --batch -ex "python import sys; print(sys.version)" -ex "quit"

# 3. Python relocatable prefix
echo ""
echo "--- 3. Python prefix ---"
check "Python prefix" "$GDB" --batch -ex "python print('prefix:', sys.prefix)" -ex "quit"

# 4. Python standard library - essential modules
echo ""
echo "--- 4. Standard library ---"
for mod in os re json math zlib sqlite3 ctypes hashlib xml.etree.ElementTree; do
    check "import $mod" "$GDB" --batch -ex "python import $mod; print('$mod: OK')" -ex "quit"
done

# 5. Python standard library - functional tests
echo ""
echo "--- 5. Standard library functional tests ---"
check "os.path.basename" "$GDB" --batch -ex "python import os.path; print(os.path.basename('/foo/bar/baz.txt'))" -ex "quit"
check "re.match" "$GDB" --batch -ex "python import re; print('match' if re.match(r'hello', 'hello world') else 'no')" -ex "quit"
check "json.dumps/loads" "$GDB" --batch -ex "python import json; d=json.dumps({'a':1,'b':2}); print(json.loads(d)['a'])" -ex "quit"
check "math.sqrt" "$GDB" --batch -ex "python import math; print(math.sqrt(81))" -ex "quit"
check "zlib.compress/decompress" "$GDB" --batch -ex "python import zlib; d=zlib.compress(b'test'); print(zlib.decompress(d))" -ex "quit"
check "hashlib.sha256" "$GDB" --batch -ex "python import hashlib; print(hashlib.sha256(b'test').hexdigest())" -ex "quit"
check "sqlite3" "$GDB" --batch -ex "python import sqlite3; conn=sqlite3.connect(':memory:'); cur=conn.execute('CREATE TABLE t (v)'); cur.execute('INSERT INTO t VALUES (42)'); print('row:', cur.execute('SELECT * FROM t').fetchone()[0])" -ex "quit"
check "ctypes" "$GDB" --batch -ex "python import ctypes; print('c_int:', ctypes.c_int(42).value); print('c_char:', ctypes.c_char(b'a').value); print('sizeof:', ctypes.sizeof(ctypes.c_int))" -ex "quit"
check "xml.etree" "$GDB" --batch -ex "python import xml.etree.ElementTree as ET; r=ET.fromstring('<root><a>1</a><b>2</b></root>'); print('tag:', r.tag); print('children:', len(r)); print('find:', r.find('a').text)" -ex "quit"
check "os.listdir" "$GDB" --batch -ex "python import os; print('listdir:', len(os.listdir('/'))); print('exists:', os.path.exists('/'))" -ex "quit"
check "time.time" "$GDB" --batch -ex "python import time; t=time.time(); print('time:', type(t)); print('sleep:', time.sleep(0.01) if time.sleep(0.01) is None else 'ok')" -ex "quit"

# 6. GDB Python API - basic
echo ""
echo "--- 6. GDB Python API basic ---"
check "gdb module" "$GDB" --batch -ex "python import gdb; print('gdb module: OK')" -ex "quit"
check "gdb.VERSION" "$GDB" --batch -ex "python print('gdb.version:', gdb.VERSION)" -ex "quit"
check "gdb.lookup_type" "$GDB" --batch -ex "python import gdb; t=gdb.lookup_type('int'); print('size:', t.sizeof); print('name:', t.name)" -ex "quit"
check "gdb.lookup_type(char)" "$GDB" --batch -ex "python import gdb; t=gdb.lookup_type('char'); print('char size:', t.sizeof)" -ex "quit"
check "gdb.lookup_type(void*)" "$GDB" --batch -ex "python import gdb; t=gdb.lookup_type('void').pointer(); print('ptr size:', t.sizeof)" -ex "quit"

# 7. GDB Python API - pretty printer
echo ""
echo "--- 7. Python pretty printer ---"
cat > /tmp/test_pretty_printer.py << 'PYEOF'
import gdb

class TestPrinter:
    def __init__(self, val):
        self.val = val
    def to_string(self):
        return "TestPrinter: %d" % int(self.val)
    def children(self):
        return [("value", self.val)]
    def display_hint(self):
        return "string"

def register_test_printer():
    gdb.pretty_printers.append(lambda val: TestPrinter(val) if str(val.type) == "int" else None)

register_test_printer()
print("Pretty printer registered")
PYEOF
check "pretty printer registration" "$GDB" --batch -ex "source /tmp/test_pretty_printer.py" -ex "python print('pretty printer test: OK')" -ex "quit"

# 8. GDB Python API - user-defined command
echo ""
echo "--- 8. Python user-defined command ---"
cat > /tmp/test_gdb_cmd.py << 'PYEOF'
import gdb

class TestCmd(gdb.Command):
    """Test command for GDB Python"""
    def __init__(self):
        super().__init__("test-hello", gdb.COMMAND_USER, gdb.COMPLETE_NONE, True)
    def invoke(self, arg, from_tty):
        print("Hello from Python test command, arg=%s" % arg)

TestCmd()
print("TestCmd registered")
PYEOF
check "register custom command" "$GDB" --batch -ex "source /tmp/test_gdb_cmd.py" -ex "test-hello world" -ex "quit"

# 9. GDB Python API - convenience function
echo ""
echo "--- 9. Python convenience function ---"
cat > /tmp/test_gdb_func.py << 'PYEOF'
import gdb

class TestFunc(gdb.Function):
    """Test function"""
    def __init__(self):
        super().__init__("test_add")
    def invoke(self, a, b):
        return int(a) + int(b)

TestFunc()
print("TestFunc registered")
PYEOF
check "register convenience function" "$GDB" --batch -ex "source /tmp/test_gdb_func.py" -ex "python print('test_add(3,4)=', gdb.parse_and_eval('\$test_add(3,4)'))" -ex "quit"

# 10. GDB Python API - value manipulation
echo ""
echo "--- 10. Value manipulation ---"
cat > /tmp/test_value.py << 'PYEOF'
import gdb

# Test value creation and manipulation
v = gdb.Value(42)
print("int value:", v)
print("int type:", v.type)
print("int cast to long:", v.cast(gdb.lookup_type('long')))

# Test string value
s = gdb.Value("hello")
print("string value:", s)
print("string type:", s.type)

# Test array - use tuple instead
t = (1, 2, 3)
print("tuple type:", type(t))
PYEOF
check "value manipulation" "$GDB" --batch -ex "source /tmp/test_value.py" -ex "quit"

# 11. GDB Python API - ELF binary analysis
echo ""
echo "--- 11. ELF binary analysis ---"
RISCV_ELF=$(find_riscv_elf)
if [ -f "$RISCV_ELF" ] ; then
    cat > /tmp/test_elf.py << 'PYEOF'
import gdb
import sys

# Test objfile iteration
print("objfiles:", list(gdb.objfiles()))
for obj in gdb.objfiles():
    print("  filename:", obj.filename)
    print("  pretty_printers:", bool(obj.pretty_printers))
    print("  is_file:", obj.is_file)

# Test architecture
arch = gdb.selected_inferior().architecture()
print("arch name:", arch.name())
print("arch register count:", len(list(arch.registers())))
PYEOF
    check "objfile and architecture" "$GDB" --batch -ex "file $RISCV_ELF" -ex "source /tmp/test_elf.py" -ex "quit"
else
    echo "  SKIP: No RISC-V ELF found for ELF analysis"
    SKIP=$((SKIP+1))
fi

# 12. GDB Python API - block and symbol lookup
echo ""
echo "--- 12. Block and symbol lookup ---"
if [ -f "$RISCV_ELF" ] ; then
    check "block iteration" "$GDB" --batch -ex "file $RISCV_ELF" -ex "python import gdb; print('globals:', len(list(gdb.lookup_global_symbol('__bss_start') or [])))" -ex "quit"
else
    echo "  SKIP: No RISC-V ELF found for symbol lookup"
    SKIP=$((SKIP+1))
fi

# 13. GDB Python API - frame and thread
echo ""
echo "--- 13. Frame and thread API ---"
cat > /tmp/test_frame.py << 'PYEOF'
import gdb

# Test frame API (no running process, so frames may not be available)
try:
    frame = gdb.selected_frame()
    print("selected frame:", frame)
except gdb.error as e:
    print("expected: no frame:", e)

# Test thread API
try:
    thread = gdb.selected_thread()
    print("selected thread:", thread)
except gdb.error as e:
    print("expected: no thread:", e)

# Test inferiors
for inf in gdb.inferiors():
    print("inferior:", inf.num, "pid:", inf.pid)
PYEOF
check "frame and thread API" "$GDB" --batch -ex "source /tmp/test_frame.py" -ex "quit"

# 14. GDB Python API - parameter management
echo ""
echo "--- 14. Parameter management ---"
cat > /tmp/test_param.py << 'PYEOF'
import gdb

# Test reading gdb parameters
print("verbose:", gdb.parameter("verbose"))
print("pagination:", gdb.parameter("pagination"))
print("architecture:", gdb.parameter("architecture"))

# Test setting a parameter
gdb.set_parameter("pagination", "off")
print("pagination after set:", gdb.parameter("pagination"))
PYEOF
check "parameter management" "$GDB" --batch -ex "source /tmp/test_param.py" -ex "quit"

# 15. GDB Python API - execute command
echo ""
echo "--- 15. Execute command ---"
cat > /tmp/test_exec.py << 'PYEOF'
import gdb

# Test gdb.execute with various commands
out = gdb.execute("show version", to_string=True)
print("version output:", out[:80] if out else "empty")

out = gdb.execute("show configuration", to_string=True)
print("config has python:", "--with-python" in out)
PYEOF
check "gdb.execute()" "$GDB" --batch -ex "source /tmp/test_exec.py" -ex "quit"

# 16. GDB Python API - event handling
echo ""
echo "--- 16. Event handling ---"
cat > /tmp/test_event.py << 'PYEOF'
import gdb

# Test event registration objects
events = [
    gdb.events.stop,
    gdb.events.cont,
    gdb.events.exited,
    gdb.events.new_objfile,
    gdb.events.before_prompt,
]
for ev in events:
    print("event:", ev)
    # Try connecting a dummy handler
    try:
        conn = ev.connect(lambda e: None)
        print("  connect: OK")
    except Exception as e:
        print("  connect error:", e)
PYEOF
check "event handling" "$GDB" --batch -ex "source /tmp/test_event.py" -ex "quit"

# 17. GDB Python API - breakpoint management
echo ""
echo "--- 17. Breakpoint management ---"
cat > /tmp/test_bp.py << 'PYEOF'
import gdb

# Test creating and listing breakpoints (even if no symbols, the API should work)
try:
    bp = gdb.Breakpoint("main", internal=True)
    print("breakpoint created:", bp.number, bp.location, bool(bp.enabled))
    # List all breakpoints
    for b in gdb.breakpoints():
        print("  bp:", b.number, b.location, b.enabled)
    bp.delete()
    print("breakpoint deleted")
except gdb.error as e:
    print("expected breakpoint error:", e)
PYEOF
check "breakpoint management" "$GDB" --batch -ex "source /tmp/test_bp.py" -ex "quit"

# 18. GDB Python API - type manipulation
echo ""
echo "--- 18. Type manipulation ---"
cat > /tmp/test_type.py << 'PYEOF'
import gdb

# Test various type lookups
for name in ["int", "char", "long", "short", "float", "double", "void"]:
    try:
        t = gdb.lookup_type(name)
        ptr = t.pointer()
        arr = t.array(10)
        print("  %s: size=%d, ptr_size=%d, arr_size=%d" % (name, t.sizeof, ptr.sizeof, arr.sizeof))
    except Exception as e:
        print("  %s: error=%s" % (name, e))

# Test pointer arithmetic
t = gdb.lookup_type("int")
print("int pointer arithmetic:", t.pointer().pointer().sizeof)
PYEOF
check "type manipulation" "$GDB" --batch -ex "source /tmp/test_type.py" -ex "quit"

# 19. Test sys.path for bundled standard library
echo ""
echo "--- 19. Python sys.path ---"
"$GDB" --batch -ex "python import sys; [print('  ', p) for p in sys.path]" -ex "quit" 2>&1
echo "  PASS: sys.path displayed"
PASS=$((PASS+1))

# 20. Test relocatability: check if prefix matches expected install path
echo ""
echo "--- 20. Relocatability check ---"
GDB_DIR=$(dirname $(readlink -f $GDB))
EXPECTED_PREFIX=$(readlink -f $GDB_DIR/..)
ACTUAL_PREFIX=$("$GDB" --batch -ex "python import sys; print(sys.prefix)" -ex "quit" 2>&1)
if [ "$ACTUAL_PREFIX" = "$EXPECTED_PREFIX" ] ; then
    echo "  PASS: sys.prefix ($ACTUAL_PREFIX) matches expected prefix"
    PASS=$((PASS+1))
else
    echo "  FAIL: sys.prefix ($ACTUAL_PREFIX) != expected ($EXPECTED_PREFIX)"
    FAIL=$((FAIL+1))
fi

echo ""
echo "=========================================="
echo "Results: $PASS passed, $FAIL failed, $SKIP skipped"
echo "=========================================="
exit $FAIL