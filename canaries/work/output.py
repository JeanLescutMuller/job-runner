#!/usr/bin/env python3
# The work of canaries.output: a Success; its summary "SUMMARY <img …> …" must show escaped on the dashboard
import sys
out = sys.stdout.buffer
for i in range(20000):
    out.write(f"line {i:05d} {'x' * 90}\n".encode())
out.write(b"y" * 200_000 + b"\n")
out.write("unicode: é ü 中文 \U0001F680\n".encode())
out.write(b"invalid utf-8: \xff\xfe\xc3 NUL: \x00 end\n")
out.write(b"progress 10%\rprogress 50%\rprogress 100%\n")
for i in range(1, 5):
    out.write(f"SUMMARY part {i}\n".encode())
out.write(("SUMMARY <img src=x onerror=alert(1)> & \"double\" 'single' " + "z" * 400 + "\n").encode())
out.flush()
sys.stderr.write("a warning on stderr\n")
sys.stderr.flush()
out.write(b"last line without newline")
