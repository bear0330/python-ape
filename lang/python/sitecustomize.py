import sys


def _onlyzippaths():
    L = []
    known_paths = set()
    for dir0 in sys.path:
        if dir0 not in known_paths and dir0.startswith("/zip/"):
            L.append(dir0)
            known_paths.add(dir0)
    sys.path[:] = L
    return known_paths


_onlyzippaths()

import contextlib
import errno
import ipaddress
import json
import random
import socket
import ssl
import struct
import time
import urllib.request
from concurrent.futures import FIRST_COMPLETED, ThreadPoolExecutor, wait

# Cosmopolitan often fails getaddrinfo("localhost") with EAI_NONAME even when
# numeric addresses and external names work. getsockname is required by the
# socketpair fallback below; the C build forces that method on.
_DNS_SERVERS = ("1.1.1.1", "8.8.8.8")
_DOH_ENDPOINTS = (
    "https://1.1.1.1/dns-query",
    "https://dns.google/dns-query",
)
_CACHE_TTL = 300.0
_NEG_TTL = 120.0
_SYS_FAIL_THRESHOLD = 2
_SYS_FAIL_COOLDOWN = 60.0
_MAX_WORKERS = 4

_orig_getaddrinfo = socket.getaddrinfo
_unverified_ctx = ssl._create_unverified_context()
_POS_CACHE = {}
_NEG_CACHE = {}
_SYS_FAIL = {}
_TRANSIENT = {
    getattr(socket, "EAI_NONAME", -2),
    getattr(socket, "EAI_NODATA", -5),
    getattr(socket, "EAI_AGAIN", -3),
}


def _now():
    return time.monotonic()


def _is_ip_literal(host):
    try:
        ipaddress.ip_address(host)
        return True
    except ValueError:
        return False


def _cache_get(host, family):
    key = (host, family)
    entry = _POS_CACHE.get(key)
    if entry and entry[0] > _now():
        return entry[1]
    if entry:
        _POS_CACHE.pop(key, None)
    negative = _NEG_CACHE.get(key)
    if negative and negative > _now():
        return []
    if negative:
        _NEG_CACHE.pop(key, None)
    return None


def _cache_put_pos(host, family, ips, ttl=_CACHE_TTL):
    _POS_CACHE[(host, family)] = (_now() + ttl, list(ips))
    _NEG_CACHE.pop((host, family), None)


def _cache_put_neg(host, family, ttl=_NEG_TTL):
    _NEG_CACHE[(host, family)] = _now() + ttl
    _POS_CACHE.pop((host, family), None)


def _sys_can_try(host, family):
    _fail, until_ts = _SYS_FAIL.get((host, family), (0, 0.0))
    return _now() >= until_ts


def _sys_on_success(host, family):
    _SYS_FAIL.pop((host, family), None)


def _sys_on_transient_fail(host, family):
    fail, until_ts = _SYS_FAIL.get((host, family), (0, 0.0))
    fail += 1
    if fail >= _SYS_FAIL_THRESHOLD:
        until_ts = _now() + _SYS_FAIL_COOLDOWN
    _SYS_FAIL[(host, family)] = (fail, until_ts)


def _build_query(qname, qtype, qclass=1):
    tid = random.randint(0, 0xffff)
    flags = 0x0100
    header = struct.pack("!HHHHHH", tid, flags, 1, 0, 0, 0)
    parts = qname.split(b".")
    question = b"".join(struct.pack("B", len(part)) + part for part in parts) + b"\x00"
    question += struct.pack("!HH", qtype, qclass)
    return header + question


def _parse_reply_a_aaaa(data, qtype):
    if len(data) < 12:
        return []
    _tid, _flags, qdcount, ancount = struct.unpack("!HHHH", data[:8])
    pos = 12
    for _question in range(qdcount):
        while data[pos] != 0:
            pos += data[pos] + 1
        pos += 5
    found = []
    for _answer in range(ancount):
        if data[pos] & 0xC0 == 0xC0:
            pos += 2
        else:
            while data[pos] != 0:
                pos += data[pos] + 1
            pos += 1
        rtype, rclass, _ttl, rdlen = struct.unpack("!HHIH", data[pos:pos + 10])
        pos += 10
        if rclass == 1 and rtype == qtype:
            if qtype == 1 and rdlen == 4:
                found.append(".".join(str(byte) for byte in data[pos:pos + 4]))
            elif qtype == 28 and rdlen == 16:
                found.append(str(ipaddress.IPv6Address(data[pos:pos + 16])))
        pos += rdlen
    return found


def _udp_dns(name, qtype, timeout=2.0):
    query = _build_query(name.encode(), qtype=qtype)
    for nameserver in _DNS_SERVERS:
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
                sock.settimeout(timeout)
                sock.sendto(query, (nameserver, 53))
                data, _addr = sock.recvfrom(1500)
            found = _parse_reply_a_aaaa(data, qtype)
            if found:
                return found
        except (socket.timeout, OSError):
            continue
    return []


