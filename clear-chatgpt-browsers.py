#!/usr/bin/python3
"""Remove ChatGPT/OpenAI history, cookies, saved logins, bookmarks and site storage
from Chrome, Firefox and Safari. Needs Full Disk Access; browsers must be quit.
Usage: clear-chatgpt-browsers.py          -> dry run (counts only)
       clear-chatgpt-browsers.py --yes    -> quits browsers, backs up, deletes"""
import glob, json, os, re, shutil, sqlite3, struct, subprocess, sys, time

DO = "--yes" in sys.argv
HOSTS = ["chatgpt.com", "openai.com", "oaistatic.com", "oaiusercontent.com", "chat.com", "sora.com"]
RX = re.compile("|".join(re.escape(h) for h in HOSTS), re.I)
L = os.path.expanduser("~/Library")
BACKUP = os.path.expanduser(f"~/Library/Application Support/chatgpt-browser-backup-{time.strftime('%Y%m%d-%H%M%S')}")


def host_hit(h):  # exact host or subdomain, so "notchat.com" does not match "chat.com"
    h = (h or "").lower().lstrip(".")
    return any(h == x or h.endswith("." + x) for x in HOSTS)


def url_hit(u):
    m = re.match(r"^[a-z-]+://([^/:?#]+)", u or "", re.I)
    return bool(m) and host_hit(m.group(1))


def db(path):
    c = sqlite3.connect(path)
    c.create_function("hit", 1, lambda u: url_hit(u))
    c.create_function("hhit", 1, lambda h: host_hit(h))
    return c


def backup(path):
    if DO and os.path.exists(path):
        dst = BACKUP + path.replace(L, "")
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copy2(path, dst)


def run(path, label, count_sql, delete_sqls):
    if not os.path.exists(path):
        return
    try:
        c = db(path)
        n = c.execute(count_sql).fetchone()[0]
        print(f"  {label}: {n}")
        if DO and n:
            backup(path)
            for s in delete_sqls:
                c.execute(s)
            c.commit()
            c.execute("VACUUM")
        c.close()
    except Exception as e:
        print(f"  {label}: ERROR {e}")


def rm_dirs(paths, label):
    paths = [p for p in paths if os.path.exists(p)]
    print(f"  {label}: {len(paths)}")
    for p in paths:
        if DO:
            shutil.rmtree(p, ignore_errors=True) if os.path.isdir(p) else os.remove(p)


def chrome():
    for prof in glob.glob(L + "/Application Support/Google/Chrome/*/History"):
        d = os.path.dirname(prof)
        print(f"Chrome {os.path.basename(d)}")
        run(prof, "history", "select count(*) from urls where hit(url)",
            ["delete from visits where url in (select id from urls where hit(url))",
             "delete from keyword_search_terms where url_id in (select id from urls where hit(url))",
             "delete from urls where hit(url)"])
        run(d + "/Cookies", "cookies", "select count(*) from cookies where hhit(host_key)",
            ["delete from cookies where hhit(host_key)"])
        run(d + "/Login Data", "saved logins", "select count(*) from logins where hit(origin_url)",
            ["delete from logins where hit(origin_url)"])
        run(d + "/Favicons", "favicons", "select count(*) from icon_mapping where hit(page_url)",
            ["delete from icon_mapping where hit(page_url)"])
        rm_dirs([p for sub in ("IndexedDB", "File System", "databases")
                 for p in glob.glob(f"{d}/{sub}/*") if RX.search(os.path.basename(p))], "site storage")
        bm = d + "/Bookmarks"
        if os.path.exists(bm):
            data = json.load(open(bm))
            n = 0
            def prune(node):
                nonlocal n
                kids = node.get("children")
                if kids is not None:
                    keep = [k for k in kids if not (k.get("type") == "url" and url_hit(k.get("url")))]
                    n += len(kids) - len(keep)
                    node["children"] = keep
                    for k in keep:
                        prune(k)
            for root in data.get("roots", {}).values():
                if isinstance(root, dict):
                    prune(root)
            print(f"  bookmarks: {n}")
            if DO and n:
                backup(bm)
                data.pop("checksum", None)  # Chrome recomputes it
                json.dump(data, open(bm, "w"), indent=3)


def firefox():
    for prof in glob.glob(L + "/Application Support/Firefox/Profiles/*/"):
        print(f"Firefox {os.path.basename(prof.rstrip('/'))}")
        ids = "(select id from moz_places where hit(url))"
        run(prof + "places.sqlite", "history+bookmarks", "select count(*) from moz_places where hit(url)",
            [f"delete from moz_historyvisits where place_id in {ids}",
             f"delete from moz_bookmarks where fk in {ids}",
             f"delete from moz_annos where place_id in {ids}",
             f"delete from moz_inputhistory where place_id in {ids}",
             f"delete from moz_places where id in {ids}",
             "delete from moz_origins where hhit(host)"])
        run(prof + "cookies.sqlite", "cookies", "select count(*) from moz_cookies where hhit(host)",
            ["delete from moz_cookies where hhit(host)"])
        run(prof + "favicons.sqlite", "favicons", "select count(*) from moz_pages_w_icons where hit(page_url)",
            ["delete from moz_icons_to_pages where page_id in (select id from moz_pages_w_icons where hit(page_url))",
             "delete from moz_pages_w_icons where hit(page_url)"])
        run(prof + "permissions.sqlite", "site permissions", "select count(*) from moz_perms where hit(origin)",
            ["delete from moz_perms where hit(origin)"])
        rm_dirs([p for p in glob.glob(prof + "storage/default/*") if RX.search(os.path.basename(p))], "site storage")
        lj = prof + "logins.json"
        if os.path.exists(lj):
            data = json.load(open(lj))
            keep = [x for x in data.get("logins", []) if not url_hit(x.get("hostname"))]
            n = len(data.get("logins", [])) - len(keep)
            print(f"  saved logins: {n}")
            if DO and n:
                backup(lj)
                data["logins"] = keep
                json.dump(data, open(lj, "w"))


