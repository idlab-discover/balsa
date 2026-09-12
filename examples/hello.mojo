"""Smoke-check the Balsa package import and Mojo toolchain."""

import balsa


def main():
    print("Balsa", balsa.__version__)
    print("Native Treelite v4 checkpoint I/O and validation.")
