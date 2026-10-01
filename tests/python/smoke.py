"""Runtime checks for python.com sockets."""
import socket


def check_getsockname():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        host, port = sock.getsockname()
    if host != "127.0.0.1" or port <= 0:
        raise AssertionError(f"unexpected getsockname result: {(host, port)}")


def check_localhost():
    infos = socket.getaddrinfo("localhost", 80, socket.AF_INET, socket.SOCK_STREAM)
    if not infos or infos[0][4][0] != "127.0.0.1":
        raise AssertionError(f"localhost did not resolve to 127.0.0.1: {infos}")


def check_socketpair():
    left, right = socket.socketpair()
    try:
        left.sendall(b"ping")
        data = right.recv(4)
    finally:
        left.close()
        right.close()
    if data != b"ping":
        raise AssertionError(f"socketpair payload mismatch: {data!r}")


def check_loopback():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as server:
        server.bind(("127.0.0.1", 0))
        server.listen(1)
        port = server.getsockname()[1]
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as client:
            client.connect(("127.0.0.1", port))
            conn, _addr = server.accept()
            with conn:
                client.sendall(b"ok")
                data = conn.recv(2)
    if data != b"ok":
        raise AssertionError(f"loopback payload mismatch: {data!r}")


def main():
    check_getsockname()
    check_localhost()
    check_socketpair()
    check_loopback()
    print("python socket smoke: ok")


if __name__ == "__main__":
    main()