def binarycookies(path):
    """Rewrite Safari's Cookies.binarycookies without matching cookies. Returns removed count."""
    raw = open(path, "rb").read()
    assert raw[:4] == b"cook", "not a binarycookies file"
    npages = struct.unpack(">I", raw[4:8])[0]
    sizes = struct.unpack(f">{npages}I", raw[8:8 + 4 * npages])
    pos, kept, removed = 8 + 4 * npages, [], 0
    for size in sizes:
        page = raw[pos:pos + size]; pos += size
        n = struct.unpack("<I", page[4:8])[0]
        for off in struct.unpack(f"<{n}I", page[8:8 + 4 * n]):
            clen = struct.unpack("<I", page[off:off + 4])[0]
            cookie = page[off:off + clen]
            doff = struct.unpack("<I", cookie[16:20])[0]
            domain = cookie[doff:cookie.index(b"\0", doff)].decode("utf-8", "replace")
            if host_hit(domain):
                removed += 1
            else:
                kept.append(cookie)
    tail = raw[pos + 4:]  # skip old checksum; keep footer + metadata plist
    if not (DO and removed):
        return removed
    pages = []
    for i in range(0, len(kept), 100):
        chunk = kept[i:i + 100]
        head = 4 + 4 + 4 * len(chunk) + 4
        offs, body, o = [], b"", head
        for ck in chunk:
            offs.append(o); body += ck; o += len(ck)
        pages.append(b"\x00\x00\x01\x00" + struct.pack("<I", len(chunk)) +
                     struct.pack(f"<{len(chunk)}I", *offs) + b"\0\0\0\0" + body)
    checksum = sum(sum(p[j] for j in range(0, len(p), 4)) for p in pages) & 0xFFFFFFFF
    out = (b"cook" + struct.pack(">I", len(pages)) + b"".join(struct.pack(">I", len(p)) for p in pages)
           + b"".join(pages) + struct.pack(">I", checksum) + tail)
    backup(path)
    open(path, "wb").write(out)
    return removed


def safari():
    print("Safari")
    run(L + "/Safari/History.db", "history", "select count(*) from history_items where hit(url)",
        ["delete from history_visits where history_item in (select id from history_items where hit(url))",
         "delete from history_tombstones where hit(url)",
         "delete from history_items where hit(url)"])
    ck = L + "/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies"
    if os.path.exists(ck):
        try:
            print(f"  cookies: {binarycookies(ck)}")
        except Exception as e:
            print(f"  cookies: ERROR {e}")
    run(L + "/Containers/com.apple.Safari/Data/Library/WebKit/WebsiteData/ResourceLoadStatistics/observations.db",
        "tracking records", "select count(*) from ObservedDomains where hhit(registrableDomain)",
        ["PRAGMA foreign_keys=ON", "delete from ObservedDomains where hhit(registrableDomain)"])
    # Each site's storage folder holds an "origin" file naming the site.
    wd = L + "/Containers/com.apple.Safari/Data/Library/WebKit/WebsiteData/Default"
    hits = set()
    for f in glob.glob(wd + "/*/*/origin"):
        try:
            if RX.search(open(f, "rb").read().decode("latin-1")):
                hits.add(os.path.dirname(f))
        except OSError:
            pass
    rm_dirs(sorted(hits), "site storage")


def self_check():
    assert url_hit("https://chatgpt.com/c/1") and url_hit("https://cdn.oaistatic.com/x")
    assert not url_hit("https://notchatgpt.com/") and not url_hit("https://google.com/?q=chatgpt.com")
    assert host_hit(".openai.com") and not host_hit("openai.com.evil.net")


self_check()
ONLY_SAFARI = "--safari" in sys.argv
APPS = {"Google Chrome": "Google Chrome", "Firefox": "firefox", "Safari": "Safari"}
if ONLY_SAFARI:
    APPS = {"Safari": "Safari"}
if DO:
    for app in APPS:
        subprocess.run(["osascript", "-e", f'quit app "{app}"'], capture_output=True)
    for _ in range(20):
        if subprocess.run(["pgrep", "-x", "-q", "|".join(APPS.values())]).returncode:
            break
        time.sleep(1)
    else:
        sys.exit("A browser is still running; quit it and rerun.")
    print(f"Backups: {BACKUP}")
if not ONLY_SAFARI:
    chrome(); firefox()
safari()
print("Done." if DO else "(preview only, nothing changed)")
