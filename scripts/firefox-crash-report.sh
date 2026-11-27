#!/usr/bin/env bash
# Ringkas crash Firefox dari breakpad minidump di snap.
# Pakai: scripts/firefox-crash-report.sh [jumlah]

set -u
DIR="$HOME/snap/firefox/common/.mozilla/firefox/Crash Reports/pending"
LIMIT="${1:-10}"

if [ ! -d "$DIR" ]; then
    echo "folder crash tidak ada: $DIR"
    exit 1
fi

python3 - "$DIR" "$LIMIT" <<'PY'
import datetime, glob, json, os, struct, sys

d, limit = sys.argv[1], int(sys.argv[2])

def parse(path):
    b = open(path, 'rb').read()
    _, _, n, rva, _, _, _ = struct.unpack_from('<IIIIIIQ', b, 0)
    st = {}
    for i in range(n):
        t, sz, r = struct.unpack_from('<III', b, rva + i * 12)
        st[t] = (sz, r)
    mods = []
    sz4, r4 = st[4]
    for i in range(struct.unpack_from('<I', b, r4)[0]):
        off = r4 + 4 + i * 108
        base, size = struct.unpack_from('<QI', b, off)
        nrva = struct.unpack_from('<I', b, off + 20)[0]
        ln = struct.unpack_from('<I', b, nrva)[0]
        nm = b[nrva + 4:nrva + 4 + ln].decode('utf-16-le', 'replace')
        mods.append((base, size, nm))
    tid = ecode = eaddr = 0
    if 6 in st:
        _, r6 = st[6]
        tid = struct.unpack_from('<I', b, r6)[0]
        ecode = struct.unpack_from('<I', b, r6 + 8)[0]
        eaddr = struct.unpack_from('<Q', b, r6 + 24)[0]
    sz3, r3 = st[3]
    rip = 0
    for i in range(struct.unpack_from('<I', b, r3)[0]):
        toff = r3 + 4 + i * 48
        t_id = struct.unpack_from('<I', b, toff)[0]
        csz, crva = struct.unpack_from('<II', b, toff + 40)
        if t_id == tid and crva and csz >= 0x100:
            rip = struct.unpack_from('<Q', b, crva + 0xF8)[0]
    mod = next(((base, nm) for base, size, nm in mods if base <= rip < base + size), None)
    frame = "%s +%s" % (os.path.basename(mod[1]), hex(rip - mod[0])) if mod else "?"
    return ecode, eaddr, frame

files = sorted(glob.glob(os.path.join(d, '*.dmp')), key=os.path.getmtime)
print("total crash pending: %d" % len(files))
for p in files[-limit:]:
    ex = os.path.splitext(p)[0] + '.extra'
    meta = json.load(open(ex)) if os.path.exists(ex) else {}
    try:
        ecode, eaddr, frame = parse(p)
    except Exception as exc:
        ecode, eaddr, frame = 0, 0, "parse error: %s" % exc
    print("\n%s" % os.path.basename(p)[:8])
    ts = meta.get('CrashTime')
    when = datetime.datetime.fromtimestamp(float(ts)).strftime('%Y-%m-%d %H:%M:%S') if ts else '?'
    print("  waktu      : %s" % when)
    print("  url        : %s" % meta.get('URL', '?'))
    print("  process    : %s" % meta.get('ProcessType', '?'))
    print("  uptime     : %s s" % meta.get('UptimeTS', '?'))
    print("  mem avail  : %s" % meta.get('AvailablePhysicalMemory', '?'))
    print("  exception  : code %s addr %s" % (hex(ecode), hex(eaddr)))
    print("  frame      : %s" % frame)
PY
