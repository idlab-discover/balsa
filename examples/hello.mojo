"""Smoke-check the Balsa package import and Mojo toolchain."""

from balsa import version


def main():
    print("Balsa", version())
    print("Native Treelite v4 checkpoint I/O and validation.")
