#!/usr/bin/env python3
"""Parse Enough.xcodeproj/project.pbxproj the way Xcode 27 does.

Unquoted values may only use letters, digits, and ``_./-``. ``gnu++20`` is
rejected unless it is quoted. When ``plutil`` is on PATH, ``plutil -lint``
runs as well.
"""

import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "Enough.xcodeproj" / "project.pbxproj"
UNQUOTED_CHARS = set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_./-")


class ParseError(Exception):
    def __init__(self, message, line):
        super().__init__(f"{message} (line {line})")
        self.line = line


class Parser:
    def __init__(self, text):
        self.text = text
        self.n = len(text)
        self.i = 0
        self.line = 1

    def peek(self):
        return self.text[self.i] if self.i < self.n else ""

    def bump(self):
        ch = self.text[self.i]
        self.i += 1
        if ch == "\n":
            self.line += 1
        return ch

    def skip(self):
        while self.i < self.n:
            ch = self.peek()
            if ch in " \t\r\n":
                self.bump()
                continue
            if self.text.startswith("/*", self.i):
                end = self.text.find("*/", self.i + 2)
                if end < 0:
                    raise ParseError("unterminated comment", self.line)
                self.line += self.text.count("\n", self.i, end + 2)
                self.i = end + 2
                continue
            if self.text.startswith("//", self.i):
                while self.i < self.n and self.peek() != "\n":
                    self.i += 1
                continue
            return

    def parse(self):
        self.skip()
        value = self.parse_value()
        self.skip()
        if self.i != self.n:
            raise ParseError(f"trailing input {self.peek()!r}", self.line)
        return value

    def parse_value(self):
        self.skip()
        if self.i >= self.n:
            raise ParseError("unexpected end of file", self.line)
        ch = self.peek()
        if ch == "{":
            return self.parse_dict()
        if ch == "(":
            return self.parse_array()
        if ch == '"':
            return self.parse_quoted()
        if ch in UNQUOTED_CHARS:
            return self.parse_unquoted()
        raise ParseError(f"unexpected character {ch!r} in an unquoted value", self.line)

    def parse_unquoted(self):
        start_line = self.line
        start = self.i
        while self.i < self.n:
            ch = self.peek()
            if ch in " \t\r\n{}()=,;\"":
                break
            if ch not in UNQUOTED_CHARS:
                snippet = self.text[start:self.i + 1]
                raise ParseError(
                    f"unquoted value {snippet!r} contains special character {ch!r}; quote it",
                    start_line,
                )
            self.bump()
        if self.i == start:
            raise ParseError("expected a value", start_line)
        return self.text[start:self.i]

    def parse_quoted(self):
        start_line = self.line
        self.bump()
        chars = []
        while self.i < self.n:
            ch = self.bump()
            if ch == '"':
                return "".join(chars)
            if ch == "\\":
                if self.i >= self.n:
                    raise ParseError("unterminated escape", self.line)
                chars.append(self.bump())
                continue
            chars.append(ch)
        raise ParseError("unterminated string", start_line)

    def parse_dict(self):
        self.bump()
        result = {}
        while True:
            self.skip()
            if self.peek() == "}":
                self.bump()
                return result
            key = self.parse_key()
            self.skip()
            if self.peek() != "=":
                raise ParseError(f"expected '=' after {key!r}", self.line)
            self.bump()
            result[key] = self.parse_value()
            self.skip()
            if self.peek() != ";":
                raise ParseError("expected ';' after dictionary entry", self.line)
            self.bump()

    def parse_key(self):
        self.skip()
        if self.peek() == '"':
            return self.parse_quoted()
        if self.peek() in UNQUOTED_CHARS:
            return self.parse_unquoted()
        raise ParseError(f"expected a key, found {self.peek()!r}", self.line)

    def parse_array(self):
        self.bump()
        items = []
        while True:
            self.skip()
            if self.peek() == ")":
                self.bump()
                return items
            items.append(self.parse_value())
            self.skip()
            if self.peek() == ",":
                self.bump()
                continue
            if self.peek() == ")":
                continue
            raise ParseError("expected ',' or ')' in array", self.line)


def parse_pbxproj(text):
    return Parser(text).parse()


def self_test():
    bad = '{ CLANG_CXX_LANGUAGE_STANDARD = gnu++20; }\n'
    good = '{ CLANG_CXX_LANGUAGE_STANDARD = "gnu++20"; }\n'
    try:
        parse_pbxproj(bad)
    except ParseError as error:
        if "+" not in str(error):
            raise SystemExit(f"self-test: error did not mention '+': {error}")
    else:
        raise SystemExit("self-test: unquoted gnu++20 was accepted")
    parsed = parse_pbxproj(good)
    if parsed.get("CLANG_CXX_LANGUAGE_STANDARD") != "gnu++20":
        raise SystemExit(f"self-test: quoted value parsed as {parsed!r}")


def lint_with_plutil(path):
    plutil = shutil.which("plutil")
    if not plutil:
        print("plutil is not installed; the built-in pbxproj parser was used")
        return
    result = subprocess.run([plutil, "-lint", str(path)], capture_output=True, text=True)
    output = (result.stdout or "") + (result.stderr or "")
    if result.returncode != 0:
        sys.stderr.write(output)
        raise SystemExit(result.returncode)
    print(output.strip() or f"{plutil} -lint OK")


def main():
    self_test()
    if not PROJECT.is_file():
        raise SystemExit(f"missing {PROJECT}")
    try:
        parse_pbxproj(PROJECT.read_text(encoding="utf-8"))
    except ParseError as error:
        raise SystemExit(f"{PROJECT}: {error}")
    print(f"parsed {PROJECT.relative_to(ROOT)}")
    lint_with_plutil(PROJECT)


if __name__ == "__main__":
    main()