def _doh_json(name, qtype, timeout=3.0):
    record_type = "A" if qtype == 1 else "AAAA"
    for endpoint in _DOH_ENDPOINTS:
        try:
            url = f"{endpoint}?name={name}&type={record_type}"
            request = urllib.request.Request(url, headers={
                "accept": "application/dns-json",
                "user-agent": "py",
            })
            with urllib.request.urlopen(request, timeout=timeout, context=_unverified_ctx) as response:
                data = json.load(response)
            if data.get("Status") == 0 and "Answer" in data:
                found = []
                for record in data["Answer"]:
                    if record.get("type") == (1 if qtype == 1 else 28):
                        found.append(record.get("data"))
                if found:
                    return found
        except Exception:
            continue
    return []


_EXEC = ThreadPoolExecutor(max_workers=_MAX_WORKERS)


def _concurrent_resolve(host, family):
    want_a = family in (0, socket.AF_INET)
    want_aaaa = family in (0, socket.AF_INET6)
    futures = []
    if want_a:
        futures.append(_EXEC.submit(_udp_dns, host, 1))
        futures.append(_EXEC.submit(_doh_json, host, 1))
    if want_aaaa:
        futures.append(_EXEC.submit(_udp_dns, host, 28))
        futures.append(_EXEC.submit(_doh_json, host, 28))

    got_a, got_aaaa = [], []
    done, pending = wait(futures, timeout=0.5, return_when=FIRST_COMPLETED)
    for future in list(done):
        found = future.result() or []
        if found:
            if any(len(ip.split(".")) == 4 for ip in found):
                got_a.extend([ip for ip in found if ip])
            else:
                got_aaaa.extend([ip for ip in found if ip])
    if pending:
        done_later, _pending = wait(pending, timeout=2.0)
        for future in list(done_later):
            found = future.result() or []
            if found:
                if any(len(ip.split(".")) == 4 for ip in found):
                    got_a.extend([ip for ip in found if ip])
                else:
                    got_aaaa.extend([ip for ip in found if ip])

    got_a = list(dict.fromkeys(got_a))
    got_aaaa = list(dict.fromkeys(got_aaaa))
    if family == socket.AF_INET6:
        return got_aaaa
    if family == socket.AF_INET:
        return got_a
    return got_a + got_aaaa


def smart_getaddrinfo(host, port, family=0, type=0, proto=0, flags=0):
    if host == "localhost":
        ip = "127.0.0.1" if family != socket.AF_INET6 else "::1"
        return _orig_getaddrinfo(ip, port, family, type, proto, flags)
    if _is_ip_literal(host):
        return _orig_getaddrinfo(host, port, family, type, proto, flags)

    cached = _cache_get(host, family)
    if cached is not None:
        if cached:
            for ip in cached:
                try:
                    return _orig_getaddrinfo(ip, port, family, type, proto, flags)
                except socket.gaierror:
                    continue
        else:
            raise socket.gaierror(socket.EAI_AGAIN, "cached negative answer")

    if _sys_can_try(host, family):
        try:
            result = _orig_getaddrinfo(host, port, family, type, proto, flags)
            ips = []
            for af, _socktype, _proto, _canonname, sockaddr in result:
                if af in (socket.AF_INET, socket.AF_INET6):
                    ips.append(sockaddr[0])
            if ips:
                _cache_put_pos(host, family, list(dict.fromkeys(ips)))
            _sys_on_success(host, family)
            return result
        except socket.gaierror as exc:
            if exc.errno in _TRANSIENT:
                _sys_on_transient_fail(host, family)
            else:
                raise

    ips = _concurrent_resolve(host, family)
    if ips:
        _cache_put_pos(host, family, ips)
        for ip in ips:
            try:
                return _orig_getaddrinfo(ip, port, family, type, proto, flags)
            except socket.gaierror:
                continue

    _cache_put_neg(host, family)
    raise socket.gaierror(socket.EAI_AGAIN, "Temporary failure in name resolution")


socket.getaddrinfo = smart_getaddrinfo


def _tcp_socketpair():
    """Loopback TCP pair for Cosmopolitan, where AF_UNIX socketpair can raise EBADF."""
    with contextlib.closing(socket.socket(socket.AF_INET, socket.SOCK_STREAM)) as listener:
        listener.bind(("127.0.0.1", 0))
        listener.listen(1)
        addr = listener.getsockname()

        peer = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        peer.setblocking(False)
        try:
            peer.connect(addr)
        except (BlockingIOError, InterruptedError):
            pass

        accepted, _addr = listener.accept()
        peer.setblocking(True)
        return accepted, peer


_orig_socketpair = getattr(socket, "socketpair", None)


def safe_socketpair(*args, **kwargs):
    if _orig_socketpair:
        try:
            return _orig_socketpair(*args, **kwargs)
        except OSError as exc:
            if exc.errno not in (
                errno.ENOSYS,
                errno.EAFNOSUPPORT,
                errno.EOPNOTSUPP,
                errno.EINVAL,
                errno.EBADF,
            ):
                raise
    return _tcp_socketpair()


socket.socketpair = safe_socketpair
